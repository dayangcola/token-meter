import Foundation

public enum Provider: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex, claude, grok, gemini
    public var id: String { rawValue }
    public var name: String {
        switch self { case .codex: "Codex"; case .claude: "Claude"; case .grok: "Grok"; case .gemini: "Gemini" }
    }
    public var subtitle: String {
        switch self { case .codex: "Codex 会员额度"; case .claude: "Claude 会员额度"; case .grok: "Grok 会员额度"; case .gemini: "Gemini 会员额度 · Antigravity CLI" }
    }
    public var loginURL: URL {
        let address = switch self {
        case .codex: "https://chatgpt.com/codex/settings/usage"
        case .claude: "https://claude.ai/settings/usage"
        case .grok: "https://grok.com/dashboard"
        case .gemini: "https://gemini.google.com/usage"
        }
        return URL(string: address)!
    }
    /// Every provider reads the login of its own local CLI; no browser session is used.
    public var source: String {
        switch self { case .gemini: "cli"; default: "oauth" }
    }
    /// Google ended Gemini CLI sign-in for personal plans, so Gemini quota comes from the Antigravity CLI (`agy`).
    public var helperName: String {
        switch self { case .gemini: "antigravity"; default: rawValue }
    }
    public var cliCommand: String {
        switch self { case .codex: "codex"; case .claude: "claude"; case .grok: "grok"; case .gemini: "agy" }
    }
}

public struct QuotaWindow: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let isWeekly: Bool
    public var remaining: Double { 100 - usedPercent }
    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?, isWeekly: Bool = false) {
        self.id = id; self.label = label; self.usedPercent = usedPercent; self.resetsAt = resetsAt; self.isWeekly = isWeekly
    }
    /// A weekly window that refills within 48 hours: the reset time is worth noticing.
    public func weeklyResetIsNear(at now: Date) -> Bool {
        guard isWeekly, let resetsAt else { return false }
        let left = resetsAt.timeIntervalSince(now)
        return left > 0 && left < 48 * 3600
    }
    public func needsResetConfirmation(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }
}

public struct QuotaSnapshot: Sendable {
    public let windows: [QuotaWindow]
    public let measuredAt: Date
    public let source: String
    public let plan: String?
    public let resetCredits: Int?
    public init(windows: [QuotaWindow], measuredAt: Date, source: String, plan: String? = nil, resetCredits: Int? = nil) {
        self.windows = windows; self.measuredAt = measuredAt; self.source = source; self.plan = plan; self.resetCredits = resetCredits
    }
}

public enum QuotaError: Error, Equatable, Sendable {
    case invalidResponse, unavailable, authentication, timeout, network, helperMissing, needsPermission
    public var message: String {
        switch self {
        case .invalidResponse: "额度格式暂时无法识别"
        case .unavailable: "此账号暂未返回可用额度"
        case .authentication: "需要在终端登录对应的 CLI"
        case .timeout: "读取超时，请稍后刷新"
        case .network: "暂时无法连接，稍后自动重试"
        case .helperMissing: "额度读取组件缺失，请重新构建"
        case .needsPermission: "点「读取」，并在钥匙串提示里允许"
        }
    }
    public static func classify(_ text: String) -> QuotaError {
        let s = text.lowercased()
        if ["timed out", "timeout"].contains(where: s.contains) { return .timeout }
        if ["401", "403", "auth", "login", "log in", "sign in", "sign-in", "credential", "cookie", "keychain", "session key", "oauth", "no token", "fetch strategy", "not found", "not detected", "signed out"].contains(where: s.contains) { return .authentication }
        if ["network", "connect", "dns", "offline", "resolve", "internet", "server", "502", "503"].contains(where: s.contains) { return .network }
        return .unavailable
    }
}

public enum QuotaParser {
    public static func parse(_ data: Data, for provider: Provider, now: Date = Date()) throws -> QuotaSnapshot {
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data) } catch { throw QuotaError.invalidResponse }
        let rows: [[String: Any]]
        if let array = root as? [[String: Any]] { rows = array }
        else if let object = root as? [String: Any] { rows = [object] }
        else { throw QuotaError.invalidResponse }
        guard let row = rows.first(where: { ($0["provider"] as? String) == provider.helperName }) else { throw QuotaError.invalidResponse }
        guard let usage = row["usage"] as? [String: Any] else {
            let error = row["error"] as? [String: Any]
            throw QuotaError.classify((error?["message"] as? String) ?? (row["error"] as? String) ?? "")
        }
        let source = (row["source"] as? String) ?? ""
        let labels = row["rateWindowLabels"] as? [String: String] ?? [:]
        var windows: [QuotaWindow] = []
        let extras = usage["extraRateWindows"] as? [[String: Any]] ?? []
        // Antigravity repeats its two 5-hour pools as primary/secondary; the named extra windows are the full list.
        if !(provider == .gemini && !extras.isEmpty) {
            for key in ["primary", "secondary", "tertiary"] {
                guard let raw = usage[key] as? [String: Any] else { continue }
                if let window = window(raw, id: key, provider: provider, label: labels[key]) { windows.append(window) }
            }
        }
        // Author's choice (see README): of the Antigravity pools show only Gemini 5-hour and Gemini 4 Argon weekly.
        let wanted = extras.filter { raw in
            let id = (raw["id"] as? String ?? "").lowercased()
            return id.hasSuffix("summary-gemini-5h") || (id.contains("argon") && id.hasSuffix("weekly"))
        }
        // Author's choice (see README): Claude shows only the 5-hour and weekly windows, not model-scoped ones.
        let shown = provider == .claude ? [] : provider == .gemini && !wanted.isEmpty ? wanted : extras
        for (index, raw) in shown.enumerated() {
            let id = (raw["id"] as? String) ?? "extra-\(index)"
            let value = (raw["window"] as? [String: Any]) ?? raw
            guard var window = window(value, id: id, provider: provider, label: raw["label"] as? String ?? raw["title"] as? String) else { continue }
            // Several pools share one period, so keep the pool name in front: "Gemini 5-hour" -> "Gemini · 5 小时".
            if let title = raw["title"] as? String ?? raw["label"] as? String {
                var pool = title
                for suffix in [" 5-hour", " weekly", " monthly", " daily", " only"] where pool.lowercased().hasSuffix(suffix) { pool = String(pool.dropLast(suffix.count)) }
                if !pool.isEmpty, !window.label.contains(pool) { window = QuotaWindow(id: window.id, label: "\(String(pool.prefix(32))) · \(window.label)", usedPercent: window.usedPercent, resetsAt: window.resetsAt, isWeekly: window.isWeekly) }
            }
            windows.append(window)
        }
        guard !windows.isEmpty else { throw QuotaError.unavailable }
        let measuredAt = date(usage["updatedAt"]) ?? now
        guard measuredAt.timeIntervalSince(now) <= 60 else { throw QuotaError.invalidResponse }
        let identity = usage["identity"] as? [String: Any]
        let rawPlan = (usage["loginMethod"] as? String) ?? (identity?["loginMethod"] as? String)
        let allowedPlans = ["plus", "pro", "max", "team", "enterprise", "free", "ultra", "supergrok", "supergrok lite", "supergrok heavy", "paid"]
        let plan = rawPlan.flatMap { allowedPlans.contains($0.lowercased()) ? $0.capitalized : nil }
        let credits = (row["resetCredits"] as? [String: Any])?["available"] as? Int
        return QuotaSnapshot(windows: windows, measuredAt: measuredAt, source: source, plan: plan, resetCredits: credits)
    }

    private static func window(_ raw: [String: Any], id: String, provider: Provider, label: String?) -> QuotaWindow? {
        guard let n = raw["usedPercent"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let used = n.doubleValue
        guard used.isFinite, (0...100).contains(used) else { return nil }
        let minutes = (raw["windowMinutes"] as? Double) ?? (raw["windowDurationMins"] as? Double)
        let title: String
        if let minutes {
            if minutes == 300 { title = "5 小时" }
            else if minutes == 10080 { title = "每周" }
            else if minutes >= 40000 && minutes <= 45000 { title = "每月" }
            else if minutes == 1440 { title = "每日" }
            else if minutes >= 60, minutes.truncatingRemainder(dividingBy: 60) == 0 { title = "\(Int(minutes / 60)) 小时" }
            else { title = label ?? "当前额度" }
        } else if let label, !label.isEmpty { title = translated(label) }
        else { title = id == "secondary" ? "第二额度窗口" : "当前额度" }
        return QuotaWindow(id: id, label: title, usedPercent: used, resetsAt: date(raw["resetsAt"]), isWeekly: minutes == 10080)
    }

    private static func translated(_ label: String) -> String {
        switch label.lowercased() { case "session", "5-hour", "5 hour": "5 小时"; case "weekly", "week": "每周"; case "monthly", "month": "每月"; case "credits": "会员额度"; default: String(label.prefix(48)) }
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

import CoreFoundation
