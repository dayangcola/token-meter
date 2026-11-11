import XCTest
@testable import QuotaCore

final class QuotaParserTests: XCTestCase {
    func testRealShapeAndFractionalDates() throws {
        let data = Data("""
        [{"provider":"codex","source":"oauth","usage":{"primary":{"usedPercent":30,"windowMinutes":300,"resetsAt":"2026-11-11T19:15:00.000Z"},"secondary":{"usedPercent":60,"windowMinutes":10080},"updatedAt":"2026-11-11T18:10:22Z","accountEmail":"private@example.invalid","loginMethod":"pro"},"resetCredits":{"available":2}}]
        """.utf8)
        let snapshot = try QuotaParser.parse(data, for: .codex, now: Date(timeIntervalSince1970: 1794507022))
        XCTAssertEqual(snapshot.windows.map(\.remaining), [70, 40])
        XCTAssertEqual(snapshot.windows.map(\.label), ["5 小时", "每周"])
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertEqual(snapshot.plan, "Pro")
        XCTAssertEqual(snapshot.resetCredits, 2)
    }

    func testUnknownAndInvalidPercentagesNeverBecomeUnusedQuota() {
        for value in ["null", "-1", "101", "true", "\"25\""] {
            let data = Data("{\"provider\":\"grok\",\"usage\":{\"primary\":{\"usedPercent\":\(value)}}}".utf8)
            XCTAssertThrowsError(try QuotaParser.parse(data, for: .grok))
        }
    }

    func testZeroAndExhaustionAreValid() throws {
        for value in [0, 100] {
            let data = Data("{\"provider\":\"claude\",\"usage\":{\"primary\":{\"usedPercent\":\(value)}}}".utf8)
            XCTAssertEqual(try QuotaParser.parse(data, for: .claude).windows[0].remaining, Double(100-value))
        }
    }

    func testRejectsWrongProviderAndReadsGeminiFromAntigravity() {
        let data = Data("{\"provider\":\"antigravity\",\"source\":\"cli\",\"usage\":{\"primary\":{\"usedPercent\":5}}}".utf8)
        XCTAssertThrowsError(try QuotaParser.parse(data, for: .codex))
        XCTAssertNoThrow(try QuotaParser.parse(data, for: .gemini))
        let other = Data("{\"provider\":\"gemini\",\"source\":\"web\",\"usage\":{\"primary\":{\"usedPercent\":5}}}".utf8)
        XCTAssertThrowsError(try QuotaParser.parse(other, for: .gemini))
    }

    func testAuthenticationErrorsAreSanitized() {
        let data = Data("{\"provider\":\"codex\",\"error\":{\"message\":\"OAuth token expired secret-value\"}}".utf8)
        XCTAssertThrowsError(try QuotaParser.parse(data, for: .codex)) { error in
            XCTAssertEqual(error as? QuotaError, .authentication)
            XCTAssertFalse((error as? QuotaError)?.message.contains("secret-value") ?? true)
        }
    }

    func testMissingLocalLoginAsksForConnection() {
        // Real CodexBar 0.84.0 replies when no CLI login or approved browser session exists.
        for message in ["No available fetch strategy for grok.", "Claude Code credentials changed (Updated 11m ago). Click Refresh to re-grant CodexBar access.", "Antigravity language server not detected. Launch Antigravity and retry."] {
            let data = Data("{\"provider\":\"grok\",\"error\":{\"message\":\"\(message)\"}}".utf8)
            XCTAssertThrowsError(try QuotaParser.parse(data, for: .grok)) { XCTAssertEqual($0 as? QuotaError, .authentication) }
        }
    }

    func testAntigravityPoolsKeepTheirNames() throws {
        // Shape returned by CodexBar 0.84.0 for a signed-in agy 1.5.5.
        let data = Data("""
        {"provider":"antigravity","source":"cli","rateWindowLabels":{"primary":"Gemini Models","secondary":"Claude and GPT"},"usage":{"primary":{"usedPercent":0,"windowMinutes":300},"secondary":{"usedPercent":0,"windowMinutes":300},"extraRateWindows":[{"id":"antigravity-quota-summary-gemini-5h","title":"Gemini 5-hour","window":{"usedPercent":0,"windowMinutes":300}},{"id":"gw","title":"Gemini weekly","window":{"usedPercent":0,"windowMinutes":10080}},{"id":"t5","title":"Claude/GPT 5-hour","window":{"usedPercent":0,"windowMinutes":300}},{"id":"antigravity-quota-summary-gemini-argon-wtu-weekly","title":"Gemini 4 Argon weekly","window":{"usedPercent":5,"windowMinutes":10080}}]}}
        """.utf8)
        let snapshot = try QuotaParser.parse(data, for: .gemini)
        XCTAssertEqual(snapshot.windows.map(\.label), ["Gemini · 5 小时", "Gemini 4 Argon · 每周"])
    }

    func testClaudeShowsOnlySessionAndWeekly() throws {
        // Shape returned by CodexBar 0.84.0 for Claude Code OAuth; numbers are made up.
        let data = Data("""
        {"provider":"claude","source":"oauth","rateWindowLabels":{"primary":"Session","secondary":"Weekly"},"usage":{"primary":{"usedPercent":40,"windowMinutes":300},"secondary":{"usedPercent":80,"windowMinutes":10080},"tertiary":null,"extraRateWindows":[{"id":"claude-weekly-scoped-fable","title":"Fable only","window":{"usedPercent":30,"windowMinutes":10080}}]}}
        """.utf8)
        let snapshot = try QuotaParser.parse(data, for: .claude)
        XCTAssertEqual(snapshot.windows.map(\.label), ["5 小时", "每周"])
        XCTAssertEqual(snapshot.windows.map(\.remaining), [60, 20])
    }

    func testExpiredResetDoesNotInventFreshQuota() {
        let now = Date()
        let window = QuotaWindow(id: "x", label: "每周", usedPercent: 85, resetsAt: now.addingTimeInterval(-10))
        XCTAssertTrue(window.needsResetConfirmation(at: now))
        XCTAssertEqual(window.remaining, 15)
    }
}
