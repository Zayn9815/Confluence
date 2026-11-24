import Foundation
import XCTest
@testable import Confluence
import SignalEngine

final class AdapterIntegrationTests: XCTestCase {
    func testForexFactoryRejectsHTMLRequestDeniedPage() {
        let html = """
        <!DOCTYPE html><html><head><title>Request Denied</title></head>
        <body>You've exceeded the limit for Calendar Export requests.</body></html>
        """.data(using: .utf8)!

        XCTAssertThrowsError(
            try EconomicCalendarService.parseForexFactoryPayload(data: html, contentType: "text/html")
        )
        // Even if server mislabels Content-Type as application/json, leading byte != '[' must reject
        XCTAssertThrowsError(
            try EconomicCalendarService.parseForexFactoryPayload(data: html, contentType: "application/json")
        )
    }

    func testBiquoteCalendarPreservesNullActualAndNonExactTimeMode() throws {
        let json = """
        [
          {
            "id": "mql5:900001",
            "eventId": "mql5:840",
            "time": "2026-11-25T13:30:00Z",
            "countryCode": "US",
            "currency": "USD",
            "name": "CPI y/y",
            "importance": "high",
            "unit": "percent",
            "multiplier": null,
            "actual": null,
            "forecast": 2.7,
            "previous": 2.8,
            "revisedPrevious": 2.9,
            "timeMode": "exact"
          },
          {
            "id": "mql5:900002",
            "eventId": "mql5:841",
            "time": "2026-11-26T00:00:00Z",
            "countryCode": "US",
            "currency": "USD",
            "name": "Bank Holiday",
            "importance": "medium",
            "actual": null,
            "forecast": null,
            "previous": null,
            "timeMode": "tentative"
          }
        ]
        """.data(using: .utf8)!

        let events = try EconomicCalendarService.parseBiquoteCalendarJSON(data: json)
        XCTAssertEqual(events.count, 2)
        let cpi = events[0]
        XCTAssertNil(cpi.actual)
        XCTAssertEqual(cpi.forecast, 2.7)
        XCTAssertEqual(cpi.revisedPrevious, 2.9)
        XCTAssertEqual(cpi.canonicalIndicator, .cpi)
        XCTAssertTrue(cpi.isExactClock)

        let holiday = events[1]
        XCTAssertFalse(holiday.isExactClock)
    }

    func testYahooChartParserHandlesNullGapsAndOTCNilVolume() throws {
        let json = """
        {
          "chart": {
            "result": [
              {
                "timestamp": [1760000000, 1760003600, 1760007200],
                "indicators": {
                  "quote": [
                    {
                      "open": [2650.0, null, 2655.0],
                      "high": [2660.0, null, 2665.0],
                      "low": [2645.0, null, 2650.0],
                      "close": [2655.0, null, 2662.0],
                      "volume": [0, null, 0]
                    }
                  ]
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let bars = try TradFiOHLCVRouter.parseYahooChartJSON(
            data: json,
            timeframe: .h1,
            marketClass: .metals,
            serverNowEpochSeconds: 1_760_020_000
        )
        XCTAssertEqual(bars.count, 2)
        XCTAssertTrue(bars.allSatisfy { $0.volume == nil })
    }

    func testCFTCSocrataStringEncodedNumbersAndFridayReleaseDate() throws {
        let json = """
        [
          {
            "cftc_contract_market_code": "088691",
            "market_and_exchange_names": "GOLD - COMEX",
            "report_date_as_yyyy_mm_dd": "2026-11-17T00:00:00.000",
            "open_interest_all": "512400",
            "m_money_positions_long_all": "210000",
            "m_money_positions_short_all": "48000",
            "nonrept_positions_long_all": "31000",
            "nonrept_positions_short_all": "49000"
          }
        ]
        """.data(using: .utf8)!

        let records = try CFTCCOTAdapter.parseSocrataJSON(data: json, dataset: .disaggregatedFuturesOnly)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].institutionalNet, 162_000)
        XCTAssertEqual(records[0].nonReportableNet, -18_000)
        XCTAssertGreaterThan(records[0].publishedAtEpochSeconds, records[0].reportDateEpochSeconds + 3 * 86_400)
    }

    func testBundledCAFAlertSoundsPresentAtAppRoot() {
        let expected = [
            "terminal_chime",
            "sonar_pulse",
            "vault_lock",
            "trap_warning",
            "news_release_ping"
        ]
        for name in expected {
            let url = Bundle.main.url(forResource: name, withExtension: "caf")
            XCTAssertNotNil(url, "Missing root-bundled \(name).caf in Confluence.app")
        }
    }

    @MainActor
    func testSwiftDataPersistenceAndDeduplicationRoundTrip() {
        let store = ConfluenceDataStore(inMemory: true)
        let psych = PsychologyReport(
            signalCategory: .strongSignal, proDirection: .long, retailCrowdDirection: .short,
            provenanceBadge: PositioningProvenance.okxFundingOI.rawValue,
            whatHappened: "Sweep reclaimed", beginnerPsychology: "Stopped out", proPsychology: "Absorbed",
            behavioralBadges: ["Osler Round-Number Sweep"], evidence: []
        )
        let sig = TradeSignal(
            id: "fp-test-1", fingerprint: "fp-test-1", symbol: "BTC/USDT", displayName: "Bitcoin",
            marketClass: .crypto, timeframe: .h1, htfTimeframe: .h4,
            category: .strongSignal, direction: .long, tier: .aPlusInstitutional,
            confidencePercent: 87.0, regime: .trending, riskState: .safe,
            killzone: .london, htfBias: .long,
            generatedAtEpochSeconds: 1_760_000_000, barCloseEpochSeconds: 1_760_000_000,
            levels: nil, alignedStrategies: [], rejectionReasons: [],
            psychologyReport: psych, dataProvider: "Binance Vision"
        )
        store.upsertSignal(sig)
        let fetched = store.fetchSignals()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.fingerprint, "fp-test-1")
    }
}
