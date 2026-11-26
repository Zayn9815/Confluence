import XCTest
import Foundation
@testable import Confluence
import SignalEngine

final class V15M6SettingsAndTradingViewTests: XCTestCase {

    // MARK: - W5: SettingsCopy Completeness & Whole-Word Case-Sensitive Jargon Check

    func testSettingsCopyEveryKeyHasNonEmptyCopyAndZeroRawJargon() {
        XCTAssertGreaterThanOrEqual(SettingHelpKey.allCases.count, 30)

        // Raw trading/engineering jargon tokens banned from user-facing labels, subtitles, and option labels.
        // Checked with whole-word, case-sensitive matching, ignoring "Confluence" and excluding `helpText`.
        let bannedTokens: [String] = [
            "FVG", "OB", "BOS", "MSS", "RVOL", "ATR", "HTF",
            "TP1", "TP2", "SL", "Take profit", "Platt", "Brier",
            "BGAppRefreshTask", "R:R", "SMC", "ICT", "COT", "OI",
            "AMOLED", "UTC", "JSON", "CSV", "Keychain", "API"
        ]

        func assertNoJargon(in text: String, context: String) {
            // Strip "Confluence" defensively per specification
            let cleaned = text.replacingOccurrences(of: "Confluence", with: "")
            for token in bannedTokens {
                let escaped = NSRegularExpression.escapedPattern(for: token)
                let pattern = "(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])"
                let regex = try? NSRegularExpression(pattern: pattern, options: [])
                let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                let match = regex?.firstMatch(in: cleaned, options: [], range: range)
                XCTAssertNil(
                    match,
                    "Found banned raw jargon token '\(token)' in \(context): \"\(text)\""
                )
            }
        }

        for key in SettingHelpKey.allCases {
            let c = key.copy
            XCTAssertFalse(
                c.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Empty label for \(key.rawValue)"
            )
            XCTAssertFalse(
                c.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Empty subtitle for \(key.rawValue)"
            )
            XCTAssertFalse(
                c.helpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Empty helpText for \(key.rawValue)"
            )

            assertNoJargon(in: c.label, context: "\(key.rawValue).label")
            assertNoJargon(in: c.subtitle, context: "\(key.rawValue).subtitle")
        }

        for optionLabel in SettingHelpKey.allPlainEnglishOptionLabels {
            XCTAssertFalse(optionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            assertNoJargon(in: optionLabel, context: "optionLabel")
        }
    }

    // MARK: - W6: TradingView Symbol Mapper, Intervals, URLs & Widget Embed HTML

    func testTradingViewSymbolMapperCoversAllWatchlistAssetsAndIntervals() {
        let expected: [String: String] = [
            "BTC/USDT": "BINANCE:BTCUSDT",
            "ETH/USDT": "BINANCE:ETHUSDT",
            "SOL/USDT": "BINANCE:SOLUSDT",
            "EUR/USD": "OANDA:EURUSD",
            "GBP/USD": "OANDA:GBPUSD",
            "USD/JPY": "OANDA:USDJPY",
            "XAU/USD": "OANDA:XAUUSD",
            "US500": "OANDA:SPX500USD",
            "NAS100": "OANDA:NAS100USD",
            "SPY": "AMEX:SPY",
            "QQQ": "NASDAQ:QQQ",
            "AAPL": "NASDAQ:AAPL",
            "NVDA": "NASDAQ:NVDA",
            "MSFT": "NASDAQ:MSFT"
        ]

        XCTAssertEqual(WatchlistDefaults.assets.count, expected.count)
        for asset in WatchlistDefaults.assets {
            let mapped = TradingViewSymbolMapper.tradingViewSymbol(for: asset.symbol)
            XCTAssertEqual(mapped, expected[asset.symbol], "Unexpected TradingView mapping for \(asset.symbol)")
            XCTAssertTrue(mapped.contains(":"), "Expected EXCHANGE:SYMBOL format for \(asset.symbol)")
        }

        // Fallback mapping for custom/unknown pairs
        XCTAssertEqual(TradingViewSymbolMapper.tradingViewSymbol(for: "ADA/USDT"), "BINANCE:ADAUSDT")
        XCTAssertEqual(TradingViewSymbolMapper.tradingViewSymbol(for: "AUD/USD"), "OANDA:AUDUSD")

        // Intervals
        XCTAssertEqual(TradingViewSymbolMapper.interval(for: .m15), "15")
        XCTAssertEqual(TradingViewSymbolMapper.interval(for: .m30), "30")
        XCTAssertEqual(TradingViewSymbolMapper.interval(for: .h1), "60")
        XCTAssertEqual(TradingViewSymbolMapper.interval(for: .h4), "240")
        XCTAssertEqual(TradingViewSymbolMapper.interval(for: .d1), "D")

        // Deep-link & HTTPS fallback URLs
        let deep = TradingViewSymbolMapper.deepLinkURL(for: "BTC/USDT", timeframe: .h1)
        XCTAssertEqual(deep?.scheme, "tradingview")
        XCTAssertEqual(deep?.host, "chart")
        XCTAssertTrue(deep?.absoluteString.contains("BINANCE") == true)
        XCTAssertTrue(deep?.absoluteString.contains("interval=60") == true)

        let web = TradingViewSymbolMapper.webFallbackURL(for: "XAU/USD", timeframe: .h4)
        XCTAssertEqual(web?.scheme, "https")
        XCTAssertEqual(web?.host, "www.tradingview.com")
        XCTAssertTrue(web?.absoluteString.contains("OANDA") == true)
        XCTAssertTrue(web?.absoluteString.contains("interval=240") == true)

        // Official embed snippet + attribution
        let html = TradingViewSymbolMapper.embedHTML(symbol: "GBP/USD", timeframe: .h1, isDark: true)
        XCTAssertTrue(html.contains("https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js"))
        XCTAssertTrue(html.contains("\"symbol\": \"OANDA:GBPUSD\""))
        XCTAssertTrue(html.contains("\"interval\": \"60\""))
        XCTAssertTrue(html.contains("\"theme\": \"dark\""))
        XCTAssertTrue(html.contains("Track all markets on TradingView"))
    }

    func testBackupSchemaVersionIsV2() {
        XCTAssertEqual(ConfluenceBackupArchive.currentSchemaVersion, 2)
    }
}
