import SwiftUI

struct DataQuality: Codable {
    struct Battery: Codable {
        let status: String
        let samples: Int
        let span_hours: Double
        let latest_age_hours: Double?
        let net_drop_points: Double?
        let points_per_day: Double?
        let start_at: Double?
        let end_at: Double?
        let message: String
        let method: String
    }
    struct Coverage: Codable {
        struct SleepRecord: Codable {
            let end_at: Double
            let duration_min: Double
            let source: String?
            let reason: String
            let explanation: String
            let usable_hr_samples: Int
            let hrv_samples: Int
            let motion_samples: Int
        }
        let sleep_records: [SleepRecord]?
        struct Signal: Codable, Identifiable {
            let id: String
            let title: String
            let bins: Int
            let outside_sleep_bins: Int
        }
        let window_start: Double
        let window_end: Double
        let latest_sample_at: Double?
        let signals: [Signal]
        let recorded_nights: Int
        let complete_staging_nights: Int
        let candidate_overlap_bins: Int
        let message: String
        let next_step: String
    }
    let generated_at: Double
    let battery: Battery
    let coverage: Coverage
    let untrusted_clock_packets: Int
    let scope: String
    var exportText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "Could not prepare diagnostics." }
        return text
    }
}

struct DataQualityView: View {
    let quality: DataQuality
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ring.diagnostics.inspect-next-sync") private var inspectNextSync = true
    private func date(_ at: Double) -> String {
        Date(timeIntervalSince1970: at).formatted(date: .abbreviated, time: .shortened)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Snapshot: \(date(quality.generated_at))").font(.caption).foregroundStyle(Obs.muted)
                    batteryCard
                    coverageCard
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Read-only ring mode check").font(.headline)
                        Text(inspectNextSync ? "Queued for your next manual sync or pull-to-refresh." : "Use this to request another one-time check during a manual sync.")
                        Button("Queue mode check") { inspectNextSync = true }.disabled(inspectNextSync)
                        Text("Reads daytime HR, exercise HR, SpO₂ and raw-sampler status. Makes no setting changes. Responses appear in Technical reports; four reads may add up to 12 seconds to that sync.").font(.footnote).foregroundStyle(Obs.muted)
                    }.foregroundStyle(Obs.ink).obsCard()
                    Text(quality.scope).font(.footnote).foregroundStyle(Obs.muted)
                    ShareLink(item: quality.exportText) {
                        Label("Share diagnostic summary", systemImage: "square.and.arrow.up")
                    }.font(.headline)
                    Text("Shares the counts, timestamps, sleep-record summaries and battery observations shown here. Raw ring records, pairing keys and your profile are not included.")
                        .font(.footnote).foregroundStyle(Obs.muted)
                }.padding(20)
            }.background(Obs.paper)
                .navigationTitle("Data & battery")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(Obs.good)
    }
    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Observed battery change", systemImage: "battery.75percent").font(.headline)
            if let rate = quality.battery.points_per_day, let drop = quality.battery.net_drop_points {
                Text(String(format: "%.1f percentage points / day", rate)).font(.title2.bold())
                Text(String(format: "Net drop %.0f points across %.1f hours", drop, quality.battery.span_hours)).font(.subheadline)
            } else {
                Text("Collecting baseline").font(.title2.bold())
            }
            Text(quality.battery.message).font(.subheadline).foregroundStyle(Obs.ink2)
            Text("\(quality.battery.samples) readings in the current segment").font(.caption).foregroundStyle(Obs.muted)
            if let at = quality.battery.end_at {
                Text("Latest included reading: \(date(at))").font(.caption).foregroundStyle(Obs.muted)
            }
            DisclosureGroup("How this is calculated") { Text(quality.battery.method).font(.footnote).padding(.top, 6) }
        }.foregroundStyle(Obs.ink).frame(maxWidth: .infinity, alignment: .leading).obsCard()
    }
    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Saved signal coverage", systemImage: "waveform.path.ecg").font(.headline)
            Text("Last 7 calendar days, through this snapshot").font(.caption).foregroundStyle(Obs.muted)
            ObsStat(label: "Sleep records", value: "\(quality.coverage.recorded_nights)")
            ObsStat(label: "Fully staged records", value: "\(quality.coverage.complete_staging_nights)")
            Text("Fully staged means the estimator covered the recorded window; it does not establish sleep-stage accuracy.")
                .font(.footnote).foregroundStyle(Obs.muted)
            ForEach(quality.coverage.signals) { signal in
                Divider()
                Text(signal.title).font(.subheadline.bold())
                Text("\(signal.bins) bins with data · \(signal.outside_sleep_bins) outside recorded sleep")
                    .font(.subheadline).foregroundStyle(Obs.ink2)
            }
            DisclosureGroup("Sleep-record details") {
                ForEach(Array((quality.coverage.sleep_records ?? []).enumerated()), id: \.offset) { _, record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(date(record.end_at)).font(.subheadline.bold())
                        Text(String(format: "%.0f min · source %@", record.duration_min, record.source ?? "none"))
                        Text(record.explanation)
                        Text("Usable HR: \(record.usable_hr_samples) · HRV: \(record.hrv_samples) · movement: \(record.motion_samples)")
                    }.font(.footnote).padding(.vertical, 6)
                }
            }
            Text(quality.coverage.message).font(.footnote).foregroundStyle(Obs.muted)
            DisclosureGroup("Daytime stress feasibility") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(quality.coverage.candidate_overlap_bins) outside-sleep bins contain HR, HRV and movement samples.")
                    Text(quality.coverage.next_step)
                    Text("\(quality.untrusted_clock_packets) relevant packets across saved history excluded because their clocks are not anchored reliably.")
                }.font(.footnote).foregroundStyle(Obs.ink2).padding(.top, 6)
            }
        }.foregroundStyle(Obs.ink).frame(maxWidth: .infinity, alignment: .leading).obsCard()
    }
}
