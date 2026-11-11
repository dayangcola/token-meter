import SwiftUI
import QuotaCore

extension Provider {
    var tint: Color {
        switch self { case .codex: Color(red: 0.37, green: 0.87, blue: 0.72); case .claude: Color(red: 0.92, green: 0.64, blue: 0.46); case .grok: Color(red: 0.85, green: 0.88, blue: 0.94); case .gemini: Color(red: 0.59, green: 0.68, blue: 1) }
    }
    var symbol: String {
        switch self { case .codex: "terminal"; case .claude: "sun.max"; case .grok: "slash.circle"; case .gemini: "sparkle" }
    }
}

struct OverviewView: View {
    @ObservedObject var store: QuotaStore
    private let muted = Color.white.opacity(0.43)

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 6) {
                if store.isDemo {
                    Label("演示数据 · 仅预览界面", systemImage: "eye")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                        .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                ForEach(Provider.allCases) { provider in
                    ProviderCard(provider: provider, state: store.states[provider] ?? ProviderState(), store: store)
                }
            }.padding(.horizontal, 10).padding(.bottom, 8)
            footer
        }
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(red: 0.055, green: 0.065, blue: 0.085).opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.10), lineWidth: 1))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("AI 额度").font(.system(size: 14, weight: .semibold))
            Text(store.lowCount > 0 ? "\(store.lowCount) 家偏低" : "\(store.connectedCount)/4")
                .font(.system(size: 12)).foregroundStyle(store.lowCount > 0 ? .orange : muted)
            Spacer()
            Button { store.onPin?() } label: {
                Image(systemName: store.isPinned ? "pin.fill" : "pin").rotationEffect(.degrees(store.isPinned ? 0 : 35))
            }.help(store.isPinned ? "取消固定" : "固定面板")
            .accessibilityLabel(store.isPinned ? "取消固定" : "固定面板")
            Button { store.refreshAll() } label: {
                if store.isLoading { ProgressView().controlSize(.mini).frame(width: 12, height: 12) }
                else { Image(systemName: "arrow.clockwise") }
            }.disabled(store.isLoading || store.isDemo).help("刷新全部额度").accessibilityLabel("刷新全部额度")
            Menu {
                Toggle("每 5 分钟自动刷新", isOn: $store.autoRefresh)
                Button("打开使用说明") {
                    if let url = Bundle.main.url(forResource: "使用说明", withExtension: "html") { NSWorkspace.shared.open(url) }
                }
                Divider()
                Button("退出 AI 额度栏") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(muted).frame(width: 22, height: 22) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("设置").accessibilityLabel("设置")
        }
        .buttonStyle(HeaderButtonStyle())
        .padding(.leading, 14).padding(.trailing, 10).padding(.top, 9).padding(.bottom, 7)
    }

    private var footer: some View { EmptyView() }
}

struct ProviderCard: View {
    let provider: Provider
    let state: ProviderState
    @ObservedObject var store: QuotaStore
    private var stale: Bool {
        guard let snapshot = state.snapshot else { return false }
        return state.error != nil || store.now.timeIntervalSince(snapshot.measuredAt) > 600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: provider.symbol).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(provider.tint).frame(width: 16)
                Text(provider.name).font(.system(size: 13, weight: .semibold))
                if let plan = state.snapshot?.plan {
                    Text(plan).font(.system(size: 10, weight: .medium)).foregroundStyle(provider.tint.opacity(0.9))
                        .padding(.horizontal, 4).padding(.vertical, 1).background(provider.tint.opacity(0.08), in: Capsule())
                }
                Spacer(minLength: 4)
                if state.isLoading { ProgressView().controlSize(.mini).frame(width: 14, height: 14) }
                else if let snapshot = state.snapshot {
                    if stale { Image(systemName: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange) }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(ageText(snapshot.measuredAt, now: context.date)).font(.system(size: 11))
                    }.foregroundStyle(stale ? Color.orange.opacity(0.8) : .white.opacity(0.28))
                    if let count = snapshot.resetCredits, count > 0 {
                        Text("\(count) 次重置").font(.system(size: 11)).foregroundStyle(.white.opacity(0.28))
                    }
                    if state.error != nil {
                        Button("重试") { store.refresh(provider, interactive: true) }
                            .font(.system(size: 11, weight: .medium)).buttonStyle(.plain).foregroundStyle(provider.tint)
                    }
                    Button { store.openUsage(provider) } label: { Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium)) }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.38)).help("打开 \(provider.name) 用量页")
                        .accessibilityLabel("打开 \(provider.name) 用量页")
                } else {
                    Text(state.error?.message ?? "读取本机 \(provider.cliCommand) 登录")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    Button("读取") { store.connect(provider) }
                        .font(.system(size: 12, weight: .medium)).buttonStyle(.plain)
                        .foregroundStyle(provider.tint).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(provider.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("读取 \(provider.name)")
                }
            }
            if let snapshot = state.snapshot {
                VStack(spacing: 5) {
                    ForEach(snapshot.windows) { window in WindowRow(window: window, tint: provider.tint, stale: stale) }
                }.opacity(stale ? 0.55 : 1)
                if let error = state.error { Text(error.message).font(.system(size: 11)).foregroundStyle(.orange.opacity(0.8)) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.055), lineWidth: 1))
    }

    private func ageText(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return stale ? "上次成功：刚刚" : "刚刚" }
        if seconds < 3600 { return "\(stale ? "上次成功：" : "")\(seconds / 60) 分钟前" }
        return "\(stale ? "上次成功：" : "")\(seconds / 3600) 小时前"
    }
}

struct WindowRow: View {
    let window: QuotaWindow
    let tint: Color
    let stale: Bool
    private var color: Color { window.remaining < 10 ? .red : window.remaining < 20 ? .orange : tint }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let pending = window.needsResetConfirmation(at: context.date)
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(window.label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                    let near = !pending && window.weeklyResetIsNear(at: context.date)
                    Group {
                        if pending { Text("等待重置确认").foregroundStyle(.orange) }
                        else if let reset = window.resetsAt {
                            Text(countdown(reset, now: context.date)).help(reset.formatted(date: .complete, time: .shortened))
                        }
                    }
                    .font(.system(size: 11, weight: near ? .semibold : .regular))
                    .foregroundStyle(near ? Color.yellow : .white.opacity(0.3)).lineLimit(1)
                    .padding(.horizontal, near ? 5 : 0).padding(.vertical, near ? 1 : 0)
                    .background(near ? Color.yellow.opacity(0.14) : .clear, in: Capsule())
                    Spacer(minLength: 4)
                    if !pending {
                        Text("\(stale ? "上次 " : "")\(Int(window.remaining.rounded()))%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
                    }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.065))
                        Capsule().fill((pending ? Color.orange : color).gradient)
                            .frame(width: max(0, geometry.size.width * window.remaining / 100))
                    }
                }.frame(height: 4)
            }
            .accessibilityElement(children: .combine)
        }
    }
    private func countdown(_ reset: Date, now: Date) -> String {
        let minutes = max(1, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if minutes >= 1440 { return "\(minutes / 1440) 天 \(minutes % 1440 / 60) 小时后重置" }
        if minutes >= 60 { return "\(minutes / 60) 小时 \(minutes % 60) 分后重置" }
        return "\(minutes) 分钟后重置"
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12)).foregroundStyle(.white.opacity(configuration.isPressed ? 0.9 : 0.45))
            .frame(width: 22, height: 22).background(.white.opacity(configuration.isPressed ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
