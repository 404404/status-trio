# GitHub Actions 发布

本 fork 的默认发布模式是 **GitHub Release only**：macOS runner 使用 Xcode 16.4 / Swift 6.1.2 构建通用 `arm64 + x86_64` 应用，上传 DMG 和 SHA-256 文件到 [404404/status-trio Releases](https://github.com/404404/status-trio/releases)。默认不会生成、签名或发布 Sparkle appcast，也不会把上游更新源写入应用。

## 预检

在 Actions 页面运行 **Build and Release macOS**，指定：

- `version=1.1.0`
- `build=5`
- `publish=false`
- `publish_appcast=false`

成功的预检会运行 `swift test`，再构建 Universal DMG，并把 DMG、校验文件和 `release.env` 作为 Actions artifact 上传。GitHub runner 没有可用的无线硬件，因此这不能替代 Wi-Fi 或蓝牙真机测试。

## 正式 GitHub Release

预检通过并且待发布提交已在 `main` 后，手动运行同一工作流：

- `version` 和 `build`：显式递增；不能覆盖既有 tag 或 Release。
- `publish=true`
- `publish_appcast=false`
- `release_notes`：英文说明，每行一个项目。
- `release_notes_zh`：中文说明，每行一个项目。

Release notes 会使用 `# Version X.Y.Z （English + 中文， 中文在下方）` 标题，英文在前、中文在后，并附带首次启动命令。发布脚本会拒绝复用已有 tag，并以本次构建的 commit SHA 创建 tag。

DMG 是 Ad-hoc 签名，除非仓库额外配置 Developer ID 证书和公证凭据。`codesign --verify` 通过不等同于 Gatekeeper 或 Apple 公证通过。首次手动安装时，如 macOS 阻止启动：

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

不要全局关闭 Gatekeeper；只在从本 fork Release 下载且 SHA-256 与发布文件匹配时执行上述命令。

## 未来启用 Sparkle（可选）

只有在本 fork 拥有一对匹配的 Sparkle EdDSA 密钥后，才设置：

- repository secret `SPARKLE_PRIVATE_KEY`
- repository variable `SPARKLE_PUBLIC_KEY`
- 可匿名读取的、属于本 fork 的 HTTPS `appcast.xml` 和 Release 下载地址

然后使用 `publish_appcast=true`。工作流会验证两项配置、签名 DMG、写入 appcast，并将对应 feed/public key 写入该构建的 app。缺少任何一项时工作流会失败；不得使用上游私钥、公钥或 appcast。

## 可选 Developer ID 和公证

如有凭据，可配置 `DEVELOPER_ID_CERTIFICATE_P12`、`DEVELOPER_ID_CERTIFICATE_PASSWORD`、`APPSTORE_CONNECT_API_KEY_ID`、`APPSTORE_CONNECT_API_ISSUER_ID` 与 `APPSTORE_CONNECT_API_PRIVATE_KEY`。没有这些凭据时，发布仍可完成，但必须标为 Ad-hoc 签名且未公证。
