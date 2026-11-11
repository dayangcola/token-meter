# 安全说明 / Security

本工具会读取本机 CLI 的登录凭据（包括 macOS 钥匙串里的 Claude Code 登录），所以安全问题请认真对待。

## 报告漏洞

请不要在公开的 issue 里贴漏洞细节。请使用 GitHub 的私密漏洞报告：仓库页面 → Security → Report a vulnerability。这是个人项目，我会尽量在一周内回复，但不作保证。

报告或提 issue 时，**不要粘贴**任何令牌、cookie、`auth.json`、钥匙串内容或带账号邮箱的原始输出。

## 设计上的已知取舍

- Claude 的登录通过 `/usr/bin/security` 从钥匙串读取。在钥匙串提示里点「始终允许」会让本机任何程序都能经由 `security` 读到它。
- 读到的 Claude 登录通过环境变量交给 CodexBar 的命令行程序。运行的几秒内，本机同一用户下的其他进程可以看到该进程的环境变量。
- 额度查询由第三方程序 CodexBar 完成。构建脚本固定版本并校验其压缩包的 SHA-256，但它的行为不在本项目控制范围内。

---

To report a vulnerability, use GitHub's private reporting (Security → Report a vulnerability) rather than a public issue. Never paste tokens, cookies, `auth.json`, Keychain contents or raw output containing account emails. This is a personal project; replies are best-effort.
