# LazyUI 更新与下载

本仓库分发 LazyUI Windows x64 免安装 ZIP，并作为程序内置的固定更新源。

[下载最新版本](https://github.com/DnepsMas/LazyUI-Releases/releases/latest)

从 0.1.2 起，解压完整 ZIP 后双击 `LazyUI.exe`，文件夹可直接作为免安装程序目录使用；不再分发 CMD 启动文件。双击 `Create Desktop Shortcut.exe`，或右键 `Create Desktop Shortcut.ps1` 选择“使用 PowerShell 运行”，即可在桌面创建 LazyUI 快捷方式。移动整个目录后重新执行快捷方式入口。

已有 0.1.1 可以直接在程序的“通用设置”中点击“检查更新”，下载验签后点击“安装并重启”。新版本健康确认后会补齐根目录 EXE 和快捷方式脚本，旧 CMD 兼容入口保留。程序启动也会按六小时间隔检查。

人工隔离测试运行 `LazyUI.exe --launch-isolated-test`，它使用包内隔离数据根；隔离入口禁用在线更新。更新测试请从普通 0.1.1 程序的通用设置执行。

每个稳定版包含免安装 ZIP、`release-manifest.json` 和 `release-manifest.json.minisig`。更新器必须验证生产 minisign 签名及 ZIP、Desktop、Runtime 和 helper 的 SHA-256，并检查版本及数据格式兼容性，才允许安装。公开验签公钥见 [release-public-key.pub](release-public-key.pub)。

Windows Authenticode 证书签名为可选；更新验签始终必需。无 Authenticode 的版本会在发布说明中明确标注，Windows 首次启动可能显示安全提示。

本仓库仅含公开发布资料和产物。客户端读取 Release 不需要 GitHub 登录；签名私钥和发布凭据不会包含在程序内。
