import Foundation

public enum MacroSurpriseEngine {
    /// Evaluates Stage-2 Actual-vs-Forecast surprise for a single published event.
    /// Strictly returns `nil` when `actual == nil` or `forecast == nil` (NEVER coerces nil to 0).
    public static func evaluateSurprise(
        event: EconomicEvent,
        nowEpochSeconds: TimeInterval,
        whipsawWindowMinutes: Int = 5
    ) -> MacroSurpriseResult? {
        guard event.supportsActualRelease,
              event.scheduledEpochSeconds <= nowEpochSeconds,
              let actual = event.actual, actual.isFinite,
              let forecast = event.forecast, forecast.isFinite
        else {
            return nil
        }

        let delta = actual - forecast
        let denom = max(abs(forecast), 0.1)
        let surprisePct = (delta / denom) * 100.0

        let canonical = event.canonicalIndicator ?? MacroPolarityTable.canonicalIndicator(for: event.name)
        let higherIsHawkish = canonical.map { MacroPolarityTable.isHigherHawkish(for: $0) } ?? true

        let stance: MacroStance
        if abs(delta) < 1e-6 || abs(surprisePct) < 1.5 {
            stance = .neutral
        } else if (delta > 0 && higherIsHawkish) || (delta < 0 && !higherIsHawkish) {
            stance = .hawkish
        } else {
            stance = .dovish
        }

        let impacts = MacroPolarityTable.directionalImpacts(currency: event.currency, stance: stance)
        let elapsedSeconds = nowEpochSeconds - event.scheduledEpochSeconds
        let inWhipsaw = elapsedSeconds >= 0 && elapsedSeconds <= Double(whipsawWindowMinutes * 60)

        let arrowParts = impacts.prefix(4).map { impact -> String in
            let arrow = impact.direction == .long ? "↑" : (impact.direction == .short ? "↓" : "→")
            return "\(impact.assetLabel) \(arrow)"
        }
        let stanceTag: String
        switch stance {
        case .hawkish: stanceTag = "Hawkish \(event.currency)"
        case .dovish: stanceTag = "Dovish \(event.currency)"
        case .neutral: stanceTag = "In-Line \(event.currency)"
        case .mixedWhipsaw: stanceTag = "Mixed \(event.currency)"
        }
        let summary = "\(event.name) (\(stanceTag)) -> \(arrowParts.joined(separator: " · "))"

        return MacroSurpriseResult(
            event: event,
            surpriseDelta: delta,
            surprisePercent: surprisePct,
            currencyStance: stance,
            impacts: impacts,
            summaryLine: summary,
            isInPostNewsWhipsawWindow: inWhipsaw
        )
    }

    /// Aggregates simultaneous releases (within ±120s for the same currency, e.g., NFP + Unemployment + Wages)
    /// into a single weighted Net Macro Impulse, flagging `.mixedWhipsaw` when major prints disagree.
    public static func buildClusters(
        events: [EconomicEvent],
        nowEpochSeconds: TimeInterval,
        whipsawWindowMinutes: Int = 5
    ) -> [MacroClusterImpulse] {
        let evaluated = events.compactMap {
            evaluateSurprise(event: $0, nowEpochSeconds: nowEpochSeconds, whipsawWindowMinutes: whipsawWindowMinutes)
        }.sorted { $0.event.scheduledEpochSeconds < $1.event.scheduledEpochSeconds }

        var groups: [[MacroSurpriseResult]] = []
        for res in evaluated {
            if let idx = groups.firstIndex(where: { group in
                guard let first = group.first else { return false }
                return first.event.currency == res.event.currency &&
                       abs(first.event.scheduledEpochSeconds - res.event.scheduledEpochSeconds) <= 120.0
            }) {
                groups[idx].append(res)
            } else {
                groups.append([res])
            }
        }

        return groups.compactMap { group -> MacroClusterImpulse? in
            guard let first = group.first else { return nil }
            let currency = first.event.currency
            let ts = first.event.scheduledEpochSeconds

            var hawkishScore = 0.0
            var dovishScore = 0.0
            for item in group {
                let w = MacroPolarityTable.clusterWeight(
                    for: item.event.canonicalIndicator ?? MacroPolarityTable.canonicalIndicator(for: item.event.name)
                )
                switch item.currencyStance {
                case .hawkish: hawkishScore += w
                case .dovish: dovishScore += w
                case .neutral, .mixedWhipsaw: break
                }
            }

            let netStance: MacroStance
            if hawkishScore > 0 && dovishScore > 0 && min(hawkishScore, dovishScore) / max(hawkishScore, dovishScore) >= 0.55 {
                netStance = .mixedWhipsaw
            } else if hawkishScore > dovishScore {
                netStance = .hawkish
            } else if dovishScore > hawkishScore {
                netStance = .dovish
            } else {
                netStance = .neutral
            }

            let impacts = MacroPolarityTable.directionalImpacts(currency: currency, stance: netStance)
            let anyWhipsawWindow = group.contains(where: \.isInPostNewsWhipsawWindow) || netStance == .mixedWhipsaw

            let strip: String
            if netStance == .mixedWhipsaw {
                strip = "Mixed \(currency) Prints (\(group.map(\.event.name).prefix(2).joined(separator: " + "))) -> High Whipsaw Caution"
            } else {
                let arrowParts = impacts.prefix(3).map { imp -> String in
                    let arrow = imp.direction == .long ? "↑" : (imp.direction == .short ? "↓" : "→")
                    return "\(imp.assetLabel) \(arrow)"
                }
                let leadName = group.max(by: {
                    let lhs = $0.event.canonicalIndicator ?? MacroPolarityTable.canonicalIndicator(for: $0.event.name)
                    let rhs = $1.event.canonicalIndicator ?? MacroPolarityTable.canonicalIndicator(for: $1.event.name)
                    return MacroPolarityTable.clusterWeight(for: lhs) < MacroPolarityTable.clusterWeight(for: rhs)
                })?.event.name ?? first.event.name
                let adj = netStance == .hawkish ? "Hawkish" : (netStance == .dovish ? "Dovish" : "In-Line")
                strip = "\(adj) \(leadName) -> \(arrowParts.joined(separator: " · "))"
            }

            return MacroClusterImpulse(
                currency: currency,
                clusterEpochSeconds: ts,
                results: group,
                netStance: netStance,
                impacts: impacts,
                headlineStrip: strip,
                isWhipsawCautionActive: anyWhipsawWindow
            )
        }
    }

    /// Evaluates Stage-1 Pre-News Countdown Shield for an asset.
    /// Strictly ignores events where `timeMode != .exact` (never shows countdown for placeholder clocks).
    public static func preNewsShield(
        for asset: AssetDescriptor,
        events: [EconomicEvent],
        nowEpochSeconds: TimeInterval,
        blackoutMinutesBefore: Int = 15,
        bannerHorizonMinutes: Int = 60,
        minimumImportance: MacroImportance = .high
    ) -> PreNewsShieldStatus? {
        let exposed = asset.exposedMacroCurrencies
        let upcoming = events
            .filter { ev in
                ev.isExactClock &&
                !ev.isPublished &&
                ev.importance >= minimumImportance &&
                exposed.contains(ev.currency) &&
                ev.scheduledEpochSeconds > nowEpochSeconds &&
                ev.scheduledEpochSeconds - nowEpochSeconds <= Double(bannerHorizonMinutes * 60)
            }
            .sorted { $0.scheduledEpochSeconds < $1.scheduledEpochSeconds }

        guard let next = upcoming.first else { return nil }
        let minutes = max(1, Int(ceil((next.scheduledEpochSeconds - nowEpochSeconds) / 60.0)))
        let blackout = minutes <= blackoutMinutesBefore
        let badge = "\(next.countryCode) \(next.name) in \(minutes)m · Expect Whipsaws"

        return PreNewsShieldStatus(
            event: next,
            minutesUntilRelease: minutes,
            isBlackoutActive: blackout,
            badgeText: badge
        )
    }

    /// Computes exact pre-news notification queue items strictly respecting iOS's 64-notification limit
    /// (enforcing a hard 40-slot budget for pre-news countdowns, `timeMode == .exact` only).
    public static func planPreNewsNotificationSlots(
        events: [EconomicEvent],
        nowEpochSeconds: TimeInterval,
        leadTimesMinutes: [Int],
        minimumImportance: MacroImportance = .high,
        maxSlots: Int = 40
    ) -> [(identifier: String, event: EconomicEvent, leadMinutes: Int, fireEpochSeconds: TimeInterval)] {
        let validLeads = Array(Set(leadTimesMinutes.filter { $0 > 0 })).sorted(by: >)
        guard !validLeads.isEmpty, maxSlots > 0 else { return [] }

        let horizon = nowEpochSeconds + 7 * 86_400
        let eligible = events
            .filter { ev in
                ev.isExactClock &&
                !ev.isPublished &&
                ev.importance >= minimumImportance &&
                ev.scheduledEpochSeconds > nowEpochSeconds &&
                ev.scheduledEpochSeconds <= horizon
            }
            .sorted { $0.scheduledEpochSeconds < $1.scheduledEpochSeconds }

        var slots: [(identifier: String, event: EconomicEvent, leadMinutes: Int, fireEpochSeconds: TimeInterval)] = []

        for ev in eligible {
            for lead in validLeads {
                let fireAt = ev.scheduledEpochSeconds - Double(lead * 60)
                guard fireAt > nowEpochSeconds + 5.0 else { continue }
                if slots.count >= maxSlots { break }
                let cleanKey = ev.semanticKey.replacingOccurrences(of: " ", with: "_")
                slots.append((
                    identifier: "confluence.prenews.\(cleanKey).\(lead)m",
                    event: ev,
                    leadMinutes: lead,
                    fireEpochSeconds: fireAt
                ))
            }
            if slots.count >= maxSlots { break }
        }
        return slots
    }
}
