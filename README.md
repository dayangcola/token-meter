# token-meter（AI 额度栏）

macOS 菜单栏小工具：一个面板看完 Codex、Claude、Grok、Gemini 四家订阅还剩多少额度、什么时候重置。

[English](#english)

## 它是什么，不是什么

- 真正去各家查询额度的是 [CodexBar](https://github.com/steipete/CodexBar) 的命令行程序（MIT）。本项目只是它外面的一层界面：中文、紧凑、只读本机 CLI 的登录。CodexBar 自己就是功能完整的菜单栏应用，支持的平台多得多；想要更多功能请直接用它。
- **非官方**。四家都没有公开的额度接口，这里借用各家 CLI 的登录去查询，对方调整接口后随时可能失效。是否符合各家服务条款请自行判断，风险自负。
- 不建立云服务，不上传任何数据，不读取浏览器，不读聊天内容，不使用重置券，不切换账号。

## 读取来源

| 面板 | 读谁的登录 | 登录方式 |
| --- | --- | --- |
| Codex | 本机 `codex` | `codex login` |
| Claude | 本机 Claude Code（macOS 钥匙串） | `claude` |
| Grok | 本机 `grok` | `grok login` |
| Gemini | 本机 Antigravity CLI `agy` | `agy` |

Gemini 走 Antigravity CLI，是因为 Google 已不支持个人套餐用 Gemini CLI 登录。

## 安全提示：Claude 与钥匙串

Claude Code 的登录只存在 macOS 钥匙串里。你在 Claude 卡片上点「读取」后，本工具会调用系统自带的 `/usr/bin/security` 读取 `Claude Code-credentials` 条目，macOS 会弹出提示。

- 如果你点「始终允许」，被授权的是 `security` 这个系统工具。此后**本机任何程序**都能通过它读到这份登录，不会再有提示。
- 介意的话请点「允许」（仅一次），代价是每次读取都会再问。也可以事后在“钥匙串访问”里把 `security` 从该条目的访问控制中移除。
- 在你点过「读取」之前，本工具不会碰钥匙串。读到的登录只在内存里，通过环境变量交给 CodexBar 的命令行程序，不写文件、不写日志。

## 写死的显示取舍

下面两条是作者按自己的习惯写死的，没有开关。想改请看 `Sources/QuotaCore/Quota.swift` 里的 `QuotaParser.parse`。

- **Claude** 只显示「5 小时」和「每周」，不显示按模型划分的每周额度。
- **Gemini** 只显示「Gemini · 5 小时」和「Gemini 4 Argon · 每周」，不显示 Antigravity 里的 Claude/GPT 额度池和 Gemini 每周额度。

另外：只显示每家当前登录的那个账号；不包含 ChatGPT 聊天额度。

## 构建

需要 Apple Silicon、macOS 14 及以上、Swift 6 工具链（装 Xcode 即可）。

```sh
zsh scripts/fetch-dependency.sh   # 下载 CodexBar 0.84.0 命令行程序并校验 SHA-256
zsh scripts/test.sh               # 单元测试
zsh scripts/build.sh              # 生成 dist/AI 额度栏.app
open 'dist/AI 额度栏.app'
```

仓库不包含任何二进制文件。构建出的应用是本机临时签名，没有开发者签名和公证，所以只提供源码，不提供安装包。

不想登录也能看界面：

```sh
open 'dist/AI 额度栏.app' --args --demo --show
```

## 使用

- 菜单栏出现 `AI` 图标，鼠标悬停展开，点击固定，`Esc` 关闭，右键可刷新或退出。
- 数字是**剩余**百分比。低于 20% 变橙，低于 10% 变红。
- 默认每 5 分钟刷新，可在齿轮菜单里关掉。
- 读取失败时保留上次的数值并标出来；过了重置时间不会自己变回 100%，要等下一次真实读数。
- 某家登录失效后会停止后台重试，重新登录后点「读取」。

## 代码结构

- `Sources/QuotaCore`：解析 CodexBar 的 JSON 输出。会丢掉账号、邮箱和原始错误正文。
- `Sources/AIQuotaBar`：菜单栏、面板、定时刷新、调用命令行程序。
- `Tests/QuotaCoreTests`：用真实返回的结构做解析测试，包括未知值、越界值和时间边界。

## 许可

MIT，见 [LICENSE](LICENSE)。CodexBar 版权归其作者所有，同为 MIT。

---

## English

A small macOS menu bar app that shows the remaining subscription quota and reset times for Codex, Claude, Grok and Gemini in one compact panel. The interface is in Chinese.

**What it is.** A thin UI on top of the [CodexBar](https://github.com/steipete/CodexBar) CLI (MIT), which does the actual quota lookups. CodexBar is itself a full menu bar app with far more providers; use it if you want more. This project only adds a compact Chinese panel that reads local CLI logins and nothing else.

**Unofficial.** None of these services publishes a quota API. The app reuses each CLI's local login, so it can break whenever a provider changes something. Check the providers' terms yourself; use at your own risk.

**Sources.** Codex: local `codex` login. Claude: Claude Code login in the macOS Keychain. Grok: local `grok` login. Gemini: the Antigravity CLI `agy`, because Google no longer supports Gemini CLI sign-in for personal plans. No browser sessions are read.

**Keychain warning.** For Claude, after you press 读取 the app runs `/usr/bin/security` to read the `Claude Code-credentials` item and macOS asks for permission. Choosing "Always Allow" grants the `security` tool itself, so any local process can read that login afterwards without a prompt. Choose "Allow" (once) if that matters to you. The token stays in memory and is passed to the CodexBar CLI through its environment; it is never written to disk or logs.

**Hard-coded choices.** Claude shows only the 5-hour and weekly windows. Gemini shows only "Gemini 5-hour" and "Gemini 4 Argon weekly". There is no setting; edit `QuotaParser.parse` in `Sources/QuotaCore/Quota.swift`.

**Build.** Apple Silicon, macOS 14+, Swift 6 toolchain.

```sh
zsh scripts/fetch-dependency.sh
zsh scripts/test.sh
zsh scripts/build.sh
open 'dist/AI 额度栏.app'
```

The repository contains no binaries. The built app is ad-hoc signed and not notarized, so only source is provided.

**License.** MIT. CodexBar is copyright its authors, also MIT.
