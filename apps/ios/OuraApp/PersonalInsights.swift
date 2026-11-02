import SwiftUI

struct PersonalInsights: Codable {
    struct OvernightStress: Codable {
        struct Measurement: Codable {
            let value: Double
            let baseline: Double
            let unit: String
        }
        let status: String
        let level: String?
        let label: String
        let date: String?
        let baseline_nights: Int
        let message: String
        let method: String
        let rhr: Measurement?
        let hrv: Measurement?
    }
    let overnight_stress: OvernightStress?
    struct BaselineModel: Codable {
        struct Observation: Codable, Identifiable {
            let id: String
            let title: String
            let message: String
            let date: String
            let baseline_nights: Int
        }
        let message: String
        let method: String
        let baseline_nights: Int
        let observations: [Observation]
    }
    let local_model: BaselineModel?
    let as_of: String
    let latest_night: String?
    let daily: [DailyObservation]
    let message: String
    let weekly: WeeklyObservations
    let method: String
}
struct DailyObservation: Codable, Identifiable {
    let id: String
    let title: String
    let unit: String
    let date: String
    let value: Double
    let baseline: Double?
    let baseline_nights: Int
    let delta: Double?
    let message: String
}
struct WeeklyObservations: Codable {
    let current_start: String
    let current_end: String
    let previous_start: String
    let previous_end: String
    let metrics: [WeeklyObservation]
}
struct WeeklyObservation: Codable, Identifiable {
    struct Point: Codable { let date: String; let value: Double }
    let id: String
    let title: String
    let unit: String
    let current: Double?
    let previous: Double?
    let current_nights: Int
    let previous_nights: Int
    let comparable: Bool
    let delta: Double?
    let points: [Point]
}

struct PersonalInsightsCard: View {
    let insights: PersonalInsights?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Your personal insights", systemImage: "sparkle.magnifyingglass")
                        .font(.headline).foregroundStyle(Obs.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Obs.muted)
                }
                if let model = insights?.local_model, !model.observations.isEmpty {
                    Text("\(model.observations.count) changes from your baseline to review")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Obs.ink)
                    Text(model.observations[0].message).font(.subheadline).foregroundStyle(Obs.ink2)
                } else if let first = insights?.daily.first {
                    Text(first.message).font(.subheadline).foregroundStyle(Obs.ink2)
                    Text("From the night ending \(first.date)").font(.caption).foregroundStyle(Obs.muted)
                } else {
                    Text(insights?.message ?? "Sync an overnight recording to begin your daily insights.")
                        .font(.subheadline).foregroundStyle(Obs.ink2)
                }
                Text("On-device analysis · insights & trends").font(.subheadline.weight(.semibold)).foregroundStyle(Obs.good)
            }.frame(maxWidth: .infinity, alignment: .leading).obsCard()
        }.buttonStyle(.plain)
    }
}

struct PersonalInsightsView: View {
    let insights: PersonalInsights?
    @State private var page = 0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Report", selection: $page) {
                        Text("Daily insights").tag(0)
                        Text("Weekly trends").tag(1)
                    }.pickerStyle(.segmented)
                    if let insights {
                        if let stress = insights.overnight_stress {
                            OvernightStressCard(stress: stress)
                        }
                        if let model = insights.local_model {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Personal baseline review", systemImage: "waveform.path.ecg").font(.headline)
                                Text("Calculated on this iPhone after sync. No PC or account required.").font(.caption).foregroundStyle(Obs.muted)
                                Text(model.message).font(.subheadline)
                                ForEach(model.observations) { observation in
                                    Divider()
                                    Text(observation.title).font(.headline)
                                    Text(observation.message).font(.subheadline)
                                    Text("Night ending \(observation.date) · \(observation.baseline_nights) baseline nights").font(.caption).foregroundStyle(Obs.muted)
                                }
                                Text("Wellness observations, not medical warnings. If you feel unwell or changes persist, speak with a healthcare professional; do not rely on this screen to decide whether you need care.").font(.footnote).foregroundStyle(Obs.ink2)
                                DisclosureGroup("How the model works") { Text(model.method).font(.caption) }
                            }.foregroundStyle(Obs.ink).frame(maxWidth: .infinity, alignment: .leading).obsCard()
                        }
                        Text("As of \(insights.as_of)").font(.caption).foregroundStyle(Obs.muted)
                        if page == 0 {
                            Text(insights.message).font(.subheadline).foregroundStyle(Obs.ink2)
                            ForEach(insights.daily) { observation in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(observation.title).font(.headline).foregroundStyle(Obs.ink)
                                    Text(String(format: "%.1f %@", observation.value, observation.unit))
                                        .font(.system(.title, design: .rounded, weight: .semibold)).foregroundStyle(Obs.ink)
                                    Text(observation.message).font(.subheadline).foregroundStyle(Obs.ink2)
                                    Text("Night ending \(observation.date)").font(.caption).foregroundStyle(Obs.muted)
                                }.frame(maxWidth: .infinity, alignment: .leading).obsCard()
                            }
                        } else {
                            Text("Last 7 calendar days: \(insights.weekly.current_start) – \(insights.weekly.current_end)")
                                .font(.subheadline).foregroundStyle(Obs.ink2)
                            Text("Previous 7: \(insights.weekly.previous_start) – \(insights.weekly.previous_end)")
                                .font(.caption).foregroundStyle(Obs.muted)
                            ForEach(insights.weekly.metrics) { metric in
                                WeeklyObservationCard(metric: metric)
                            }
                        }
                        Text(insights.method).font(.footnote).foregroundStyle(Obs.muted)
                    } else {
                        Text("Your insights will appear after a successful ring sync. Missing readings are never replaced with zeroes.")
                            .font(.body).foregroundStyle(Obs.ink2).obsCard()
                    }
                }.padding(20)
            }.background(Obs.paper)
                .navigationTitle("Insights")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(Obs.good)
    }
}

/// A descriptive overnight pattern. No extra BLE reads or live stress claims.
struct OvernightStressCard: View {
    let stress: PersonalInsights.OvernightStress
    private var tint: Color {
        switch stress.level {
        case "higher": return Obs.coral
        case "lower": return Obs.good
        case "usual": return Obs.blue
        default: return Obs.lavender
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Overnight stress estimate", systemImage: "waveform.path.ecg")
                .font(.headline).foregroundStyle(Obs.ink)
            Text(stress.label).font(.title2.bold()).foregroundStyle(tint)
            Text("HR / HRV pattern · not a live stress reading")
                .font(.caption).foregroundStyle(Obs.muted)
            if let date = stress.date {
                Text("Night ending \(date)").font(.caption).foregroundStyle(Obs.muted)
            }
            if stress.status == "learning" {
                ProgressView(value: Double(min(stress.baseline_nights, 14)), total: 14)
                    .tint(tint).accessibilityLabel("Baseline learning progress")
                    .accessibilityValue("\(stress.baseline_nights) of 14 prior nights")
            }
            Text(stress.message).font(.subheadline).foregroundStyle(Obs.ink2)
            if let hr = stress.rhr, let hrv = stress.hrv {
                VStack(alignment: .leading, spacing: 8) {
                    measurement("Nightly minimum heart rate", hr)
                    measurement("Nightly HRV", hrv)
                }
                Text("Compared with \(stress.baseline_nights) earlier nights")
                    .font(.caption).foregroundStyle(Obs.muted)
            }
            DisclosureGroup("About this estimate") {
                Text(stress.method).font(.footnote).foregroundStyle(Obs.ink2).padding(.top, 6)
            }.font(.subheadline).tint(Obs.good).foregroundStyle(Obs.ink)
        }.frame(maxWidth: .infinity, alignment: .leading).obsCard()
    }
    private func measurement(_ title: String, _ reading: PersonalInsights.OvernightStress.Measurement) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(Obs.muted)
            Text(String(format: "%.1f %@ · baseline %.1f %@", reading.value, reading.unit, reading.baseline, reading.unit))
                .font(.subheadline.weight(.medium)).foregroundStyle(Obs.ink)
        }
    }
}

private struct WeeklyObservationCard: View {
    let metric: WeeklyObservation
    private func value(_ reading: Double?) -> String {
        reading.map { String(format: "%.1f %@", $0, metric.unit) } ?? "No readings"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(metric.title).font(.headline).foregroundStyle(Obs.ink)
            VStack(spacing: 10) {
                ObsStat(label: "Last 7 days", value: value(metric.current))
                ObsStat(label: "Previous 7 days", value: value(metric.previous))
            }
            Text("\(metric.current_nights)/7 nights · previous \(metric.previous_nights)/7 nights")
                .font(.caption).foregroundStyle(Obs.muted)
            if let delta = metric.delta, metric.comparable {
                Text(String(format: "%+.1f %@ change in the recorded average", delta, metric.unit))
                    .font(.subheadline).foregroundStyle(Obs.ink2)
            } else {
                Text("At least 3 recorded nights in each week are needed to show a change.")
                    .font(.caption).foregroundStyle(Obs.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).obsCard()
    }
}
