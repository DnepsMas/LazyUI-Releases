# LazyUI 更新与下载

本仓库分发 LazyUI Windows x64 免安装 ZIP，并作为程序内置的固定更新源。

[下载最新版本](https://github.com/DnepsMas/LazyUI-Releases/releases/latest)

从 0.1.2 起，解压完整 ZIP 后双击 `LazyUI.exe`，文件夹可直接作为免安装程序目录使用；不再分发 CMD 启动文件。双击 `Create Desktop Shortcut.exe`，或右键 `Create Desktop Shortcut.ps1` 选择“使用 PowerShell 运行”，即可在桌面创建 LazyUI 快捷方式。移动整个目录后重新执行快捷方式入口。

0.1.1 的下载器存在 Windows 路径比较错误，应用内下载更新会失败。升级到 0.1.2 请先从托盘退出旧程序，将 [Update-to-0.1.2.ps1](Update-to-0.1.2.ps1) 保存到旧程序根目录（与 current.json 同级），在该目录打开 PowerShell 并运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Update-to-0.1.2.ps1
```

脚本抓取并核对固定 0.1.2 发布包，替换程序文件，保留用户数据和旧版本文件，并拒绝覆盖运行中的程序。完成后双击 `LazyUI.exe`。0.1.2 已修复下载器，以后可在“通用设置”中检查更新、下载验签、安装并重启。

人工隔离测试运行 `LazyUI.exe --launch-isolated-test`，它使用包内隔离数据根；隔离入口禁用在线更新。本次 0.1.1 → 0.1.2 请使用上述替换脚本测试。自动化已覆盖官方旧包副本和包签名验证；原生 GUI 重启、真实聊天和 Provider 使用仍需人工验收。

每个稳定版包含免安装 ZIP、`release-manifest.json` 和 `release-manifest.json.minisig`。更新器必须验证生产 minisign 签名及 ZIP、Desktop、Runtime 和 helper 的 SHA-256，并检查版本及数据格式兼容性，才允许安装。公开验签公钥见 [release-public-key.pub](release-public-key.pub)。

Windows Authenticode 证书签名为可选；更新验签始终必需。无 Authenticode 的版本会在发布说明中明确标注，Windows 首次启动可能显示安全提示。

本仓库仅含公开发布资料和产物。客户端读取 Release 不需要 GitHub 登录；签名私钥和发布凭据不会包含在程序内。
