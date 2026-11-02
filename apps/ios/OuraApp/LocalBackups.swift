import SwiftUI

struct LocalSnapshot: Identifiable {
    let url: URL
    let created: Date
    let bytes: Int64
    var id: String { url.lastPathComponent }
}

/// Bounded, self-contained data snapshots. Pairing/PC keys remain in Keychain.
@MainActor
final class LocalBackups: ObservableObject {
    static let shared = LocalBackups()
    static let retention = 3
    static let interval: TimeInterval = 24 * 60 * 60
    @Published private(set) var snapshots: [LocalSnapshot] = []
    @Published private(set) var working = false
    @Published private(set) var message: String?
    let folder: URL

    init(folder: URL = DB.url.deletingLastPathComponent().appendingPathComponent("LocalBackups", isDirectory: true)) {
        self.folder = folder
        refresh()
    }
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "data.local-backups.enabled") as? Bool ?? true
    }
    func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])) ?? []
        snapshots = files.filter { $0.lastPathComponent.hasPrefix("oura-snapshot-") && $0.pathExtension == "db" }
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
                      let date = values.creationDate else { return nil }
                return LocalSnapshot(url: url, created: date, bytes: Int64(values.fileSize ?? 0))
            }.sorted { $0.created > $1.created }
    }
    @discardableResult
    func capture(dbPath: String = DB.readPath(), force: Bool = false, now: Date = Date()) async -> URL? {
        guard !working, force || Self.enabled, FileManager.default.fileExists(atPath: dbPath) else { return nil }
        refresh()
        if !force, let last = snapshots.first, now.timeIntervalSince(last.created) < Self.interval { return nil }
        working = true
        defer { working = false }
        let file = folder.appendingPathComponent("oura-snapshot-\(UUID().uuidString).db")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var directory = folder
            var resource = URLResourceValues(); resource.isExcludedFromBackup = true
            try? directory.setResourceValues(resource)
            let failure: String? = await Task.detached {
                do { try exportDatabase(dbPath: dbPath, outPath: file.path); return nil }
                catch { return error.localizedDescription }
            }.value
            if let failure { throw NSError(domain: "openhealth.backup", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .creationDate: now], ofItemAtPath: file.path)
            refresh()
            for old in snapshots.dropFirst(Self.retention) { try FileManager.default.removeItem(at: old.url) }
            refresh()
            message = "Snapshot saved. Export a copy to Files to keep it outside this app."
            return file
        } catch {
            try? FileManager.default.removeItem(at: file)
            refresh()
            message = "Could not save a snapshot. Check available storage and try again."
            return nil
        }
    }
    func delete(_ item: LocalSnapshot) {
        guard !working else { return }
        do { try FileManager.default.removeItem(at: item.url); refresh(); message = "Snapshot deleted." }
        catch { message = "Could not delete this snapshot." }
    }
}

struct BackupCenterView: View {
    @ObservedObject var ring: RingSync
    let onManage: () -> Void
    @ObservedObject private var backups = LocalBackups.shared
    @AppStorage("data.local-backups.enabled") private var automatic = true
    @Environment(\.dismiss) private var dismiss
    @State private var share: URL?
    @State private var deletion: LocalSnapshot?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Daily on-device snapshots", isOn: $automatic)
                    Button(backups.working ? "Creating snapshot…" : "Create snapshot now") {
                        Task { _ = await backups.capture(force: true) }
                    }.disabled(backups.working || ring.busy)
                    if let message = backups.message { Text(message).font(.footnote).foregroundStyle(Obs.muted) }
                } footer: {
                    Text("After a successful foreground sync, a snapshot is saved at most once per 24 hours. The latest three are kept on this iPhone. These copies are not cloud backups and are lost if the app is deleted or the phone is lost.")
                }
                Section("Saved snapshots") {
                    if backups.snapshots.isEmpty { Text("No snapshots yet. Sync your ring, then create one.").foregroundStyle(Obs.muted) }
                    ForEach(backups.snapshots) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.created.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                            Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)).font(.caption).foregroundStyle(Obs.muted)
                            HStack {
                                Button("Save or share") { share = item.url }.buttonStyle(.borderless)
                                Spacer()
                                Button("Delete", role: .destructive) { deletion = item }.buttonStyle(.borderless)
                            }
                        }.padding(.vertical, 5)
                    }
                }
                Section("Keep a copy outside the app") {
                    Text("Use Save or share → Save to Files. Choose iCloud Drive or another location you control. Each .db file contains the ring records as of the snapshot date.")
                    Text("Pairing keys, PC connection codes and your profile settings are not included. Save your ring pairing key separately in a password manager; you may need it on another phone.")
                    Button("Open ring manager to restore a file") {
                        dismiss()
                        Task { try? await Task.sleep(nanoseconds: 350_000_000); onManage() }
                    }
                    Text("In the ring manager, choose Restore from a backup and select a .db file saved in Files. Restoring replaces the current on-phone ring history, so export current data first.")
                        .font(.footnote).foregroundStyle(Obs.muted)
                }
            }
            .scrollContentBackground(.hidden).background(Obs.paper)
            .navigationTitle("Backups & data")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { backups.refresh() }
            .sheet(isPresented: Binding(get: { share != nil }, set: { if !$0 { share = nil } })) {
                if let share { DiagnosticsShare(url: share) }
            }
            .confirmationDialog("Delete this local snapshot?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                if let deletion { Button("Delete snapshot", role: .destructive) { backups.delete(deletion); self.deletion = nil } }
            }
        }.tint(Obs.good)
    }
}
