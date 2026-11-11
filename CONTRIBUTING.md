# 参与贡献

这是一个个人项目：作者按自己的使用需要更新，不保证响应时间，也不保证接受所有改动。欢迎提 issue 和 PR，但请先了解下面几点。

## 适合提的

- 某一家读不到数、读数与官方页面不一致、界面显示错误。
- CodexBar 升级后输出格式变化导致的解析问题。
- 文档错误。

## 不太会做的

- 增加更多平台。需要更多平台请直接使用 [CodexBar](https://github.com/steipete/CodexBar)。
- 读取浏览器会话或 cookie。本项目只读本机 CLI 的登录。
- 把写死的显示取舍做成设置项（见 README）。

## 提 issue

请写明 macOS 版本、是哪一家、卡片上显示的那句话。**不要粘贴**令牌、cookie、钥匙串内容或带账号邮箱的原始输出。

## 提 PR

```sh
zsh scripts/fetch-dependency.sh
zsh scripts/test.sh
zsh scripts/build.sh
```

- 解析逻辑的改动请在 `Tests/QuotaCoreTests` 里加用例，测试数据用虚构数字，不要用真实账号的读数。
- 不要提交二进制、`dist/`、`vendor/CodexBar/`。
- 代码和文档以 MIT 许可证贡献。
