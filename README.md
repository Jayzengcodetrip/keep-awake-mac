# ☕ 保持清醒 · KeepAwake for Mac

一个轻量的 macOS 原生菜单栏工具：**单击开启，再点关闭；屏幕可以熄灭，Mac 不因闲置而自动睡眠。**

**当前发布形式：免费源码＋Agent 本机编译安装。暂未提供经过 Apple Developer ID 签名和公证的预编译下载版。** GitHub 的 Download ZIP 下载的是源码，不能直接当作应用双击运行。

## 使用起来是什么样

| 菜单栏状态 | 含义 | 左键单击 |
| --- | --- | --- |
| 带斜杠的杯子＋**关** | 本工具未阻止自动睡眠 | 开启保持清醒 |
| 热咖啡杯＋**开** | 本工具正在防止闲置睡眠 | 关闭保持清醒 |

- 日常开关立即生效，没有 Done／Cancel 二次确认，也不打开终端。
- 右键可查看状态、切换开关、选择登录时打开、退出。
- 首次打开显示简短说明，可收起到菜单栏；重新打开应用或主动查看状态时也可看到窗口。
- 每次启动默认关闭防休眠；“登录时打开”需要用户主动选择，不会自动开启防休眠。
- 不占 Dock，不联网，不收集 Wi-Fi、账号、文件或 Agent 工作内容。

## 适合什么场景

Mac 保持开盖，正常锁屏或息屏，继续运行下载、计算或 Agent 后台任务。底层通过 IOKit 创建 `PreventUserIdleSystemSleep`，防闲置睡眠类型与 `caffeinate -i` 一致。

**不保证合盖后继续运行，也不保证公共 Wi-Fi 永不断线。** 手动睡眠、低电量、公共网络认证过期、网络故障和任务自身错误都可能中断工作。应用也不会锁住网络、续期认证或自动登录公共 Wi-Fi。后台任务仍消耗电量，用完请关闭。

[Apple 对该电源管理接口的说明](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)

## 最简单的安装方式：交给本机 Agent

将下面这段连同仓库链接发给可以在 **Mac 本机读写文件、运行命令** 的 Agent。仅能聊天的网页助手无法直接代为安装。

```text
请检查并安装这个开源 Mac 工具：
https://github.com/Jayzengcodetrip/keep-awake-mac

先阅读 README.md、INSTALL_WITH_AGENT.md 和实际源码、安装脚本，
确认它只实现菜单栏防闲置睡眠，没有与功能无关的操作。
检测我的系统、架构和 Apple 编译工具，按说明本机编译、验证并安装。
缺少工具时明确告诉我需要安装什么；不要关闭系统安全保护。
安装后检查开关和防休眠状态的创建、释放，保留我原有的其他应用。
告诉我安装位置、使用方式和卸载方法，明确哪些项目尚未验证。
```

完整步骤：[Agent 安装指南](INSTALL_WITH_AGENT.md)。

## 手动从源码安装

需要 macOS、可用的 Apple Xcode 或 Command Line Tools、Swift 编译器。本项目已使用 Apple Swift 6.3.3 构建验证，断言测试要求 Swift 6；更早工具链未验证。应用的运行目标是 **macOS 13.0 及以上**；本机构建同时生成 Apple silicon 和 Intel 两个架构。构建工具自身支持的系统版本也需要满足，运行目标不等于所有旧系统都能安装最新编译器。

1. 下载仓库源码 ZIP 并解压，或克隆仓库。
2. 在终端进入解压后的项目文件夹。
3. 检查源码和脚本，再执行：

```sh
zsh scripts/install.zsh
```

默认安装到当前用户的 `~/Applications/保持清醒.app`，无需 `sudo`。安装完成后，在 Finder 的个人 Applications 文件夹双击应用。

如果没有 Apple 编译工具，先通过 Apple 的系统安装界面安装 Command Line Tools：

```sh
xcode-select --install
```

等待系统安装完成后重试。项目脚本不会自动下载安装工具，也不会自动接受系统协议。

安装脚本会检查已存在应用的标识，不覆盖未知的同名应用。更新同一项目时会保留旧版备份；**更新前请先右键退出正在运行的保持清醒**。需要换目标目录时：

```sh
zsh scripts/install.zsh --destination "$HOME/Applications/KeepAwake"
```

本机编译使用临时签名。它不是供别人直接下载的正式签名应用；如系统提示无法验证应用，请先核对源码与构建过程，不要全局关闭 Gatekeeper 或删除安全策略。

## 验证与兼容性

- 已在 Apple silicon 的 macOS 26.5.2 环境编译 universal 应用，验证两个架构、macOS 13 部署目标、签名及临时目录安装。
- 防休眠测试直接向系统创建、查询、释放本工具自己的断言，带有 20 秒系统释放上限，不会停止其他应用的防休眠。
- 菜单栏视觉和真实公共 Wi-Fi 情况需要在使用者自己的环境中验证。不能把编译成功等同于所有 macOS 版本、所有网络都已实测。
- [测试方法](Tests/README.md) · [验证范围](docs/VALIDATION.md)

## 卸载

1. 如果曾启用“登录时打开”，先在工具的右键菜单中取消。
2. 右键选择“退出保持清醒”。这会释放本工具自己的防休眠状态。
3. 将安装目录中的 `保持清醒.app` 移到废纸篓。源码文件夹也可自行删除。
4. 如曾更新，安装目录内 `.keep-awake-backups` 是本工具保存的旧版本，可按需移到废纸篓。

不会更改系统全局睡眠设置，也不会留下独立的 caffeinate 子进程。

## 隐私、许可与维护

[隐私说明](PRIVACY.md) · [MIT 许可证](LICENSE) · [更新记录](CHANGELOG.md)

项目提供源代码与可审阅脚本，不含开发者电脑的运行日志、私人路径、账号密码、私钥或签名证书。公开源码检查：

```sh
python3 scripts/privacy_check.py
```

正式签名版的维护流程预留在 [发布说明](scripts/RELEASING.md)，当前免费源码版不会自动调用签名账号或 Apple 公证服务。

欢迎通过 Issues 反馈；请先移除截图、日志中的 Wi-Fi 名称、账号、路径或其他个人信息。
