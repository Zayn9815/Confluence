import Foundation
import SwiftUI
import UIKit
import WebKit
import SignalEngine

/// Pure deterministic mapper from canonical Confluence symbols & timeframes to
/// TradingView widget-safe symbols, deep-link URLs, web fallback URLs, and Advanced Chart embed HTML.
public enum TradingViewSymbolMapper: Sendable {

    private static let explicitMap: [String: String] = [
        // Crypto
        "BTC/USDT": "BINANCE:BTCUSDT",
        "ETH/USDT": "BINANCE:ETHUSDT",
        "SOL/USDT": "BINANCE:SOLUSDT",
        // Forex
        "EUR/USD": "OANDA:EURUSD",
        "GBP/USD": "OANDA:GBPUSD",
        "USD/JPY": "OANDA:USDJPY",
        // Gold / Metals
        "XAU/USD": "OANDA:XAUUSD",
        // Indices (widget-safe CFD symbols avoid delayed exchange restrictions)
        "US500": "OANDA:SPX500USD",
        "NAS100": "OANDA:NAS100USD",
        // Index ETFs & US Stocks
        "SPY": "AMEX:SPY",
        "QQQ": "NASDAQ:QQQ",
        "AAPL": "NASDAQ:AAPL",
        "NVDA": "NASDAQ:NVDA",
        "MSFT": "NASDAQ:MSFT"
    ]

    public static func tradingViewSymbol(for canonicalSymbol: String) -> String {
        let normalized = canonicalSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let mapped = explicitMap[normalized] {
            return mapped
        }
        if normalized.hasSuffix("/USDT") {
            let compact = normalized.replacingOccurrences(of: "/", with: "")
            return "BINANCE:\(compact)"
        }
        if normalized.contains("/") {
            let compact = normalized.replacingOccurrences(of: "/", with: "")
            return "OANDA:\(compact)"
        }
        return normalized
    }

    public static func interval(for timeframe: Timeframe) -> String {
        switch timeframe {
        case .m15: return "15"
        case .m30: return "30"
        case .h1: return "60"
        case .h4: return "240"
        case .d1: return "D"
        }
    }

    public static func deepLinkURL(for canonicalSymbol: String, timeframe: Timeframe? = nil) -> URL? {
        let tvSymbol = tradingViewSymbol(for: canonicalSymbol)
        var components = URLComponents()
        components.scheme = "tradingview"
        components.host = "chart"
        var items = [URLQueryItem(name: "symbol", value: tvSymbol)]
        if let tf = timeframe {
            items.append(URLQueryItem(name: "interval", value: interval(for: tf)))
        }
        components.queryItems = items
        return components.url
    }

    public static func webFallbackURL(for canonicalSymbol: String, timeframe: Timeframe? = nil) -> URL? {
        let tvSymbol = tradingViewSymbol(for: canonicalSymbol)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.tradingview.com"
        components.path = "/chart/"
        var items = [URLQueryItem(name: "symbol", value: tvSymbol)]
        if let tf = timeframe {
            items.append(URLQueryItem(name: "interval", value: interval(for: tf)))
        }
        components.queryItems = items
        return components.url
    }

    /// Official TradingView Advanced Chart embed snippet with visible TradingView attribution.
    public static func embedHTML(
        symbol canonicalSymbol: String,
        timeframe: Timeframe,
        isDark: Bool,
        chartPalette: ConfluenceChartPalette? = nil
    ) -> String {
        let tvSymbol = tradingViewSymbol(for: canonicalSymbol)
        let tvInterval = interval(for: timeframe)
        let theme = isDark ? "dark" : "light"
        let bgHex = chartPalette?.background.hexString ?? (isDark ? "#0B0E14" : "#F8F7F4")
        let textHex = chartPalette?.axisText.hexString ?? (isDark ? "#9CA7BA" : "#5A6577")

        // Strict symbol character whitelist to prevent HTML/JS injection inside <script>
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:_.-/")
        let safeSymbol = String(tvSymbol.unicodeScalars.filter { allowed.contains($0) })

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: \(bgHex);
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            }
            .tradingview-widget-container {
              width: 100%;
              height: 100%;
              display: flex;
              flex-direction: column;
            }
            .tradingview-widget-container__widget {
              flex: 1 1 auto;
              width: 100%;
              min-height: 0;
            }
            .tradingview-widget-copyright {
              font-size: 11px;
              line-height: 18px;
              text-align: center;
              padding: 4px 8px;
              color: \(textHex);
              background: \(bgHex);
            }
            .tradingview-widget-copyright a {
              color: #2962FF;
              text-decoration: none;
            }
          </style>
        </head>
        <body>
          <div class="tradingview-widget-container">
            <div class="tradingview-widget-container__widget"></div>
            <div class="tradingview-widget-copyright">
              <a href="https://www.tradingview.com/" rel="noopener nofollow" target="_blank">Track all markets on TradingView</a>
            </div>
            <script type="text/javascript" src="https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js" async>
            {
              "autosize": true,
              "symbol": "\(safeSymbol)",
              "interval": "\(tvInterval)",
              "timezone": "Etc/UTC",
              "theme": "\(theme)",
              "style": "1",
              "locale": "en",
              "allow_symbol_change": false,
              "hide_top_toolbar": false,
              "hide_legend": false,
              "save_image": false,
              "calendar": false,
              "support_host": "https://www.tradingview.com"
            }
            </script>
          </div>
        </body>
        </html>
        """
    }
}

/// Lazy `WKWebView` wrapper hosting the official TradingView Advanced Chart embed.
/// Instantiated ONLY when the user explicitly selects the TradingView chart tab,
/// and torn down cleanly via `dismantleUIView` on dismissal or mode switch.
public struct TradingViewWidgetView: UIViewRepresentable {
    public let symbol: String
    public let timeframe: Timeframe
    public let isDark: Bool
    public let chartPalette: ConfluenceChartPalette?

    public init(symbol: String, timeframe: Timeframe, isDark: Bool, chartPalette: ConfluenceChartPalette? = nil) {
        self.symbol = symbol
        self.timeframe = timeframe
        self.isDark = isDark
        self.chartPalette = chartPalette
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        applyBackground(to: webView, isDark: isDark)
        loadIfNeeded(webView: webView, coordinator: context.coordinator)
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        applyBackground(to: uiView, isDark: isDark)
        loadIfNeeded(webView: uiView, coordinator: context.coordinator)
    }

    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.loadHTMLString("", baseURL: nil)
        coordinator.lastLoadedKey = nil
    }

    private func applyBackground(to webView: WKWebView, isDark: Bool) {
        let bg = chartPalette?.background.uiColor ?? (isDark
            ? UIColor(red: 11.0 / 255.0, green: 14.0 / 255.0, blue: 20.0 / 255.0, alpha: 1.0)
            : UIColor(red: 248.0 / 255.0, green: 247.0 / 255.0, blue: 244.0 / 255.0, alpha: 1.0))
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg
    }

    private func loadIfNeeded(webView: WKWebView, coordinator: Coordinator) {
        let tvSymbol = TradingViewSymbolMapper.tradingViewSymbol(for: symbol)
        let tvInterval = TradingViewSymbolMapper.interval(for: timeframe)
        let bgHex = chartPalette?.background.hexString ?? (isDark ? "#0B0E14" : "#F8F7F4")
        let key = "\(tvSymbol)|\(tvInterval)|\(isDark)|\(bgHex)"
        guard coordinator.lastLoadedKey != key else { return }
        coordinator.lastLoadedKey = key
        let html = TradingViewSymbolMapper.embedHTML(
            symbol: symbol,
            timeframe: timeframe,
            isDark: isDark,
            chartPalette: chartPalette
        )
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.tradingview.com"))
    }

    @MainActor
    public final class Coordinator {
        var lastLoadedKey: String?
    }
}
