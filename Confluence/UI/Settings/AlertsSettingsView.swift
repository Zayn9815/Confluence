import SwiftUI
import SignalEngine

/// Settings Category 2: Alerts (Permissions, Category Toggles, Quiet Hours, Per-Market Alert Rules & Pre-News).
public struct AlertsSettingsView: View {
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    private let weekdayLabels: [(Int, String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]

    public init(coordinator: MarketScannerCoordinator, palette: ConfluencePalette) {
        self.coordinator = coordinator
        self.palette = palette
    }

    public var body: some View {
        Form {
            Section("System Notification Permission") {
                HStack {
                    Text("iOS Notifications")
                    Spacer()
                    Button(coordinator.notificationStatusDescription) {
                        Task { await coordinator.requestNotifications() }
                    }
                    .font(.caption.weight(.semibold))
                }

                HStack {
                    Text("Stored Bell Inbox")
                    Spacer()
                    Text("\(coordinator.notifications.count) saved · \(coordinator.unreadNotificationCount) unread")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                }

                Button {
                    coordinator.isNotificationInboxPresented = true
                } label: {
                    Label("Open Notification Inbox", systemImage: "bell.badge")
                }
            }

            Section {
                Toggle("Strong setup alerts", isOn: $coordinator.settings.payload.alertRules.allowStrongSignals)
                Toggle("Behavioral trap warnings", isOn: $coordinator.settings.payload.alertRules.allowTrapAlerts)
                Toggle("Pre-news reminders", isOn: $coordinator.settings.payload.alertRules.allowPreNewsCountdowns)
                Toggle("Major economic release impacts", isOn: $coordinator.settings.payload.alertRules.allowMacroReleases)
            } header: {
                SettingsSectionHeader(SettingHelpKey.alertCategories.copy.label, helpKey: .alertCategories)
            }

            Section {
                Toggle("Enable quiet hours", isOn: $coordinator.settings.payload.alertRules.quietHours.enabled)

                if coordinator.settings.payload.alertRules.quietHours.enabled {
                    Picker("Start hour", selection: $coordinator.settings.payload.alertRules.quietHours.startHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }

                    Picker("End hour", selection: $coordinator.settings.payload.alertRules.quietHours.endHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active days (\(coordinator.settings.payload.alertRules.quietHours.formattedWindow))")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryInk)
                        HStack(spacing: 6) {
                            ForEach(weekdayLabels, id: \.0) { dayNum, label in
                                let active = coordinator.settings.payload.alertRules.quietHours.activeWeekdays.contains(dayNum)
                                Button {
                                    if active {
                                        coordinator.settings.payload.alertRules.quietHours.activeWeekdays.remove(dayNum)
                                    } else {
                                        coordinator.settings.payload.alertRules.quietHours.activeWeekdays.insert(dayNum)
                                    }
                                } label: {
                                    Text(label)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(active ? palette.canvas : palette.secondaryInk)
                                        .frame(width: 30, height: 30)
                                        .background(active ? palette.champagneGold : palette.elevatedSurface, in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                SettingsSectionHeader(SettingHelpKey.quietHours.copy.label, helpKey: .quietHours)
            } footer: {
                Text(SettingHelpKey.quietHours.copy.subtitle)
            }

            Section {
                ForEach(MarketClass.allCases, id: \.self) { market in
                    NavigationLink {
                        MarketAlertRuleDetailView(market: market, coordinator: coordinator, palette: palette)
                    } label: {
                        let rule = coordinator.settings.payload.alertRules.rule(for: market)
                        HStack {
                            Text(market.displayName)
                            Spacer()
                            if !rule.enabled {
                                Text("Muted")
                                    .font(.caption)
                                    .foregroundStyle(palette.tertiaryInk)
                            } else {
                                let floorText = rule.minScoreOverride.map { "≥\(Int($0.rounded()))" } ?? "Global"
                                Text("ON · \(floorText)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(palette.longEmerald)
                            }
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(SettingHelpKey.perMarketAlertRules.copy.label, helpKey: .perMarketAlertRules)
            }

            Section {
                Picker("Calendar alert impact", selection: $coordinator.settings.payload.calendarPushImpactFilter) {
                    ForEach(CalendarImpactFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }

                Toggle("Pre-news reminder (15 min before)", isOn: $coordinator.settings.payload.preNewsLead15m)
                Toggle("Pre-news reminder (5 min before)", isOn: $coordinator.settings.payload.preNewsLead5m)
                Toggle(isOn: $coordinator.settings.payload.pauseSignalsDuringPreNewsWindow) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.pauseDuringPreNews.copy.label)
                        InfoButton(.pauseDuringPreNews)
                    }
                }
            } header: {
                SettingsSectionHeader(SettingHelpKey.preNewsCountdowns.copy.label, helpKey: .preNewsCountdowns)
            } footer: {
                Text(SettingHelpKey.preNewsCountdowns.copy.subtitle)
            }

            Section("Risk Protection") {
                Toggle(isOn: $coordinator.settings.payload.autoSuppressCrisisAlerts) {
                    HStack(spacing: 6) {
                        Text(SettingHelpKey.crisisAlertSuppression.copy.label)
                        InfoButton(.crisisAlertSuppression)
                    }
                }
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await coordinator.refreshNotificationStatus()
        }
    }
}

private struct MarketAlertRuleDetailView: View {
    let market: MarketClass
    @Bindable var coordinator: MarketScannerCoordinator
    let palette: ConfluencePalette

    private func binding<T>(_ keyPath: WritableKeyPath<MarketAlertRule, T>) -> Binding<T> {
        Binding(
            get: { coordinator.settings.payload.alertRules.rule(for: market)[keyPath: keyPath] },
            set: { newValue in
                var current = coordinator.settings.payload.alertRules.rule(for: market)
                current[keyPath: keyPath] = newValue
                coordinator.settings.payload.alertRules.marketRules[market] = current
            }
        )
    }

    var body: some View {
        let rule = coordinator.settings.payload.alertRules.rule(for: market)
        Form {
            Section("Delivery Channels") {
                Toggle("Enable \(market.displayName) Alerts", isOn: binding(\.enabled))
                if rule.enabled {
                    Toggle("Push Notifications", isOn: binding(\.allowPush))
                    Toggle("In-App Banner", isOn: binding(\.allowBanner))
                    Toggle("Alert Sound", isOn: binding(\.allowSound))
                }
            }

            if rule.enabled {
                Section {
                    Toggle("Custom Minimum Score Override", isOn: Binding(
                        get: { rule.minScoreOverride != nil },
                        set: { enabled in
                            var current = coordinator.settings.payload.alertRules.rule(for: market)
                            current.minScoreOverride = enabled ? coordinator.settings.payload.minimumConfidencePercent : nil
                            coordinator.settings.payload.alertRules.marketRules[market] = current
                        }
                    ))

                    if let overrideVal = rule.minScoreOverride {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("\(market.displayName) Alert Score Floor")
                                Spacer()
                                Text("\(Int(overrideVal.rounded()))/100")
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundStyle(palette.champagneGold)
                            }
                            Slider(
                                value: Binding(
                                    get: { overrideVal },
                                    set: { val in
                                        var current = coordinator.settings.payload.alertRules.rule(for: market)
                                        current.minScoreOverride = val
                                        coordinator.settings.payload.alertRules.marketRules[market] = current
                                    }
                                ),
                                in: 55...95,
                                step: 1
                            )
                        }
                    }
                } header: {
                    Text("Score Threshold")
                } footer: {
                    Text("When OFF, inherits the global Strong Signal raw score gate (\(Int(coordinator.settings.payload.minimumConfidencePercent.rounded()))/100).")
                }
            }
        }
        .navigationTitle("\(market.displayName) Alerts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
