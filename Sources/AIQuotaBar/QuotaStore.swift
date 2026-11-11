import AppKit
import SwiftUI
import QuotaCore

struct ProviderState {
    var snapshot: QuotaSnapshot?
    var error: QuotaError?
    var isLoading = false
    var hasAttempted = false
    var lastAttempt: Date?
}

enum QuotaReader {
    /// Claude Code keeps its login only in the macOS Keychain, and the bundled helper never opens that item itself.
    /// macOS asks the user before `security` may read it; the token stays in memory and goes to the helper by environment.
    static func claudeToken() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw QuotaError.authentication }
        let deadline = Date().addingTimeInterval(90)
        while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        if process.isRunning { process.terminate(); throw QuotaError.needsPermission }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { throw QuotaError.needsPermission }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = root["claudeAiOauth"] as? [String: Any],
              let token = login["accessToken"] as? String, !token.isEmpty else { throw QuotaError.authentication }
        if let expires = login["expiresAt"] as? Double, Date(timeIntervalSince1970: expires / 1000) <= Date() { throw QuotaError.authentication }
        return token
    }

    static func fetch(_ provider: Provider, keychainAllowed: Bool = true) async throws -> QuotaSnapshot {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexBarCLI")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw QuotaError.helperMissing }
        var claudeToken: String?
        if provider == .claude {
            guard keychainAllowed else { throw QuotaError.needsPermission }
            claudeToken = try await QuotaReader.claudeToken()
        }
        let token = claudeToken
        return try await Task.detached(priority: .utility) {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("aiquota-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: work) }
            let out = work.appendingPathComponent("stdout")
            let err = work.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: out.path, contents: nil, attributes: [.posixPermissions: 0o600])
            FileManager.default.createFile(atPath: err.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: out)
            let errors = try FileHandle(forWritingTo: err)
            defer { try? output.close(); try? errors.close() }
            let process = Process()
            process.executableURL = helper
            process.arguments = ["usage", "--provider", provider.helperName, "--source", provider.source, "--format", "json", "--json-only", "--no-color"]
            let inherited = ProcessInfo.processInfo.environment
            let allowed = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "CODEX_HOME", "XDG_CONFIG_HOME", "CODEXBAR_CONFIG", "GROK_HOME"]
            var environment = inherited.filter { allowed.contains($0.key) }
            environment["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["NO_COLOR"] = "1"
            environment["CODEXBAR_ALLOW_BROWSER_COOKIE_IMPORT"] = "0"
            if let token { environment["CODEXBAR_CLAUDE_OAUTH_TOKEN"] = token }
            process.environment = environment
            process.standardOutput = output
            process.standardError = errors
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { throw QuotaError.helperMissing }
            let deadline = Date().addingTimeInterval(35)
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
            if process.isRunning {
                process.terminate()
                let grace = Date().addingTimeInterval(2)
                while process.isRunning && Date() < grace { try await Task.sleep(for: .milliseconds(50)) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw QuotaError.timeout
            }
            process.waitUntilExit()
            let reader = try FileHandle(forReadingFrom: out)
            defer { try? reader.close() }
            let data = try reader.read(upToCount: 1_048_577) ?? Data()
            guard data.count <= 1_048_576 else { throw QuotaError.invalidResponse }
            do { return try QuotaParser.parse(data, for: provider) }
            catch {
                if let error = error as? QuotaError, error != .invalidResponse { throw error }
                if process.terminationStatus == 0 { throw QuotaError.invalidResponse }
                let errorReader = try FileHandle(forReadingFrom: err)
                defer { try? errorReader.close() }
                let stderr = try errorReader.read(upToCount: 8192) ?? Data()
                throw QuotaError.classify(String(decoding: stderr + data, as: UTF8.self))
            }
        }.value
    }
}

@MainActor
final class QuotaStore: ObservableObject {
    @Published var states = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, ProviderState()) })
    @Published var isPinned = false
    @Published var isDemo = false
    @Published var now = Date()
    @Published var autoRefresh: Bool { didSet { UserDefaults.standard.set(autoRefresh, forKey: "autoRefresh") } }
    var onPin: (() -> Void)?
    var onClose: (() -> Void)?
    var onStatusChanged: (() -> Void)?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastRefresh: Date?

    init(demo: Bool) {
        autoRefresh = UserDefaults.standard.object(forKey: "autoRefresh") as? Bool ?? true
        isDemo = demo
        if demo { loadDemo() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                guard self.autoRefresh, self.lastRefresh.map({ self.now.timeIntervalSince($0) >= 300 }) ?? true else { return }
                self.refreshAll()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, self.autoRefresh else { return }; self.refreshAll() }
        }
    }

    var isLoading: Bool { states.values.contains(where: \.isLoading) }
    var connectedCount: Int { states.values.filter { $0.snapshot != nil }.count }
    var lowCount: Int {
        states.values.filter { state in
            guard state.error == nil, let snapshot = state.snapshot, Date().timeIntervalSince(snapshot.measuredAt) < 600 else { return false }
            return snapshot.windows.contains { $0.remaining < 20 && !$0.needsResetConfirmation(at: Date()) }
        }.count
    }

    func refreshIfNeeded() {
        guard !isDemo, !isLoading else { return }
        if lastRefresh == nil || Date().timeIntervalSince(lastRefresh!) >= 300 { refreshAll() }
    }

    func refreshAll() {
        guard !isDemo else { return }
        lastRefresh = Date()
        for provider in Provider.allCases {
            // An authentication failure waits for explicit reconnect instead of repeatedly prompting.
            if states[provider]?.error == .authentication || states[provider]?.error == .needsPermission { continue }
            refresh(provider, interactive: false)
        }
    }

    func refresh(_ provider: Provider, interactive: Bool) {
        guard !isDemo, states[provider]?.isLoading != true else { return }
        states[provider]?.isLoading = true
        states[provider]?.hasAttempted = true
        states[provider]?.lastAttempt = Date()
        Task {
            do {
                // The Keychain is touched only after the user pressed 读取 for Claude at least once.
                let allowed = interactive || UserDefaults.standard.bool(forKey: "claudeKeychainApproved")
                let snapshot = try await QuotaReader.fetch(provider, keychainAllowed: allowed)
                if provider == .claude { UserDefaults.standard.set(true, forKey: "claudeKeychainApproved") }
                states[provider]?.snapshot = snapshot
                states[provider]?.error = nil
            } catch {
                states[provider]?.error = (error as? QuotaError) ?? .unavailable
            }
            states[provider]?.isLoading = false
            onStatusChanged?()
        }
    }

    func openUsage(_ provider: Provider) { NSWorkspace.shared.open(provider.loginURL) }

    func connect(_ provider: Provider) { refresh(provider, interactive: true) }

    func loadDemo() {
        let now = Date()
        for (provider, values) in zip(Provider.allCases, [[32.0, 47.0], [86, 62], [15], [42, 23]]) {
            let windows = values.enumerated().map { i, used in
                QuotaWindow(id: "\(i)", label: provider == .grok || i == 1 ? "每周" : "5 小时", usedPercent: used, resetsAt: now.addingTimeInterval(i == 1 || provider == .grok ? 180000 : 7200))
            }
            states[provider] = ProviderState(snapshot: QuotaSnapshot(windows: windows, measuredAt: now, source: provider.source, plan: provider == .codex ? "Pro" : nil, resetCredits: provider == .codex ? 2 : nil), hasAttempted: true)
        }
    }
}
