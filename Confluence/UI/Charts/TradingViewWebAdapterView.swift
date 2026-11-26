import Foundation
import SwiftUI
import UIKit
import WebKit
import Observation
import SignalEngine

// MARK: - LiveContainer-Proof Cookie Vault Record

private struct PersistedWebCookieRecord: Codable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresEpochSeconds: TimeInterval?
    let isSecure: Bool
    let isHTTPOnly: Bool
    let sameSitePolicy: String?
    let version: Int

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresEpochSeconds = cookie.expiresDate?.timeIntervalSince1970
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = cookie.isHTTPOnly
        self.sameSitePolicy = cookie.sameSitePolicy?.rawValue
        self.version = cookie.version
    }

    func toHTTPCookie(nowEpochSeconds: TimeInterval) -> HTTPCookie? {
        if let exp = expiresEpochSeconds, exp <= nowEpochSeconds {
            return nil
        }
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .version: version
        ]
        if let exp = expiresEpochSeconds {
            props[.expires] = Date(timeIntervalSince1970: exp)
        }
        if isSecure {
            props[.secure] = "TRUE"
        }
        if isHTTPOnly {
            props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        if let sameSite = sameSitePolicy, !sameSite.isEmpty {
            props[.sameSitePolicy] = sameSite
        }
        return HTTPCookie(properties: props)
    }
}

// MARK: - Leak-Free Script Message Handler

@MainActor
private final class WeakTVScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: TradingViewWebSessionManager?

    init(owner: TradingViewWebSessionManager) {
        self.owner = owner
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        owner?.handleScriptMessage(name: message.name, body: message.body)
    }
}

// MARK: - MainActor WebKit Delegate Bridge

@MainActor
private final class TradingViewWebDelegateProxy: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    weak var manager: TradingViewWebSessionManager?

    init(manager: TradingViewWebSessionManager) {
        self.manager = manager
        super.init()
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        let preferDesktop = manager?.preferDesktop ?? false
        preferences.preferredContentMode = preferDesktop ? .desktop : .mobile
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        manager?.handleNavigationStart()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        manager?.handleObservedURL(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        manager?.handleNavigationFinish(url: webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        manager?.handleNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        manager?.handleNavigationError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        manager?.handleWebContentProcessTerminated()
    }

    // MARK: WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        await presentAlert(message: message)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        await presentConfirm(message: message)
    }

    // MARK: WKHTTPCookieStoreObserver

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        manager?.scheduleCookieVaultFlush()
    }

    // MARK: Scene-Safe Alert Presentation (Never UIApplication.shared.windows)

    private func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private func presentAlert(message: String) async {
        guard let presenter = topMostViewController() else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: "TradingView", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })
            presenter.present(alert, animated: true)
        }
    }

    private func presentConfirm(message: String) async -> Bool {
        guard let presenter = topMostViewController() else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let alert = UIAlertController(title: "TradingView", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alert, animated: true)
        }
    }
}

// MARK: - Persistent TradingView Full Web Session Manager

/// Singleton persistent `WKWebView` session manager for **TradingView Full Web**.
/// - Lazily constructs the `WKWebView` ONLY when the user selects the `TradingView Web` engine.
/// - Preserves TradingView login, chart layouts, drawings, and watchlists across sheet dismissals,
///   app restarts, SideStore re-signs, and LiveContainer launches via an atomic JSON Cookie Vault
///   at `Application Support/tv_session_cookies.json` (never touching `Cookies.binarycookies` and
///   never hardcoding bundle IDs).
/// - Injects CSS/JS to suppress mobile web "Open in App" nag banners and enable 1-tap Clean Chart Mode.
@MainActor
@Observable
public final class TradingViewWebSessionManager {
    public static let shared = TradingViewWebSessionManager()

    public private(set) var canGoBack: Bool = false
    public private(set) var canGoForward: Bool = false
    public private(set) var estimatedProgress: Double = 0
    public private(set) var isLoading: Bool = false
    public private(set) var currentURL: URL? = nil
    public private(set) var loadErrorMessage: String? = nil
    public private(set) var isCleanModeEnabled: Bool = false
    public private(set) var preferDesktop: Bool = false

    private var webView: WKWebView?
    private var delegateProxy: TradingViewWebDelegateProxy?
    private var scriptHandler: WeakTVScriptMessageHandler?
    private var urlObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?
    private var hasLoadedInitialPage: Bool = false
    private var cookieFlushTask: Task<Void, Never>?

    private static let cookieVaultFileName = "tv_session_cookies.json"
    private static let scriptBridgeName = "confluenceBridge"
    private static let defaultChartURLString = "https://www.tradingview.com/chart/"
    private static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private init() {}

    // MARK: - Lazy WebView Lifecycle

    /// Returns the persistent `WKWebView`, creating it lazily and restoring any saved session cookies
    /// before firing the initial navigation.
    public func obtainWebView(
        initialSymbol: String,
        initialTimeframe: Timeframe,
        preferDesktop: Bool,
        isDark: Bool
    ) -> WKWebView {
        self.preferDesktop = preferDesktop
        if let existing = webView {
            applyTheme(isDark: isDark, to: existing)
            if !hasLoadedInitialPage {
                seedCookiesAndLoadInitial(
                    webView: existing,
                    fallbackSymbol: initialSymbol,
                    fallbackTimeframe: initialTimeframe
                )
            }
            return existing
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences.preferredContentMode = preferDesktop ? .desktop : .mobile
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let contentController = WKUserContentController()
        let userScript = WKUserScript(
            source: Self.injectedAugmentationJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        contentController.addUserScript(userScript)

        let bridge = WeakTVScriptMessageHandler(owner: self)
        self.scriptHandler = bridge
        contentController.add(bridge, name: Self.scriptBridgeName)
        config.userContentController = contentController

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = Self.safariUserAgent
        wv.allowsBackForwardNavigationGestures = false
        wv.isOpaque = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        applyTheme(isDark: isDark, to: wv)

        let proxy = TradingViewWebDelegateProxy(manager: self)
        self.delegateProxy = proxy
        wv.navigationDelegate = proxy
        wv.uiDelegate = proxy
        config.websiteDataStore.httpCookieStore.add(proxy)

        installObservers(on: wv)
        self.webView = wv

        seedCookiesAndLoadInitial(
            webView: wv,
            fallbackSymbol: initialSymbol,
            fallbackTimeframe: initialTimeframe
        )
        return wv
    }

    public func updateAppearance(isDark: Bool) {
        guard let wv = webView else { return }
        applyTheme(isDark: isDark, to: wv)
    }

    public func setPreferDesktop(_ newValue: Bool) {
        guard preferDesktop != newValue else { return }
        preferDesktop = newValue
        if let wv = webView {
            wv.configuration.defaultWebpagePreferences.preferredContentMode = newValue ? .desktop : .mobile
            wv.reload()
        }
    }

    public func setCleanMode(_ enabled: Bool) {
        isCleanModeEnabled = enabled
        applyCleanModeJS()
    }

    public func toggleCleanMode() {
        setCleanMode(!isCleanModeEnabled)
    }

    // MARK: - Navigation & Sync Controls

    public func goBack() {
        webView?.goBack()
    }

    public func goForward() {
        webView?.goForward()
    }

    public func reload() {
        loadErrorMessage = nil
        if let wv = webView {
            if wv.url == nil {
                let target = savedChartURL() ?? URL(string: Self.defaultChartURLString)!
                wv.load(URLRequest(url: target))
            } else {
                wv.reload()
            }
        }
    }

    /// 1-tap **Sync Pair** action: navigates to the active Confluence symbol & timeframe while
    /// preserving any saved user chart layout path (`/chart/<layoutId>/`). Never called automatically.
    public func syncToSymbol(_ symbol: String, timeframe: Timeframe) {
        guard let wv = webView else { return }
        loadErrorMessage = nil
        let targetURL = Self.buildSyncURL(
            symbol: symbol,
            timeframe: timeframe,
            existingURL: currentURL ?? savedChartURL()
        )
        wv.load(URLRequest(url: targetURL))
    }

    /// Pure helper preserving `/chart/<layoutId>/` path while replacing `symbol` & `interval` query items.
    public static func buildSyncURL(
        symbol: String,
        timeframe: Timeframe,
        existingURL: URL?
    ) -> URL {
        let tvSymbol = TradingViewSymbolMapper.tradingViewSymbol(for: symbol)
        let tvInterval = TradingViewSymbolMapper.interval(for: timeframe)

        var basePath = "/chart/"
        if let url = existingURL,
           let host = url.host?.lowercased(),
           host.contains("tradingview.com"),
           url.path.hasPrefix("/chart") {
            basePath = url.path.isEmpty ? "/chart/" : url.path
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.tradingview.com"
        components.path = basePath
        components.queryItems = [
            URLQueryItem(name: "symbol", value: tvSymbol),
            URLQueryItem(name: "interval", value: tvInterval)
        ]
        return components.url ?? URL(string: defaultChartURLString)!
    }

    // MARK: - Cookie Vault Persistence (LiveContainer & SideStore Safe)

    /// Flushes `tradingview.com` cookies from `WKWebsiteDataStore.default().httpCookieStore`
    /// into `Application Support/tv_session_cookies.json` immediately on app backgrounding.
    public func flushCookieVaultOnBackground() {
        guard webView != nil else { return }
        cookieFlushTask?.cancel()
        Task { @MainActor [weak self] in
            await self?.persistCookiesNow()
        }
    }

    fileprivate func scheduleCookieVaultFlush() {
        cookieFlushTask?.cancel()
        cookieFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.persistCookiesNow()
        }
    }

    private func persistCookiesNow() async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let allCookies = await cookieStore.allCookies()
        let tvCookies = allCookies.filter { $0.domain.lowercased().contains("tradingview.com") }
        guard !tvCookies.isEmpty else { return }

        let records = tvCookies.map(PersistedWebCookieRecord.init(cookie:))
        guard let vaultURL = Self.cookieVaultFileURL() else { return }

        do {
            let dir = vaultURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: vaultURL, options: [.atomic])
        } catch {
            // Non-fatal: WebKit's default store still holds cookies in-process.
        }
    }

    private func reseedCookiesFromVault() async {
        guard let vaultURL = Self.cookieVaultFileURL(),
              let data = try? Data(contentsOf: vaultURL),
              let records = try? JSONDecoder().decode([PersistedWebCookieRecord].self, from: data),
              !records.isEmpty
        else { return }

        let now = Date().timeIntervalSince1970
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        for rec in records {
            if let cookie = rec.toHTTPCookie(nowEpochSeconds: now) {
                await cookieStore.setCookie(cookie)
            }
        }
    }

    private static func cookieVaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(cookieVaultFileName, isDirectory: false)
    }

    // MARK: - Complete Sign-Out & Cache Wipe

    /// Fully clears TradingView login session, cookies (both WebKit store and JSON Cookie Vault),
    /// saved last chart URL, and tears down the retained `WKWebView` so in-memory JS auth resets completely.
    public func clearSessionAndCache() async {
        cookieFlushTask?.cancel()
        cookieFlushTask = nil

        urlObservation?.invalidate()
        urlObservation = nil
        progressObservation?.invalidate()
        progressObservation = nil
        backObservation?.invalidate()
        forwardObservation?.invalidate()
        backObservation = nil
        forwardObservation = nil

        let store = WKWebsiteDataStore.default()
        if let proxy = delegateProxy {
            store.httpCookieStore.remove(proxy)
        }

        if let wv = webView {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
            wv.configuration.userContentController.removeScriptMessageHandler(forName: Self.scriptBridgeName)
            wv.removeFromSuperview()
        }
        webView = nil
        delegateProxy = nil
        scriptHandler = nil
        hasLoadedInitialPage = false
        canGoBack = false
        canGoForward = false
        estimatedProgress = 0
        isLoading = false
        currentURL = nil
        loadErrorMessage = nil

        // Delete persisted Cookie Vault file
        if let vaultURL = Self.cookieVaultFileURL() {
            try? FileManager.default.removeItem(at: vaultURL)
        }

        // Delete saved last chart URL
        UserDefaults.standard.removeObject(forKey: BackupArchiveService.tvLastChartURLDefaultsKey)

        // Remove all TradingView cookies & WebKit website data records
        let cookies = await store.httpCookieStore.allCookies()
        for cookie in cookies where cookie.domain.lowercased().contains("tradingview") {
            await store.httpCookieStore.deleteCookie(cookie)
        }

        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: allTypes)
        let tvRecords = records.filter { $0.displayName.lowercased().contains("tradingview") }
        if !tvRecords.isEmpty {
            await store.removeData(ofTypes: allTypes, for: tvRecords)
        }
    }

    // MARK: - Internal Delegate & Observer Callbacks

    private func seedCookiesAndLoadInitial(
        webView wv: WKWebView,
        fallbackSymbol: String,
        fallbackTimeframe: Timeframe
    ) {
        hasLoadedInitialPage = true
        let initialURL = savedChartURL()
            ?? TradingViewSymbolMapper.webFallbackURL(for: fallbackSymbol, timeframe: fallbackTimeframe)
            ?? URL(string: Self.defaultChartURLString)!

        Task { @MainActor [weak self, weak wv] in
            await self?.reseedCookiesFromVault()
            guard let wv else { return }
            wv.load(URLRequest(url: initialURL))
        }
    }

    private func installObservers(on wv: WKWebView) {
        urlObservation = wv.observe(\.url, options: [.new]) { [weak self] _, change in
            let nextURL = change.newValue ?? nil
            Task { @MainActor [weak self] in
                self?.handleObservedURL(nextURL)
            }
        }
        progressObservation = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            let prog = change.newValue ?? 0
            Task { @MainActor [weak self] in
                self?.estimatedProgress = prog
                self?.isLoading = (prog > 0 && prog < 1.0)
            }
        }
        backObservation = wv.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.canGoBack = value
            }
        }
        forwardObservation = wv.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.canGoForward = value
            }
        }
    }

    fileprivate func handleNavigationStart() {
        loadErrorMessage = nil
        isLoading = true
    }

    fileprivate func handleObservedURL(_ url: URL?) {
        guard let url else { return }
        currentURL = url
        persistChartURLIfEligible(url)
    }

    fileprivate func handleNavigationFinish(url: URL?) {
        isLoading = false
        estimatedProgress = 1.0
        loadErrorMessage = nil
        handleObservedURL(url)
        applyCleanModeJS()
        Task { @MainActor [weak self] in
            await self?.persistCookiesNow()
        }
    }

    fileprivate func handleNavigationError(_ error: Error) {
        isLoading = false
        let nsError = error as NSError
        // Ignore harmless navigation cancellation (-999) and WebKit frame load interrupted (102)
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            return
        }
        loadErrorMessage = nsError.localizedDescription
    }

    fileprivate func handleWebContentProcessTerminated() {
        guard let wv = webView else { return }
        let target = savedChartURL() ?? currentURL ?? URL(string: Self.defaultChartURLString)!
        Task { @MainActor [weak self, weak wv] in
            await self?.reseedCookiesFromVault()
            guard let wv else { return }
            wv.load(URLRequest(url: target))
        }
    }

    fileprivate func handleScriptMessage(name: String, body: Any) {
        guard name == Self.scriptBridgeName else { return }
        if let dict = body as? [String: Any],
           let href = dict["href"] as? String,
           let url = URL(string: href) {
            handleObservedURL(url)
        }
    }

    private func persistChartURLIfEligible(_ url: URL) {
        guard let host = url.host?.lowercased(),
              host.contains("tradingview.com"),
              url.path.hasPrefix("/chart")
        else { return }
        UserDefaults.standard.set(url.absoluteString, forKey: BackupArchiveService.tvLastChartURLDefaultsKey)
    }

    private func savedChartURL() -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: BackupArchiveService.tvLastChartURLDefaultsKey),
              let url = URL(string: raw),
              let host = url.host?.lowercased(),
              host.contains("tradingview.com"),
              url.path.hasPrefix("/chart")
        else { return nil }
        return url
    }

    private func applyTheme(isDark: Bool, to wv: WKWebView) {
        let bg = isDark
            ? UIColor(red: 11.0 / 255.0, green: 14.0 / 255.0, blue: 20.0 / 255.0, alpha: 1.0)
            : UIColor(red: 248.0 / 255.0, green: 247.0 / 255.0, blue: 244.0 / 255.0, alpha: 1.0)
        wv.backgroundColor = bg
        wv.scrollView.backgroundColor = bg
    }

    private func applyCleanModeJS() {
        guard let wv = webView else { return }
        let flag = isCleanModeEnabled ? "true" : "false"
        let js = """
        (function() {
          if (document && document.documentElement) {
            document.documentElement.classList.toggle('confluence-clean-mode', \(flag));
          }
        })();
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Injected CSS + JS Augmentation (Mobile App Banner Strip + Clean Mode)

    private static let injectedAugmentationJS: String = """
    (function() {
      if (window.__confluenceTVInjected) return;
      window.__confluenceTVInjected = true;

      var style = document.createElement('style');
      style.id = 'confluence-tv-augment-style';
      style.textContent = `
        /* Hide TradingView mobile web "Open in App / Get the Mobile App" nag banners without touching login dialogs */
        [data-name="mobile-app-banner"],
        [class*="mobileAppBanner"],
        [class*="appBanner"],
        [class*="openInApp"],
        [class*="smartBanner"],
        a[href*="tradingview.onelink.me"],
        div[class*="toast-wrapper"][class*="app"] {
          display: none !important;
          visibility: hidden !important;
          pointer-events: none !important;
          height: 0 !important;
          max-height: 0 !important;
          overflow: hidden !important;
        }

        /* 1-tap Clean Chart Mode: collapse non-essential marketing/footer chrome while preserving chart & drawing tools */
        html.confluence-clean-mode .tv-header,
        html.confluence-clean-mode [data-name="header-toolbar-promo"],
        html.confluence-clean-mode [class*="promoBanner"],
        html.confluence-clean-mode [class*="trialBanner"],
        html.confluence-clean-mode [class*="footer-chart-panel"] {
          display: none !important;
        }
      `;
      (document.head || document.documentElement).appendChild(style);

      function hideAppNags() {
        try {
          var candidates = document.querySelectorAll('div, section, aside');
          for (var i = 0; i < candidates.length; i++) {
            var el = candidates[i];
            if (!el || el.getAttribute('role') === 'dialog') continue;
            var txt = (el.innerText || '').trim();
            if (txt.length > 0 && txt.length < 140) {
              var lower = txt.toLowerCase();
              if ((lower.indexOf('open in app') !== -1 || lower.indexOf('get the mobile app') !== -1 || lower.indexOf('continue in app') !== -1) &&
                  lower.indexOf('sign in') === -1 && lower.indexOf('log in') === -1) {
                var rect = el.getBoundingClientRect();
                if (rect.height > 0 && rect.height < 130) {
                  el.style.setProperty('display', 'none', 'important');
                }
              }
            }
          }
        } catch (_) {}
      }

      hideAppNags();
      var observer = new MutationObserver(function() {
        hideAppNags();
      });
      if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true });
      }

      // Report SPA pushState / replaceState chart layout URL changes back to Swift
      var reportURL = function() {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.confluenceBridge) {
            window.webkit.messageHandlers.confluenceBridge.postMessage({ href: window.location.href });
          }
        } catch (_) {}
      };
      var origPush = history.pushState;
      history.pushState = function() {
        var r = origPush.apply(this, arguments);
        reportURL();
        return r;
      };
      var origReplace = history.replaceState;
      history.replaceState = function() {
        var r = origReplace.apply(this, arguments);
        reportURL();
        return r;
      };
      window.addEventListener('popstate', reportURL);
    })();
    """
}

// MARK: - Container-Hosted Persistent WKWebView Bridge

private struct TradingViewWebContainerView: UIViewRepresentable {
    let symbol: String
    let timeframe: Timeframe
    let preferDesktop: Bool
    let isDark: Bool

    func makeUIView(context: Context) -> UIView {
        let host = UIView(frame: .zero)
        host.backgroundColor = .clear
        attachPersistentWebView(to: host)
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let manager = TradingViewWebSessionManager.shared
        manager.updateAppearance(isDark: isDark)
        manager.setPreferDesktop(preferDesktop)
        attachPersistentWebView(to: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // Keep the WKWebView alive inside TradingViewWebSessionManager so login, layouts,
        // drawings, and watchlists persist across sheet dismissals. Only detach from this host.
        for subview in uiView.subviews where subview is WKWebView {
            subview.removeFromSuperview()
        }
    }

    private func attachPersistentWebView(to host: UIView) {
        let wv = TradingViewWebSessionManager.shared.obtainWebView(
            initialSymbol: symbol,
            initialTimeframe: timeframe,
            preferDesktop: preferDesktop,
            isDark: isDark
        )
        if wv.superview !== host {
            wv.removeFromSuperview()
            wv.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(wv)
            NSLayoutConstraint.activate([
                wv.topAnchor.constraint(equalTo: host.topAnchor),
                wv.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                wv.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor)
            ])
        }
    }
}

// MARK: - TradingView Full Web Adapter View (Liquid Glass Utility Bar + Signal HUD)

public struct TradingViewWebAdapterView: View {
    public let symbol: String
    public let timeframe: Timeframe
    public let overlayModel: ChartSignalOverlayModel
    public let pricePrecision: ChartPricePrecision
    public let palette: ConfluencePalette
    public let isDark: Bool
    @Binding public var preferDesktop: Bool

    @State private var showSignalHUD: Bool = true
    @AppStorage("tv_web_signin_tip_dismissed") private var isSignInTipDismissed: Bool = false

    private var session: TradingViewWebSessionManager {
        TradingViewWebSessionManager.shared
    }

    public init(
        symbol: String,
        timeframe: Timeframe,
        overlayModel: ChartSignalOverlayModel,
        pricePrecision: ChartPricePrecision,
        palette: ConfluencePalette,
        isDark: Bool,
        preferDesktop: Binding<Bool>
    ) {
        self.symbol = symbol
        self.timeframe = timeframe
        self.overlayModel = overlayModel
        self.pricePrecision = pricePrecision
        self.palette = palette
        self.isDark = isDark
        self._preferDesktop = preferDesktop
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Compact iOS 27 Liquid Glass utility bar
            HStack(spacing: 6) {
                Button {
                    session.syncToSymbol(symbol, timeframe: timeframe)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .bold))
                        Text("Sync \(symbol)")
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(palette.canvas)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(palette.champagneGold, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Group {
                    Button { session.goBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                    .disabled(!session.canGoBack)
                    .opacity(session.canGoBack ? 1.0 : 0.35)

                    Button { session.goForward() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                    .disabled(!session.canGoForward)
                    .opacity(session.canGoForward ? 1.0 : 0.35)

                    Button { session.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }

                    Button {
                        preferDesktop.toggle()
                        session.setPreferDesktop(preferDesktop)
                    } label: {
                        Image(systemName: preferDesktop ? "desktopcomputer" : "iphone")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(preferDesktop ? palette.champagneGold : palette.primaryInk)
                            .frame(width: 26, height: 26)
                    }
                    .accessibilityLabel(preferDesktop ? "Desktop Web Mode" : "Mobile Web Mode")

                    Button {
                        session.toggleCleanMode()
                    } label: {
                        Image(systemName: session.isCleanModeEnabled ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(session.isCleanModeEnabled ? palette.champagneGold : palette.primaryInk)
                            .frame(width: 26, height: 26)
                    }
                    .accessibilityLabel("Clean Chart Mode")

                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showSignalHUD.toggle()
                        }
                    } label: {
                        Image(systemName: showSignalHUD ? "eye.fill" : "eye.slash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(showSignalHUD ? palette.champagneGold : palette.secondaryInk)
                            .frame(width: 26, height: 26)
                    }
                    .accessibilityLabel("Toggle Signal HUD")
                }
                .foregroundStyle(palette.primaryInk)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .confluenceLiquidGlass(cornerRadius: 12, borderColor: palette.border)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(palette.surface)

            // Thin progress bar
            if session.isLoading && session.estimatedProgress > 0 && session.estimatedProgress < 1.0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(palette.champagneGold)
                        .frame(width: max(6, geo.size.width * CGFloat(session.estimatedProgress)))
                }
                .frame(height: 2)
                .background(palette.border.opacity(0.4))
            }

            // Dismissible 1-line Sign-In Tip
            if !isSignInTipDismissed {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.macroIceBlue)
                    Text("Sign in with TradingView email/username & password to keep layouts saved (Google blocks embedded WebView Sign-In).")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.secondaryInk)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button {
                        isSignInTipDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.tertiaryInk)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.macroIceBlue.opacity(0.10))
            }

            // Inline Offline / Error Retry Banner
            if let err = session.loadErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(palette.shortCrimson)
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(palette.primaryInk)
                        .lineLimit(2)
                    Spacer()
                    Button("Retry") {
                        session.reload()
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.canvas)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(palette.champagneGold, in: Capsule())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(palette.shortCrimson.opacity(0.14))
            }

            // Persistent WebView + Non-Blocking Floating Liquid Glass Signal Level HUD
            ZStack(alignment: .topLeading) {
                TradingViewWebContainerView(
                    symbol: symbol,
                    timeframe: timeframe,
                    preferDesktop: preferDesktop,
                    isDark: isDark
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showSignalHUD && overlayModel.hasAnyOverlayLevels {
                    ChartSignalOverlayHUD(
                        overlayModel: overlayModel,
                        precision: pricePrecision,
                        palette: palette,
                        engineBadge: "TV Full Web"
                    )
                    .padding(10)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
