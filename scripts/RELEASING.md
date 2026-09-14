# 构建与正式发布

`build.sh`、`release.sh` 和 `verify-app.sh` 不会覆盖已经安装的应用、启动应用或修改登录项。`install.zsh` 会安装本仓库源码构建的应用；更新前备份同一项目的旧版，带 `--launch` 时会打开应用。应用要求 macOS 13.0 或更新版本，生成的可执行文件同时包含 Apple silicon（arm64）和 Intel（x86_64）。编译成功不等于已经在所有系统版本和两种硬件上完成运行测试。

## 本地构建

使用当前受支持的 Apple Xcode / Command Line Tools，确认 `xcrun swiftc` 可用。构建工具需支持脚本中的 Swift 路径映射选项；建议使用最新稳定版工具链。应用最低运行版本和构建工具版本是两回事。

在仓库根目录运行：

```sh
./scripts/build.sh
./scripts/verify-app.sh --local 'build/local/保持清醒.app'
```

结果位于 `build/local/保持清醒.app`。这是 ad-hoc 签名的本地测试构建，未经 Apple 公证；脚本不会为它生成正式发布 ZIP。不要把本机构建成功当成其他用户下载后能顺利打开的证明。

## 从源码安装

当前公开提供源码和本机安装方式，不把 ad-hoc 预编译应用作为可直接下载的正式版。用户或获得授权的 Agent 审阅源码后，可在仓库根目录运行：

```sh
./scripts/install.zsh
```

脚本先检查 Apple 编译工具，再在本机完成 universal 构建和签名验证，最后安装到 `~/Applications/保持清醒.app`。缺少工具时会说明安装方法并停止，不会自动下载工具。添加 `--launch` 可在安装后打开；省略时不启动应用。添加 `--destination 文件夹` 可改为另一个目标文件夹。

同名但身份不同、损坏或为符号链接的已有应用都不会被覆盖。已有 `org.keepawake.macos` 版本更新前会被备份到目标文件夹下 `.keep-awake-backups/`；脚本不强制退出正在运行的旧版，更新后请退出旧版再打开新版。不使用 `sudo`，不修改登录项。

## 正式下载版

正式分发需要开发者自己准备有效的 **Developer ID Application** 签名身份，并在钥匙串中保存一个 `notarytool` 配置。脚本不注册 Apple 账号，不读取或导出密码，不创建或导出证书，也不自动运行 `store-credentials`。

1. 在本机完成 Apple Developer ID 与钥匙串配置。按照下方 Apple 文档，通过系统工具的安全交互输入认证信息，不把密码写进命令、仓库或聊天。
2. 更新仓库 `Info.plist` 中的 `CFBundleShortVersionString`（如 `1.0.0`）和 `CFBundleVersion`。先完成本地构建和实际运行验证。
3. 仅在准备好向 Apple 上传此构建时，运行下列命令。将占位内容替换为本机的签名身份和已存在的钥匙串配置名称；这两个值不需要提交到仓库。

```sh
KEEP_AWAKE_SIGNING_IDENTITY='Developer ID Application: …' \
KEEP_AWAKE_NOTARY_PROFILE='your-existing-notary-profile' \
./scripts/release.sh
```

脚本不保存这些环境变量。Developer ID 签名需要访问本机钥匙串，并会向 Apple 获取可信时间戳；公证会将编译后的应用上传给 Apple。工具或钥匙串可能要求开发者本人确认。

正式流程依次执行：重新构建 universal 应用；Developer ID 签名、Hardened Runtime 和可信时间戳校验；使用 `notarytool --keychain-profile` 提交并等待明确的 `Accepted`；把票据附到 `.app`；验证票据与 Gatekeeper；重新压缩并解压后再次验证。只有全部通过，才将以下三个文件放进 `dist/KeepAwake-版本号-universal/`：

- `KeepAwake-版本号-universal.zip`
- `SHA256SUMS.txt`
- `release-checks.txt`

同一版本的输出不会被覆盖。任何失败、超时、未接受或无法验证的结果都不会产生该次正式输出；先前版本的有效发布文件仍保留。默认等待公证最长 30 分钟，可通过 `KEEP_AWAKE_NOTARY_TIMEOUT` 调整。超时后 Apple 可能仍在处理，先用本机 `notarytool history --keychain-profile` 检查，再决定是否重试，避免盲目重复提交。脚本会删除临时签名与公证日志；Apple 的历史和公证日志应由维护者在本机查看，不作为公开附件。

可独立复查已经解压的正式应用：

```sh
./scripts/verify-app.sh --release '/path/to/保持清醒.app'
```

还应在另一台 Mac 上从实际下载链接下载 ZIP、解压并首次打开，确认正常的 Gatekeeper 下载确认和菜单栏行为。公证并不保证没有系统确认弹窗，也不等于 Mac App Store 审核。脚本不关闭 Gatekeeper、不移除下载隔离属性，也不建议用户这么做。

## 发布包中的隐私边界

脚本只复制源码构建的可执行文件、通用 `Info.plist` 和可选的仓库 `Resources/AppIcon.icns`。不打包用户名目录、配置缓存、测试日志、Apple ID、钥匙串配置名称或证书导出文件；编译关闭调试信息并映射源码路径，在签名前拒绝常见个人目录路径。公开检查报告只记录版本、平台和各检查是否通过。

**Developer ID 签名本身会公开证书中的开发者姓名或组织名称及 Team ID。** 这是 Apple 可验证发行者身份的一部分，无法在保留有效签名的同时隐藏。密码、私钥、Apple 账号登录信息与此不同，始终不应进入仓库或下载附件。

## Apple 官方文档

- [构建 universal macOS 应用](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)
- [Developer ID 签名](https://developer.apple.com/developer-id/)
- [发布前公证 macOS 软件](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [自定义 notarytool 与 stapler 工作流](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Mac 上的安全打开与 Gatekeeper](https://support.apple.com/en-us/102445)
