import SwiftUI
import Security

private enum PCSecret {
    private static let account = "pc-analysis-connection-code"
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ value: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Never forward credentials or health uploads to a redirect target.
private final class PCSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct PCReport: Decodable {
    let service_version: Int
    let generated_at: String
    let notes: [String]
    let summary: Summary
}

struct PCAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var ring: RingSync
    let profile: Profile?
    @AppStorage("pc.analysis.url") private var address = ""
    @State private var code = PCSecret.load()
    @State private var busy = false
    @State private var message = ""
    @State private var report: PCReport?

    private static var reportURL: URL {
        DB.url.deletingLastPathComponent().appendingPathComponent("pc-analysis-report.json")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Windows computer") {
                    TextField("https://your-pc.your-tailnet.ts.net", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("PC connection code", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Use the HTTPS address from Tailscale Serve and the code displayed by Start-Analysis. This is separate from your ring pairing key.")
                        .font(.footnote)
                }
                Section {
                    Button("Test connection") { Task { await request(analyze: false) } }
                    Button(busy ? "Working…" : "Send ring data and analyze") {
                        Task { await request(analyze: true) }
                    }
                    .disabled(profile == nil || ring.busy)
                    if busy { ProgressView() }
                    if !message.isEmpty { Text(message).font(.footnote) }
                } footer: {
                    Text("Sends a copy of your raw ring database and saved profile only when you tap Analyze. Your PC must be on, with Tailscale connected on both devices. Save your correct profile first. The PC deletes the temporary copy after processing.")
                }
                .disabled(busy)
                if let report {
                    Section("PC report · \(report.generated_at)") {
                        Text(report.summary.digest ?? "Report received")
                        ForEach(report.notes, id: \.self) { Text($0).font(.footnote) }
                        if report.summary.nights.isEmpty {
                            Text("No nights available yet. Wear the ring overnight, sync, then analyze again.")
                        }
                        ForEach(report.summary.days, id: \.self) { day in
                            NavigationLink(day) {
                                DayReportView(s: report.summary, day: day, tab: .sleep)
                            }
                        }
                    }
                    Section {
                        Button("Delete saved PC report", role: .destructive) {
                            self.report = nil
                            try? FileManager.default.removeItem(at: Self.reportURL)
                        }
                    } footer: {
                        Text("This report is a saved snapshot, separate from the live iPhone dashboard. Analyze again after syncing new ring data. Signal-derived sleep stages are estimates; private ML weights are not bundled.")
                    }
                }
            }
            .navigationTitle("PC analysis")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                if let data = try? Data(contentsOf: Self.reportURL) {
                    report = try? JSONDecoder().decode(PCReport.self, from: data)
                }
            }
        }
    }

    private func request(analyze: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            guard let base = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
                  base.scheme == "https", let host = base.host,
                  host.lowercased().hasSuffix(".ts.net"),
                  base.user == nil, base.password == nil,
                  base.port == nil || base.port == 443,
                  base.query == nil, base.fragment == nil,
                  base.path.isEmpty || base.path == "/" else {
                throw PCError.message("Enter your PC's HTTPS .ts.net address, without a path.")
            }
            let secret = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard secret.count >= 32, !secret.contains("\n"), !secret.contains("\r") else {
                throw PCError.message("Paste the connection code from your Windows service.")
            }
            PCSecret.save(secret)
            let offset = Double(TimeZone.current.secondsFromGMT()) / 3600
            var components = base
            components.path = analyze ? "/v1/analyze" : "/v1/health"
            if analyze { components.queryItems = [URLQueryItem(name: "tz", value: String(offset))] }
            guard let url = components.url else { throw PCError.message("Invalid PC address.") }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 360
            config.timeoutIntervalForResource = 420
            let session = URLSession(configuration: config, delegate: PCSessionDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let data: Data
            let response: URLResponse
            if analyze {
                guard let profile else { throw PCError.message("Save your profile first.") }
                message = "Preparing a consistent ring database copy…"
                guard let snapshot = await ring.exportRawDatabase() else {
                    throw PCError.message("Could not export the database. Sync your ring first.")
                }
                defer { try? FileManager.default.removeItem(at: snapshot) }
                let size = (try FileManager.default.attributesOfItem(atPath: snapshot.path)[.size] as? NSNumber)?.intValue ?? 0
                guard size > 0, size <= 256 * 1024 * 1024 else {
                    throw PCError.message("Database must be smaller than 256 MB.")
                }
                request.httpMethod = "POST"
                request.setValue("application/vnd.sqlite3", forHTTPHeaderField: "Content-Type")
                request.setValue(String(size), forHTTPHeaderField: "Content-Length")
                request.setValue(try JSONEncoder().encode(profile).base64EncodedString(),
                                 forHTTPHeaderField: "X-OpenHealth-Profile")
                message = "Sending to your PC and analyzing… This may take up to five minutes."
                (data, response) = try await session.upload(for: request, fromFile: snapshot)
            } else {
                message = "Connecting to your PC…"
                (data, response) = try await session.data(for: request)
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                throw PCError.message(object?["error"] as? String ?? "PC request failed. Check Tailscale, the address and connection code.")
            }
            if analyze {
                let result = try JSONDecoder().decode(PCReport.self, from: data)
                guard result.service_version == 1, result.summary.error == nil else {
                    throw PCError.message("The PC returned an unsupported or unsuccessful report.")
                }
                try data.write(to: Self.reportURL, options: [.atomic, .completeFileProtection])
                report = result
                message = "PC report received and saved on this iPhone."
            } else {
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard object?["service_version"] as? Int == 1,
                      object?["engine_available"] as? Bool == true else {
                    throw PCError.message("PC service responded, but its analysis engine is unavailable.")
                }
                message = "Connected. PC analysis engine is ready."
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

private enum PCError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
