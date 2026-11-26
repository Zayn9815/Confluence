import Foundation

public enum PsychologyReportBuilder {
    /// Synthesizes a strictly rule-triggered `PsychologyReport` from concrete structural, trap,
    /// positioning, and macro evidence — zero generic filler text.
    public static func build(
        category: SignalCategory,
        signalDirection: TradeDirection,
        ict: ICTAnalysis,
        traps: [BehavioralTrap],
        positioning: PositioningAssessment?,
        macroImpulse: MacroClusterImpulse?,
        rejectionReasons: [String],
        rvol: Double?,
        regime: MarketRegime,
        newsCatalyst: NewsCatalystAssessment? = nil,
        asset: AssetDescriptor? = nil
    ) -> PsychologyReport {
        var evidence: [BehavioralEvidence] = []
        var badges: [String] = []

        // 1. Active Behavioral Traps
        let actionableTraps = traps.filter(\.isActionable)
        let latestTrap = actionableTraps.last

        if let trap = latestTrap {
            badges.append(trap.triggerKind.rawValue)
            if trap.state == .returned {
                badges.append("Disposition Wall")
            }
            evidence.append(
                BehavioralEvidence(
                    badge: trap.triggerKind.rawValue,
                    fact: trap.detail,
                    proBias: trap.direction.institutionalDirection,
                    retailBias: trap.direction.trappedRetailDirection
                )
            )
        }

        // 2. Positioning evidence (OKX or CFTC COT)
        if let pos = positioning {
            badges.append(contentsOf: pos.badges)
            evidence.append(
                BehavioralEvidence(
                    badge: pos.provenance.rawValue,
                    fact: pos.summary,
                    proBias: pos.proDirection,
                    retailBias: pos.retailCrowdDirection
                )
            )
        }

        // 3. Macro Surprise & Breaking News catalyst evidence
        if let macro = macroImpulse {
            let macroPro: TradeDirection
            if let asset {
                macroPro = MacroPolarityTable.impactDirection(for: asset, currency: macro.currency, stance: macro.netStance)
            } else {
                macroPro = macro.impacts.first?.direction ?? .neutral
            }
            if macro.isWhipsawCautionActive {
                badges.append("News Whipsaw Risk")
            } else if macroPro != .neutral && macroPro == signalDirection {
                badges.append("Macro Catalyst Aligned")
            } else if macroPro != .neutral && signalDirection != .neutral && macroPro != signalDirection {
                badges.append("Macro Catalyst Opposes")
            }
            evidence.append(
                BehavioralEvidence(
                    badge: "Macro Release",
                    fact: macro.headlineStrip,
                    proBias: macroPro,
                    retailBias: macro.isWhipsawCautionActive ? macroPro.opposite : .neutral
                )
            )
        }
        if let news = newsCatalyst {
            badges.append(news.headlineBadge)
            evidence.append(
                BehavioralEvidence(
                    badge: "Breaking News",
                    fact: news.summary,
                    proBias: news.direction,
                    retailBias: .neutral
                )
            )
        }

        // 4. Provenance badge (exact data source honesty)
        let provenance: PositioningProvenance
        if let pos = positioning {
            provenance = pos.provenance
        } else if macroImpulse != nil {
            provenance = .macroSurpriseStructure
        } else {
            provenance = .structureVolumeWickProxy
        }

        // 5. Separate Intraday Pro Flow (`proDir`) from Weekly Macro COT (`macroDir`)
        let macroDir: TradeDirection?
        let macroLabel: String?
        let macroAligns: Bool?
        if let pos = positioning, pos.proDirection != .neutral {
            macroDir = pos.proDirection
            macroLabel = (pos.provenance == .cftcCOT) ? "Weekly COT Macro" : "OKX Derivatives Flow"
            if signalDirection != .neutral {
                macroAligns = (pos.proDirection == signalDirection)
            } else {
                macroAligns = nil
            }
        } else {
            macroDir = nil
            macroLabel = nil
            macroAligns = nil
        }

        // Intraday Pro Flow prioritizes intraday structure/traps/OKX flow — never overwritten by opposing weekly COT
        var proDir: TradeDirection = .neutral
        if let trap = latestTrap {
            proDir = trap.direction.institutionalDirection
        } else if signalDirection != .neutral {
            proDir = signalDirection
        } else if let pos = positioning, pos.provenance == .okxFundingOI, pos.proDirection != .neutral {
            proDir = pos.proDirection
        } else if ict.currentStructureBias != .neutral {
            proDir = ict.currentStructureBias
        } else if let pos = positioning {
            proDir = pos.proDirection
        }

        var retailDir: TradeDirection = .neutral
        if let trap = latestTrap {
            retailDir = trap.direction.trappedRetailDirection
        } else if let pos = positioning, pos.retailCrowdDirection != .neutral {
            retailDir = pos.retailCrowdDirection
        } else if let sweep = ict.liquiditySweeps.last {
            retailDir = sweep.reversalDirection.opposite
        } else if let dz = ict.dealingZone {
            retailDir = (dz == .premium) ? .long : (dz == .discount ? .short : .neutral)
        }

        if macroAligns == false && macroLabel != nil {
            badges.append(positioning?.provenance == .cftcCOT ? "Counter-Trend vs Macro COT" : "Counter-Trend vs OKX Flow")
        }

        // 6. Compose concrete 3-part narrative grounded purely in triggered facts
        let whatHappened: String
        let beginnerPsych: String
        let proPsych: String

        switch category {
        case .trapAlert:
            if let trap = latestTrap {
                whatHappened = "\(trap.direction.rawValue) [\(trap.state.rawValue.uppercased())]: \(trap.detail)"
                switch trap.triggerKind {
                case .oslerRoundNumberSweep, .liquiditySwingSweep:
                    beginnerPsych = "Retail stop orders clustered at \(formatPrice(trap.level)) were triggered on the pierce (\(String(format: "%.2f", trap.pierceATRMultiple))x ATR), while breakout chasers entered \(trap.direction.trappedRetailDirection.rawValue.uppercased()) right into institutional supply/demand."
                    proPsych = "Smart money absorbed the clustered stop liquidity beyond \(formatPrice(trap.level)) and closed back inside range, leaning \(trap.direction.institutionalDirection.rawValue.uppercased()) while underwater breakout traders create a disposition breakeven wall."
                case .attentionFOMOSpike:
                    let volNote = rvol.map { String(format: "%.1fx RVOL", $0) } ?? "parabolic range expansion"
                    beginnerPsych = "Attention-driven retail FOMO (\(volNote)) chased extended price far from EMA-20 equilibrium, entering late into exhaustion."
                    proPsych = "Institutions faded the overcrowded attention spike into retail market orders, positioning \(trap.direction.institutionalDirection.rawValue.uppercased()) for mean reversion."
                case .postNewsWhipsawTrap:
                    beginnerPsych = "Beginners chased the initial post-release knee-jerk candle without waiting for a closed structure bar, getting caught in wide spreads and whipsaw."
                    proPsych = "Desks swept resting stops on the initial macro spike and faded the emotional imbalance back through the pre-news open."
                case .shortSqueezeTrap, .longSqueezeTrap:
                    beginnerPsych = "Overleveraged retail positioning was forced into mechanical liquidation, driving one-sided emotional flow."
                    proPsych = "Larger players rode the forced liquidation cascade rather than fighting overcrowded margin flow."
                }
            } else {
                whatHappened = positioning?.summary ?? "Behavioral trap condition triggered by positioning divergence."
                beginnerPsych = "Retail positioning is heavily skewed \(retailDir.rawValue.uppercased()) against structural rejection."
                proPsych = "Institutional flow favors \(proDir.rawValue.uppercased()) liquidity absorption."
            }

        case .strongSignal:
            var facts: [String] = []
            if let brk = ict.structureBreaks.last {
                facts.append("\(brk.kind.rawValue) \(brk.direction.rawValue.uppercased()) at \(formatPrice(brk.brokenLevel))")
            }
            if let trap = latestTrap, trap.direction.institutionalDirection == signalDirection {
                facts.append("\(trap.direction.rawValue) (\(trap.triggerKind.rawValue))")
            }
            if let pos = positioning {
                facts.append(pos.summary)
            }
            if let macro = macroImpulse {
                facts.append(macro.headlineStrip)
            }
            if let news = newsCatalyst, news.matchingHeadlinesCount > 0 {
                facts.append(news.summary)
            }
            whatHappened = facts.isEmpty
                ? "Closed-bar multi-strategy confluence aligned \(signalDirection.rawValue.uppercased()) in \(regime.badgeLabel) regime."
                : facts.joined(separator: " · ")

            if retailDir != .neutral && retailDir != signalDirection {
                beginnerPsych = "Retail crowd is leaning \(retailDir.rawValue.uppercased()) (chasing swept stops or opposing liquidity), supplying counterparty liquidity for the \(signalDirection.rawValue.uppercased()) move."
            } else if let dz = ict.dealingZone {
                beginnerPsych = "Beginners typically hesitate in \(dz.rawValue) after a pullback or wait until price is already extended away from value."
            } else {
                beginnerPsych = "Retail participants react to single-indicator noise instead of waiting for closed-bar structural confirmation."
            }

            if let pos = positioning, let mDir = macroDir, let aligns = macroAligns {
                if aligns {
                    proPsych = "Intraday institutional flow AND \(macroLabel ?? pos.provenance.rawValue) align \(signalDirection.rawValue.uppercased()) with defined structural invalidation and \(signalDirection == .long ? "discount demand" : "premium supply") backing."
                } else {
                    proPsych = "Intraday institutional order flow confirms \(signalDirection.rawValue.uppercased()) on closed structure (\(signalDirection == .long ? "discount demand" : "premium supply")); note \(macroLabel ?? pos.provenance.rawValue) sits \(mDir.rawValue.uppercased()) (counter-trend — respect disciplined targets)."
                }
            } else {
                proPsych = "Intraday institutional order flow confirmed \(signalDirection.rawValue.uppercased()) on closed structure with asymmetric R:R beyond invalidation liquidity."
            }

        case .weakSignal:
            let reasonsText = rejectionReasons.isEmpty
                ? "Insufficient multi-strategy alignment."
                : rejectionReasons.joined(separator: "; ")
            whatHappened = "Filtered setup (\(signalDirection.rawValue.uppercased())): \(reasonsText)"
            beginnerPsych = "Beginners force entries on partial setups without waiting for >=3 independent confirmations, R:R floor, or clean regime/news clearance."
            proPsych = "Institutional desks stand aside when edge is diluted (\(reasonsText)) and preserve capital for clean asymmetric liquidity sweeps."
        }

        let uniqueBadges = Array(NSOrderedSet(array: badges)).compactMap { $0 as? String }

        return PsychologyReport(
            signalCategory: category,
            proDirection: proDir,
            retailCrowdDirection: retailDir,
            provenanceBadge: provenance.rawValue,
            whatHappened: whatHappened,
            beginnerPsychology: beginnerPsych,
            proPsychology: proPsych,
            behavioralBadges: uniqueBadges,
            evidence: evidence,
            macroPositioningDirection: macroDir,
            macroPositioningLabel: macroLabel,
            macroAlignsWithSetup: macroAligns
        )
    }

    private static func formatPrice(_ value: Double) -> String {
        ChartPricePrecision.resolve(symbol: "", referencePrice: value).format(value)
    }
}
