import SwiftUI

/// Presentation only. Every measurement comes from the existing shared summary.
struct DashboardOverview: View {
    let s: Summary
    @ObservedObject var ring: RingSync
    let analyzing: Bool
    let onSync: () -> Void
    let onPC: () -> Void
    let onProfile: () -> Void
    let onHistory: () -> Void
    let onDebt: () -> Void
    let onDay: (String, Bool) -> Void
    let onVital: (VitalKind) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                DailyOverviewHero(s: s, ring: ring, onSync: onSync)
                vitals
                if let day = s.days.first {
                    sectionTitle("Sleep & movement", detail: "Your latest day")
                    TodayCard(s: s, day: day, onSleep: { onDay(day, true) },
                              onActivity: { onDay(day, false) })
                }
                if let debt = s.sleepDebt {
                    SleepDebtCard(debt: debt, action: onDebt).obsCard()
                }
                if let radar = s.symptomRadar, radar.available {
                    IllnessCard(illness: radar).obsCard()
                }
                pcCard
                if s.cardio?.vascular_age != nil || s.fitness?.vo2max != nil {
                    cardiovascular
                }
                if !s.days.isEmpty {
                    Button(action: onHistory) {
                        HStack {
                            Image(systemName: "calendar").foregroundStyle(Obs.lavender)
                            Text("Explore your history").font(.headline)
                            Spacer()
                            Text("\(s.days.count) days").font(.subheadline).foregroundStyle(Obs.muted)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }.foregroundStyle(Obs.ink).obsCard()
                    }.buttonStyle(.plain)
                }
                RingOverviewPanel(s: s, onSync: onSync)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Obs.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "circle.hexagongrid.fill").foregroundStyle(Obs.good)
                    Text("Open Health").font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                }.foregroundStyle(Obs.ink)
                Spacer(minLength: 8)
                DashboardIconButton(icon: "desktopcomputer", label: "PC analysis", action: onPC)
                DashboardIconButton(icon: "person.crop.circle", label: "Your profile", action: onProfile)
                DashboardIconButton(icon: "arrow.triangle.2.circlepath", label: "Sync your ring", action: onSync)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.subheadline).foregroundStyle(Obs.muted)
                Text(greeting).font(.largeTitle.bold()).foregroundStyle(Obs.ink)
            }
            if ring.busy || analyzing {
                HStack(spacing: 8) {
                    ProgressView().tint(Obs.good)
                    Text(ring.busy ? "Syncing your ring…" : "Refreshing your insights…")
                        .font(.subheadline).foregroundStyle(Obs.ink2)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold()).foregroundStyle(Obs.ink)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(Obs.muted)
        }
    }

    private var vitals: some View {
        let temperature = s.nights.first { $0.skin_temp != nil }?.skin_temp
        let oxygen = s.nights.first { $0.spo2_mean != nil }?.spo2_mean
        let heart = s.vitals.hr?.latest ?? s.vitals.rhr.latest
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Your vitals", detail: "Tap to explore")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                DashboardVital(title: "Heart rate", icon: "heart.fill", value: heart,
                               unit: "bpm", tint: Obs.coral,
                               note: s.vitals.hr?.latest != nil ? "Latest reading" : "Nightly minimum",
                               series: s.vitals.rhr.series) { onVital(.heartRate) }
                DashboardVital(title: "Nightly HRV", icon: "waveform.path.ecg", value: s.vitals.hrv.latest,
                               unit: "ms", tint: Obs.lavender, note: "Overnight average",
                               series: s.vitals.hrv.series) { onVital(.hrv) }
                DashboardVital(title: "Skin temperature", icon: "thermometer.medium", value: temperature,
                               unit: "°C", tint: Obs.bad, note: "Latest night", decimals: 1,
                               series: Array(s.nights.compactMap(\.skin_temp).prefix(14).reversed())) { onVital(.temp) }
                DashboardVital(title: "Blood oxygen", icon: "drop.fill", value: oxygen,
                               unit: "%", tint: Obs.blue, note: "Latest night",
                               series: Array(s.nights.compactMap(\.spo2_mean).prefix(14).reversed())) { onVital(.oxygen) }
            }
        }
    }

    private var pcCard: some View {
        Button(action: onPC) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "desktopcomputer")
                    .font(.title2).foregroundStyle(Obs.good)
                    .frame(width: 48, height: 48).background(Obs.good.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 7) {
                    Text("A deeper look").font(.headline).foregroundStyle(Obs.ink)
                    Text("Send a snapshot to your PC for a private analysis report.")
                        .font(.subheadline).foregroundStyle(Obs.ink2).fixedSize(horizontal: false, vertical: true)
                    Label("Set up or connect", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Obs.good)
                }
                Spacer(minLength: 0)
            }.obsCard()
        }.buttonStyle(.plain)
    }

    private var cardiovascular: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Cardiovascular estimates", systemImage: "heart.text.square")
                .font(.headline).foregroundStyle(Obs.ink)
            if let age = s.cardio?.vascular_age {
                ObsStat(label: "Vascular age", value: String(format: "%.1f years", age))
            }
            if let velocity = s.cardio?.pwv_ms {
                ObsStat(label: "Pulse-wave velocity", value: String(format: "%.2f m/s", velocity))
            }
            if let vo = s.fitness?.vo2max {
                ObsStat(label: "VO₂max estimate", value: String(format: "%.1f", vo))
                Text("ml/kg/min · depends on your saved profile")
                    .font(.caption).foregroundStyle(Obs.muted)
            }
        }.obsCard()
    }
}

private struct DashboardIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
                .foregroundStyle(Obs.ink2).frame(width: 44, height: 44)
                .background(Obs.surface, in: Circle())
                .overlay(Circle().strokeBorder(Obs.rule, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

private struct DailyOverviewHero: View {
    let s: Summary
    @ObservedObject var ring: RingSync
    let onSync: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(ring.busy ? "SYNCING" : (ring.lastSuccessfulSyncAt == nil ? "LET’S GET STARTED" : "LAST SYNC SAVED"),
                          systemImage: ring.busy ? "arrow.triangle.2.circlepath" : (ring.lastSuccessfulSyncAt == nil ? "circle.dotted" : "checkmark.circle.fill"))
                        .font(.caption2.weight(.bold)).tracking(1).foregroundStyle(Obs.good)
                    Text(s.nights.isEmpty ? "Your story\nstarts tonight." : "Your day,\nin focus.")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Obs.ink).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize { RingChargeGauge(percent: s.device?.battery_pct) }
            }
            Text(s.nights.isEmpty
                 ? "Wear your ring overnight. Sync in the morning to start building your personal picture."
                 : (s.digest ?? "Your latest ring data, all in one place."))
                .font(.subheadline).foregroundStyle(Obs.ink2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Label(AutoSyncPolicy.enabled ? "Auto-sync · 2h target" : "Manual sync", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.medium)).foregroundStyle(Obs.ink2)
                Spacer(minLength: 0)
                Button(action: onSync) {
                    Label("Sync", systemImage: "arrow.up.right").font(.subheadline.weight(.semibold))
                        .foregroundStyle(Obs.onAccent).padding(.horizontal, 15).frame(minHeight: 44)
                        .background(Obs.good, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(LinearGradient(colors: [Obs.elevated, Obs.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Obs.good.opacity(0.18), lineWidth: 1))
    }
}

private struct RingChargeGauge: View {
    let percent: Int?
    var body: some View {
        ZStack {
            Circle().stroke(Obs.rule, lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(min(100, max(0, percent ?? 0))) / 100)
                .stroke(Obs.good, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
                Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(Obs.good)
                Text(percent.map { "\($0)%" } ?? "—")
                    .font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(Obs.ink)
                Text("Ring charge").font(.system(size: 9, weight: .medium)).foregroundStyle(Obs.muted)
            }
        }.frame(width: 88, height: 88)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ring battery")
            .accessibilityValue(percent.map { "\($0) percent" } ?? "No reading")
    }
}

private struct DashboardVital: View {
    let title: String
    let icon: String
    let value: Double?
    let unit: String
    let tint: Color
    let note: String
    var decimals: Int = 0
    var series: [Double] = []
    let action: () -> Void
    private var displayValue: String { value.map { String(format: "%.*f", decimals, $0) } ?? "—" }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint).frame(width: 36, height: 36)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Obs.muted)
                }
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Obs.ink2)
                    .lineLimit(2).frame(minHeight: 20, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayValue).font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text(unit).font(.caption).foregroundStyle(Obs.muted)
                }.foregroundStyle(Obs.ink).minimumScaleFactor(0.75).lineLimit(1)
                if series.count > 1 {
                    Sparkline(series: series, accent: tint).frame(height: 24)
                }
                Text(value == nil ? "Awaiting ring data" : note)
                    .font(.caption).foregroundStyle(Obs.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .padding(17).background(Obs.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Obs.rule, lineWidth: 1))
        }.buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(displayValue) \(unit)")
            .accessibilityHint("Shows measurement history")
    }
}

private struct RingOverviewPanel: View {
    let s: Summary
    let onSync: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "circle.circle").font(.title2).foregroundStyle(Obs.good)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your ring").font(.headline).foregroundStyle(Obs.ink)
                    Text(s.device?.synced_hm.map { "Last synced at \($0)" } ?? "Ready when you are")
                        .font(.caption).foregroundStyle(Obs.muted)
                }
                Spacer()
                Button("Manage", action: onSync).font(.subheadline.weight(.semibold)).foregroundStyle(Obs.good).frame(minHeight: 44)
            }
            DisclosureGroup("Device & diagnostics") {
                VStack(spacing: 12) {
                    ObsStat(label: "Battery", value: s.device?.battery_pct.map { "\($0)%" } ?? "—")
                    ObsStat(label: "Firmware", value: s.device?.firmware ?? "—")
                    ObsStat(label: "Serial", value: s.device?.serial ?? "—")
                    if let count = s.device?.decoded_events { ObsStat(label: "Decoded events", value: "\(count)") }
                    if let error = s.error { Text(error).font(.caption).foregroundStyle(Obs.bad) }
                    ForEach(s.clock?.warnings ?? [], id: \.self) { Text($0).font(.caption).foregroundStyle(Obs.bad) }
                    ForEach(s.modelErrors, id: \.self) { Text($0).font(.caption).foregroundStyle(Obs.bad) }
                    BuildStamp()
                }.padding(.top, 14)
            }.font(.subheadline).foregroundStyle(Obs.ink2).tint(Obs.muted)
        }.obsCard()
    }
}
