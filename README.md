# LazyUI 更新与下载

本仓库分发 LazyUI Windows x64 免安装 ZIP，并作为程序内置的固定更新源。

[下载最新版本](https://github.com/DnepsMas/LazyUI-Releases/releases/latest)

最新稳定版 [v0.1.3](https://github.com/DnepsMas/LazyUI-Releases/releases/tag/v0.1.3) 修复旧版切换后模型配置无法读取、显示 `runtime_build_mismatch` 的问题。新版在启动时接替兼容且空闲的旧 Runtime，保留原有配置和聊天记录。托盘“退出 LazyUI”现在会等待 Runtime 正常关闭，再退出界面；有活动任务时显示原因并保留程序。

从 0.1.2 起，解压完整 ZIP 后双击 `LazyUI.exe`，文件夹可直接作为免安装程序目录使用；不再分发 CMD 启动文件。双击 `Create Desktop Shortcut.exe`，或右键 `Create Desktop Shortcut.ps1` 选择“使用 PowerShell 运行”，即可在桌面创建 LazyUI 快捷方式。移动整个目录后重新执行快捷方式入口。

0.1.2 用户可在“通用设置”中检查更新、下载验签、安装并重启。0.1.1 的下载器存在 Windows 路径比较错误，应用内下载更新会失败；请关闭旧版界面，从上面的最新版本页面下载完整 ZIP，解压到新目录并双击新的 `LazyUI.exe`。普通入口继续读取原有用户配置和聊天数据，新版会处理空闲旧 Runtime 的交接，无需清空数据或手动复制数据库。

历史 [Update-to-0.1.2.ps1](Update-to-0.1.2.ps1) 保留用于固定 0.1.1 → 0.1.2 的替换升级；它不会升级到最新版本。

人工隔离测试运行 `LazyUI.exe --launch-isolated-test`，它使用包内隔离数据根；隔离入口禁用在线更新。自动化已覆盖官方 0.1.1 Runtime 到 0.1.3 的交接、配置和会话保留、最终签名根 EXE 启动链以及包签名验证；原生 GUI 控件、托盘实际点击、真实 Provider 和完整更新故障恢复仍需人工验收。

每个稳定版包含免安装 ZIP、`release-manifest.json` 和 `release-manifest.json.minisig`。更新器必须验证生产 minisign 签名及 ZIP、Desktop、Runtime 和 helper 的 SHA-256，并检查版本及数据格式兼容性，才允许安装。公开验签公钥见 [release-public-key.pub](release-public-key.pub)。

Windows Authenticode 证书签名为可选；更新验签始终必需。无 Authenticode 的版本会在发布说明中明确标注，Windows 首次启动可能显示安全提示。

本仓库仅含公开发布资料和产物。客户端读取 Release 不需要 GitHub 登录；签名私钥和发布凭据不会包含在程序内。
