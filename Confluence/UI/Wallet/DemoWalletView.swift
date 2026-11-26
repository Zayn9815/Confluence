import SwiftUI
import SignalEngine

/// Pure helper for live Journal/Demo row progress bar from Stop loss (0.0) to Target 1 (1.0).
public enum LivePositionRowMetrics {
    public struct Summary: Sendable, Equatable {
        public let rMultiple: Double
        public let returnPercent: Double
        public let pnlUSD: Double?
        /// Clamped 0.0 (at/beyond Stop loss) ... 1.0 (at/beyond Target 1).
        public let stopToTargetProgress: Double
        /// Position of entry along the 0.0...1.0 Stop-loss-to-Target-1 bar.
        public let entryMarkerFraction: Double
        public let freshness: LivePriceFreshness
    }

    public static func compute(
        direction: TradeDirection,
        entryPrice: Double,
        stopLoss: Double,
        initialStopLoss: Double? = nil,
        target1: Double,
        liveQuote: LivePriceQuote?,
        fallbackPrice: Double,
        pnlUSD: Double? = nil,
        marginUSD: Double? = nil,
        nowEpochSeconds: TimeInterval = Date().timeIntervalSince1970
    ) -> Summary {
        let mark = liveQuote?.price ?? fallbackPrice
        let rDenomStop = initialStopLoss ?? stopLoss
        let riskDist = max(abs(entryPrice - rDenomStop), 1e-9)
        let signedDelta = (direction == .long) ? (mark - entryPrice) : (entryPrice - mark)
        let r = signedDelta / riskDist
        let pct: Double
        if let pnl = pnlUSD, let margin = marginUSD, margin > 1e-9 {
            pct = (pnl / margin) * 100.0
        } else {
            pct = (signedDelta / max(entryPrice, 1e-9)) * 100.0
        }

        let totalSpan = (direction == .long) ? (target1 - stopLoss) : (stopLoss - target1)
        let progress: Double
        let entryFrac: Double
        if totalSpan > 1e-9 {
            let fromStop = (direction == .long) ? (mark - stopLoss) : (stopLoss - mark)
            let entryFromStop = (direction == .long) ? (entryPrice - stopLoss) : (stopLoss - entryPrice)
            progress = min(1.0, max(0.0, fromStop / totalSpan))
            entryFrac = min(1.0, max(0.0, entryFromStop / totalSpan))
        } else {
            progress = 0.5
            entryFrac = 0.33
        }

        let freshness = liveQuote?.freshness(nowEpochSeconds: nowEpochSeconds) ?? .offline
        return Summary(
            rMultiple: r,
            returnPercent: pct,
            pnlUSD: pnlUSD,
            stopToTargetProgress: progress,
            entryMarkerFraction: entryFrac,
            freshness: freshness
        )
    }
}

/// Paper-only Demo Wallet screen showing virtual equity, free/reserved margin, live open positions,
/// balance editor, simulated fees toggle, CSV export, and transaction ledger.
public struct DemoWalletView: View {
    @Bindable public var coordinator: MarketScannerCoordinator
    public let palette: ConfluencePalette

    @State private var showPlaceTrade: Bool = false
    @State private var showEditBalance: Bool = false
    @State private var balanceInputText: String = ""
    @State private var editingPosition: DemoPosition? = nil
    @State private var slInput: String = ""
    @State private var t1Input: String = ""
    @State private var t2Input: String = ""
    @State private var editError: String? = nil

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    public var body: some View {
        let wallet = coordinator.demoWallet
        let liveMap = coordinator.livePriceService.livePriceMap()
        let unrealized = wallet.totalUnrealizedPnLUSD(livePrices: liveMap)
        let equity = wallet.totalEquityUSD(livePrices: liveMap)
        let now = Date().timeIntervalSince1970

        ScrollView {
            VStack(spacing: 12) {
                // Paper-only disclaimer & balance summary
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Demo Wallet (Paper Only)", systemImage: "banknote")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.champagneGold)
                        Spacer()
                        Button {
                            balanceInputText = String(format: "%.2f", wallet.cashBalanceUSD)
                            showEditBalance = true
                        } label: {
                            Text("Edit balance")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.macroIceBlue)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(palette.macroIceBlue.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("$\(String(format: "%.2f", equity))")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(palette.primaryInk)
                        Text("Equity")
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryInk)
                        Spacer()
                        let uColor = unrealized >= 0 ? palette.longEmerald : palette.shortCrimson
                        Text("\(unrealized >= 0 ? "+" : "")$\(String(format: "%.2f", unrealized)) open")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(uColor)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        walletStat("Cash", "$\(String(format: "%.2f", wallet.cashBalanceUSD))", palette.primaryInk)
                        walletStat("Free margin", "$\(String(format: "%.2f", wallet.freeMarginUSD))", palette.longEmerald)
                        walletStat("Reserved", "$\(String(format: "%.2f", wallet.reservedMarginUSD))", palette.champagneGold)
                    }

                    HStack {
                        Text("Realized P/L: \(wallet.realizedPnLUSD >= 0 ? "+" : "")$\(String(format: "%.2f", wallet.realizedPnLUSD))")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(wallet.realizedPnLUSD >= 0 ? palette.longEmerald : palette.shortCrimson)
                        Spacer()
                        Toggle("Simulated fees", isOn: $coordinator.settings.payload.demoWalletFeesEnabled)
                            .labelsHidden()
                        Text("Fees \(coordinator.settings.payload.demoWalletFeesEnabled ? "ON" : "OFF")")
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryInk)
                    }

                    HStack(spacing: 8) {
                        Button {
                            showPlaceTrade = true
                        } label: {
                            Label("Place Demo Trade", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.canvas)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(palette.champagneGold, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if let url = coordinator.exportDemoWalletTransactionsCSV(), !wallet.transactions.isEmpty {
                            ShareLink(item: url) {
                                Label("CSV", systemImage: "square.and.arrow.up")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(palette.macroIceBlue)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(palette.elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
                .padding(14)
                .institutionalCard(palette: palette)

                // Active Positions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open & Pending Demo Trades (\(wallet.activePositions.count))")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.primaryInk)

                    if wallet.activePositions.isEmpty {
                        Text("No open demo trades. Tap \"Place Demo Trade\" above or \"Trade\" on any interactive chart.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                    } else {
                        ForEach(wallet.activePositions) { pos in
                            activePositionCard(pos, now: now)
                        }
                    }
                }
                .padding(14)
                .institutionalCard(palette: palette)

                // Closed Demo Trades
                if !wallet.closedPositions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Closed Demo History (\(wallet.closedPositions.count))")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.primaryInk)

                        ForEach(wallet.closedPositions.prefix(30)) { pos in
                            closedPositionRow(pos)
                        }
                    }
                    .padding(14)
                    .institutionalCard(palette: palette)
                }
            }
            .padding(14)
        }
        .background(palette.canvas)
        .onAppear {
            coordinator.acquireActivePositionsLiveFeed()
        }
        .sheet(isPresented: $showPlaceTrade) {
            PlaceDemoTradeSheet(
                coordinator: coordinator,
                palette: palette
            )
        }
        .alert("Edit Demo Balance (USD)", isPresented: $showEditBalance) {
            TextField("New balance", text: $balanceInputText)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let val = Double(balanceInputText), val >= wallet.reservedMarginUSD {
                    coordinator.adjustDemoWalletBalance(to: val)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Minimum balance is your currently reserved margin ($\(String(format: "%.2f", wallet.reservedMarginUSD))).")
        }
        .sheet(item: $editingPosition) { pos in
            NavigationStack {
                Form {
                    Section("Edit \(pos.symbol) levels") {
                        HStack {
                            Text("Stop loss")
                            Spacer()
                            TextField("Stop loss", text: $slInput)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Target 1")
                            Spacer()
                            TextField("Target 1", text: $t1Input)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Target 2")
                            Spacer()
                            TextField("Optional", text: $t2Input)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let err = editError {
                        Section {
                            Text(err).font(.caption).foregroundStyle(palette.shortCrimson)
                        }
                    }
                }
                .navigationTitle("Edit Stop loss & Targets")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingPosition = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            savePositionEdit(pos)
                        }
                    }
                }
            }
        }
    }

    private func walletStat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.tertiaryInk)
            Text(value).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func activePositionCard(_ pos: DemoPosition, now: TimeInterval) -> some View {
        let quote = coordinator.livePriceService.latest(for: pos.symbol)
        let entry = pos.filledPrice ?? pos.entryPrice
        let mark = quote?.price ?? entry
        let pnl = pos.status == .open ? DemoWalletEngine.pnlUSD(for: pos, markPrice: mark) : 0
        let metrics = LivePositionRowMetrics.compute(
            direction: pos.direction,
            entryPrice: entry,
            stopLoss: pos.stopLoss,
            initialStopLoss: pos.initialStopLoss,
            target1: pos.target1,
            liveQuote: quote,
            fallbackPrice: entry,
            pnlUSD: pnl,
            marginUSD: pos.marginReservedUSD,
            nowEpochSeconds: now
        )
        let displayR = pos.status == .open ? metrics.rMultiple : 0.0
        let displayPct = pos.status == .open ? metrics.returnPercent : 0.0
        let prec = ChartPricePrecision.resolve(symbol: pos.symbol, marketClass: pos.marketClass, referencePrice: entry)
        let pnlColor = pnl >= 0 ? palette.longEmerald : palette.shortCrimson

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(pos.symbol) · \(pos.direction.rawValue.uppercased())")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.primaryInk)
                Text(pos.status == .open ? "OPEN" : "LIMIT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.champagneGold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.champagneGold.opacity(0.15), in: Capsule())
                Spacer()
                if metrics.freshness == .offline {
                    Text("OFFLINE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.shortCrimson)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.shortCrimson.opacity(0.14), in: Capsule())
                } else {
                    Text("Live \(prec.format(mark))")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                }
            }

            HStack {
                Text("\(pnl >= 0 ? "+" : "-")$\(String(format: "%.2f", abs(pnl)))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(pnlColor)
                Text("(\(String(format: "%+.2fR", displayR)) · \(String(format: "%+.1f%%", displayPct)))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(pnlColor)
                Spacer()
                Text("Margin $\(String(format: "%.0f", pos.marginReservedUSD)) · \(String(format: "%.0fx", pos.leverage))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.tertiaryInk)
            }

            // Progress bar from Stop loss (0) to Target 1 (1)
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.border.opacity(0.4)).frame(height: 6)
                        Capsule()
                            .fill(pnl >= 0 ? palette.longEmerald : palette.shortCrimson)
                            .frame(width: max(4, geo.size.width * metrics.stopToTargetProgress), height: 6)
                        Rectangle()
                            .fill(palette.champagneGold)
                            .frame(width: 2, height: 10)
                            .offset(x: max(0, min(geo.size.width - 2, geo.size.width * metrics.entryMarkerFraction)))
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("Stop loss \(prec.format(pos.stopLoss))")
                        .foregroundStyle(palette.shortCrimson)
                    Spacer()
                    Text("Target 1 \(prec.format(pos.target1))")
                        .foregroundStyle(palette.longEmerald)
                }
                .font(.system(size: 10).monospacedDigit())
            }

            HStack(spacing: 8) {
                if pos.status == .open && !pos.isStopLossAtBreakeven {
                    Button("Move SL to BE") {
                        _ = coordinator.moveDemoStopLossToBreakeven(positionId: pos.id)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.macroIceBlue)
                }
                Button("Edit levels") {
                    slInput = prec.format(pos.stopLoss)
                    t1Input = prec.format(pos.target1)
                    t2Input = pos.target2.map { prec.format($0) } ?? ""
                    editError = nil
                    editingPosition = pos
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.primaryInk)
                Spacer()
                Button(pos.status == .open ? "Close now" : "Cancel limit") {
                    _ = coordinator.closeDemoPositionManually(positionId: pos.id)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(palette.shortCrimson)
            }
        }
        .padding(11)
        .background(palette.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func closedPositionRow(_ pos: DemoPosition) -> some View {
        let color = pos.realizedPnLUSD >= 0 ? palette.longEmerald : palette.shortCrimson
        let statusLabel: String = {
            switch pos.status {
            case .closedTarget1: return "Target 1"
            case .closedTarget2: return "Target 2"
            case .closedStopLoss: return "Stop loss"
            case .closedManual: return "Manual"
            case .expired: return "Expired"
            case .cancelled: return "Cancelled"
            case .open, .pendingLimit: return "Active"
            }
        }()
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pos.symbol) · \(pos.direction.rawValue.uppercased()) · \(statusLabel)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.primaryInk)
                if let ex = pos.exitPrice {
                    let prec = ChartPricePrecision.resolve(symbol: pos.symbol, marketClass: pos.marketClass, referencePrice: ex)
                    Text("Entry \(prec.format(pos.filledPrice ?? pos.entryPrice)) -> Exit \(prec.format(ex))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.tertiaryInk)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(pos.realizedPnLUSD >= 0 ? "+" : "")$\(String(format: "%.2f", pos.realizedPnLUSD))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                Text(String(format: "%+.2fR", pos.rMultiple))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(color)
            }
        }
        .padding(9)
        .background(palette.elevatedSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func savePositionEdit(_ pos: DemoPosition) {
        editError = nil
        guard let sl = Double(slInput), let t1 = Double(t1Input) else {
            editError = "Enter valid numbers for Stop loss and Target 1."
            return
        }
        let t2Trim = t2Input.trimmingCharacters(in: .whitespaces)
        let t2: Double?
        if t2Trim.isEmpty {
            t2 = nil
        } else if let parsedT2 = Double(t2Trim) {
            t2 = parsedT2
        } else {
            editError = "Target 2 must be a valid number."
            return
        }
        if case .failure(let err) = coordinator.updateDemoStopLoss(positionId: pos.id, newStopLoss: sl) {
            editError = err.userMessage
            return
        }
        if case .failure(let err) = coordinator.updateDemoTargets(positionId: pos.id, newTarget1: t1, newTarget2: t2) {
            editError = err.userMessage
            return
        }
        editingPosition = nil
    }
}
