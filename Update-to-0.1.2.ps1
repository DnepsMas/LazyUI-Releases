# LazyUI 官方 v0.1.1 → v0.1.2 一次性文件升级。
# 保存到旧程序根目录（与 current.json 同级），从托盘退出旧程序后使用 PowerShell 运行。
# 文件和清单按固定 SHA-256 核对；保留旧版本，不访问用户 .lazyui 数据，不启动或停止应用。
param([string]$PackageRoot, [switch]$DryRun)
if ([string]::IsNullOrWhiteSpace($PackageRoot)) { $PackageRoot = $PSScriptRoot }
$ExpectedVersion = '0.1.2'
$ExpectedArchiveSha256 = 'cf8bb13ab8e3687a2cd29f753ce892e41d142d97f7307ddfa79c266f1aa8adcd'
$ExpectedArchiveSize = [long]11948276
$ExpectedReleaseManifestSha256 = '30f8db594e9a2a1b790d836cea1081b40032db38b5cc2d266d9678872612a88d'
$ExpectedOldPackageManifestSha256 = '635ad932bfbd0bd2b77842db8286a1782d4cfbe1d27138ca542f1b3832c864e2'

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $OutputEncoding
$repository = 'DnepsMas/LazyUI-Releases'
$maxBinary = [long]536870912
$maxExpanded = [long]2147483648

function Get-UpdateHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Assert-RegularPath([string]$Path, [switch]$AllowMissing) {
    $item = $null
    try { $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { if ($AllowMissing) { return $false }; throw }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '路径含符号链接或重解析点，停止更新。' }
    return $true
}

function Assert-Contained([string]$Base, [string]$Path) {
    $basePath = [IO.Path]::GetFullPath($Base).TrimEnd('\', '/')
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($basePath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '文件路径越过允许的更新目录。' }
    return $full
}

function Read-UpdateJson([string]$Path, [long]$Limit) {
    $null = Assert-RegularPath $Path
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or $item.Length -le 0 -or $item.Length -gt $Limit) { throw '更新清单大小或类型无效。' }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Assert-NoPackageProcesses([string]$Root) {
    $names = @('lazyui-desktop', 'lazyui-runtime', 'lazyui-update-helper', 'LazyUI', 'Create Desktop Shortcut')
    foreach ($process in @(Get-Process -ErrorAction Stop)) {
        $path = $null
        try { $path = $process.MainModule.FileName }
        catch { if ($process.ProcessName -in $names) { throw '有 LazyUI 进程的路径无法核实。请先退出对应实例，再重试；脚本不会结束任何进程。' }; continue }
        if ([string]::IsNullOrWhiteSpace($path)) {
            if ($process.ProcessName -in $names) { throw '有 LazyUI 进程的路径无法核实。请先退出对应实例，再重试。' }
            continue
        }
        $path = [IO.Path]::GetFullPath($path)
        if ($path.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "旧程序目录仍有进程运行（PID $($process.Id)）。请从托盘退出该目录的 LazyUI，并等待 Desktop、Runtime 和更新助手退出后重试。脚本不会停机或结束进程。"
        }
    }
}

function Assert-Record([string]$Root, $Record) {
    if ($Record.path -cnotmatch '^versions/[0-9A-Za-z._-]+/(lazyui-desktop|lazyui-runtime|lazyui-update-helper)\.exe$' -or
        $Record.sha256 -cnotmatch '^[0-9a-f]{64}$' -or [long]$Record.size_bytes -le 0 -or [long]$Record.size_bytes -gt $maxBinary) { throw '程序文件记录无效。' }
    $path = Assert-Contained $Root (Join-Path $Root ($Record.path -replace '/', '\'))
    $null = Assert-RegularPath $path
    if ((Get-Item -LiteralPath $path).Length -ne [long]$Record.size_bytes -or (Get-UpdateHash $path) -cne $Record.sha256) { throw '程序文件与清单中的大小或 SHA-256 不一致。' }
    return $path
}

function Download-UpdateAsset([string]$Name, [string]$Destination, [long]$Limit) {
    $url = [uri]"https://github.com/$repository/releases/download/v$ExpectedVersion/$Name"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = $null
    for ($redirect = 0; $redirect -le 5; $redirect++) {
        if ($url.Scheme -cne 'https' -or ($url.Host -cne 'github.com' -and $url.Host -cne 'release-assets.githubusercontent.com' -and $url.Host -cne 'objects.githubusercontent.com')) { throw '下载跳转未指向允许的 GitHub HTTPS 资产地址。' }
        $request = [Net.HttpWebRequest]::Create($url)
        $request.AllowAutoRedirect = $false
        $request.Timeout = 180000
        $request.ReadWriteTimeout = 30000
        $request.UserAgent = 'LazyUI-portable-file-update'
        $request.Accept = 'application/octet-stream'
        $response = $request.GetResponse()
        if ([int]$response.StatusCode -in @(301, 302, 303, 307, 308)) {
            $location = $response.Headers['Location']
            $response.Dispose()
            $response = $null
            if ($redirect -eq 5 -or [string]::IsNullOrWhiteSpace($location)) { throw 'GitHub 资产跳转次数越界或缺少目标。' }
            $url = [uri]::new($url, $location)
            continue
        }
        break
    }
    $file = $null
    $stream = $null
    try {
        if (-not $response -or [int]$response.StatusCode -ne 200 -or $response.ContentLength -gt $Limit) { throw 'GitHub 资产响应状态或下载大小无效。' }
        $stream = $response.GetResponseStream()
        $file = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] 65536
        [long]$total = 0
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($total -gt ($Limit - $read)) { throw '下载的更新资产大小越界。' }
            $total += $read
            $file.Write($buffer, 0, $read)
        }
        $file.Flush($true)
    } finally {
        if ($file) { $file.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
    }
    $null = Assert-RegularPath $Destination
    $size = (Get-Item -LiteralPath $Destination).Length
    if ($size -le 0 -or $size -gt $Limit) { throw '下载的更新资产大小越界。' }
}

function Assert-ZipEntries($Entries) {
    if ($Entries.Count -gt 10000) { throw '更新 ZIP 的文件数量过多。' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [long]$total = 0
    foreach ($entry in $Entries) {
        $name = $entry.FullName
        $relative = $name.TrimEnd('/')
        $parts = $relative.Split('/')
        if ([string]::IsNullOrWhiteSpace($relative) -or $name -cmatch '[^\x20-\x7e]' -or
            $name -match '[\\:*?"<>|]' -or $name.StartsWith('/') -or [IO.Path]::IsPathRooted($name) -or
            @($parts | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' -or $_.EndsWith('.') -or $_.EndsWith(' ') -or $_ -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' }).Count -gt 0 -or
            -not $seen.Add($relative)) { throw '更新 ZIP 包含危险路径、非 ASCII 文件名或重复目标。' }
        $kind = ($entry.ExternalAttributes -shr 16) -band 0xf000
        if ($kind -eq 0xa000 -or ($entry.ExternalAttributes -band 0x400) -ne 0) { throw '更新 ZIP 包含符号链接或重解析文件。' }
        [long]$length = $entry.Length
        if ($length -lt 0 -or $length -gt $maxBinary -or $total -gt ($maxExpanded - $length)) { throw '更新 ZIP 解压大小越界。' }
        $total += $length
    }
}

function Assert-Tree([string]$Path) {
    $null = Assert-RegularPath $Path
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($Path)
    [long]$count = 0
    while ($queue.Count -gt 0) {
        foreach ($item in @(Get-ChildItem -LiteralPath $queue.Dequeue() -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '更新文件树包含重解析点。' }
            if (++$count -gt 100000) { throw '程序文件树数量越界。' }
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
        }
    }
}

function Assert-MatchingTree([string]$Source, [string]$Destination) {
    Assert-Tree $Source
    Assert-Tree $Destination
    $sourceItems = @(Get-ChildItem -LiteralPath $Source -Recurse -Force)
    $destinationItems = @(Get-ChildItem -LiteralPath $Destination -Recurse -Force)
    if ($sourceItems.Count -ne $destinationItems.Count) { throw '已有新版本目录的文件集合不同，拒绝覆盖。' }
    foreach ($item in $sourceItems) {
        $relative = $item.FullName.Substring($Source.Length).TrimStart('\')
        $copied = Assert-Contained $Destination (Join-Path $Destination $relative)
        $null = Assert-RegularPath $copied
        $copyItem = Get-Item -LiteralPath $copied -Force
        if ($item.PSIsContainer -ne $copyItem.PSIsContainer -or (-not $item.PSIsContainer -and ($item.Length -ne $copyItem.Length -or (Get-UpdateHash $item.FullName) -cne (Get-UpdateHash $copied)))) { throw '已有新版本目录的文件大小或 SHA-256 不同，拒绝覆盖。' }
    }
}

function Write-AtomicUpdateFile([string]$Path, [byte[]]$Bytes) {
    $null = Assert-Contained $root $Path
    $exists = Assert-RegularPath $Path -AllowMissing
    if ($exists -and (Get-Item -LiteralPath $Path).PSIsContainer) { throw '更新目标是目录，拒绝覆盖。' }
    $temporary = Join-Path $root ('.lazyui-file-update-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $file = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $file.Write($Bytes, 0, $Bytes.Length); $file.Flush($true) } finally { $file.Dispose() }
        if ($exists) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force } }
}

if ($ExpectedVersion -cnotmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$' -or
    $ExpectedArchiveSha256 -cnotmatch '^[0-9a-fA-F]{64}$' -or $ExpectedReleaseManifestSha256 -cnotmatch '^[0-9a-fA-F]{64}$' -or $ExpectedOldPackageManifestSha256 -cnotmatch '^[0-9a-fA-F]{64}$' -or
    $ExpectedArchiveSize -le 0 -or $ExpectedArchiveSize -gt $maxBinary) { throw '必须提供稳定版本、可信清单及 ZIP 的 SHA-256 和精确大小。' }
$ExpectedArchiveSha256 = $ExpectedArchiveSha256.ToLowerInvariant()
$ExpectedReleaseManifestSha256 = $ExpectedReleaseManifestSha256.ToLowerInvariant()
$ExpectedOldPackageManifestSha256 = $ExpectedOldPackageManifestSha256.ToLowerInvariant()
$root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw '旧免安装程序目录不存在。' }
for ($ancestor = $root; $ancestor; $ancestor = [IO.Directory]::GetParent($ancestor)) { $null = Assert-RegularPath ([string]$ancestor) }
$userProfileDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
$userData = [IO.Path]::GetFullPath((Join-Path $userProfileDirectory '.lazyui')).TrimEnd('\', '/')
if ($root.Equals($userData, [StringComparison]::OrdinalIgnoreCase) -or
    $root.StartsWith($userData + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $userData.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '程序目录不能位于用户 .lazyui 数据目录内，也不能包含该数据目录。' }
$currentPath = Join-Path $root 'current.json'
$versionsRoot = Join-Path $root 'versions'
Assert-Tree $versionsRoot
$oldCurrent = Read-UpdateJson $currentPath 4096
if ($oldCurrent.package_format_version -ne 1 -or $oldCurrent.app_version -cnotmatch '^\d+\.\d+\.\d+$' -or
    $oldCurrent.version_directory -cnotmatch '^[0-9A-Za-z][0-9A-Za-z._-]{0,115}-[0-9a-f]{12}$' -or
    $oldCurrent.manifest_sha256 -cnotmatch '^[0-9a-f]{64}$' -or $oldCurrent.pending_update) { throw '旧包版本指针无效或仍有未完成的更新，请先恢复原更新。' }
if ([version]$ExpectedVersion -lt [version]$oldCurrent.app_version) { throw '文件替换更新不接受降级。' }
$oldVersionRoot = Assert-Contained $root (Join-Path (Join-Path $root 'versions') $oldCurrent.version_directory)
$oldManifestPath = Join-Path $oldVersionRoot 'manifest.json'
$oldManifest = Read-UpdateJson $oldManifestPath 65536
if ((Get-UpdateHash $oldManifestPath) -cne $oldCurrent.manifest_sha256 -or $oldManifest.app_version -cne $oldCurrent.app_version -or
    $oldManifest.version_directory -cne $oldCurrent.version_directory -or $oldManifest.package_format_version -ne 1 -or
    $oldManifest.channel -cne 'stable' -or $oldManifest.signature_status -cne 'signed' -or $oldManifest.dirty -ne $false -or
    $oldManifest.target -cne 'x86_64-pc-windows-msvc') { throw '旧目录不是完整的稳定免安装包。' }
if ($oldCurrent.app_version -cne $ExpectedVersion -and $oldCurrent.manifest_sha256 -cne $ExpectedOldPackageManifestSha256) { throw '旧包清单未命中可信来源固定 SHA-256，拒绝覆盖任何程序文件。' }
$oldFiles = @()
foreach ($kind in @('desktop', 'runtime', 'launcher')) { $oldFiles += Assert-Record $root $oldManifest.$kind }
$oldCurrentBytes = [IO.File]::ReadAllBytes($currentPath)
$oldCurrentHash = Get-UpdateHash $currentPath
Assert-NoPackageProcesses $root

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$staging = Join-Path $tempBase ('lazyui-file-update-' + [guid]::NewGuid().ToString('N'))
$lockPath = Join-Path $root '.lazyui-file-update.lock'
$lock = $null
$fileLocks = [Collections.Generic.List[IDisposable]]::new()
$copyTemporary = $null
$pointerSwitched = $false
try {
    New-Item -ItemType Directory -Path $staging | Out-Null
    $zipName = "LazyUI-$ExpectedVersion-windows-x64.zip"
    $zipPath = Join-Path $staging $zipName
    $releasePath = Join-Path $staging 'release-manifest.json'
    Download-UpdateAsset 'release-manifest.json' $releasePath 65536
    if ((Get-UpdateHash $releasePath) -cne $ExpectedReleaseManifestSha256) { throw '发布清单 SHA-256 与可信固定值不一致；没有执行新程序。' }
    Download-UpdateAsset 'release-manifest.json.minisig' (Join-Path $staging 'release-manifest.json.minisig') 4096
    $release = Read-UpdateJson $releasePath 65536
    if ($release.manifest_format_version -ne 1 -or $release.package_format_version -ne 1 -or
        $release.app_version -cne $ExpectedVersion -or $release.channel -cne 'stable' -or $release.signature_status -cne 'signed' -or
        $release.target -cne 'x86_64-pc-windows-msvc' -or $release.dirty -ne $false -or
        $release.archive.name -cne $zipName -or $release.archive.sha256 -cne $ExpectedArchiveSha256 -or
        [long]$release.archive.size_bytes -ne $ExpectedArchiveSize -or $release.package_manifest_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw '固定发布清单的版本、平台、签名状态或 ZIP 记录不匹配。' }
    if ($oldCurrent.app_version -ceq $ExpectedVersion -and $oldCurrent.manifest_sha256 -cne $release.package_manifest_sha256) { throw '当前相同版本未命中固定发布包清单，拒绝覆盖。' }
    Download-UpdateAsset $zipName $zipPath $ExpectedArchiveSize
    if ((Get-Item -LiteralPath $zipPath).Length -ne $ExpectedArchiveSize -or (Get-UpdateHash $zipPath) -cne $ExpectedArchiveSha256) { throw '更新 ZIP 大小或 SHA-256 不匹配；没有执行新程序。' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try { Assert-ZipEntries @($archive.Entries) } finally { $archive.Dispose() }
    $extracted = Join-Path $staging 'package'
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extracted)
    Assert-Tree $extracted
    $newCurrentPath = Join-Path $extracted 'current.json'
    $newCurrent = Read-UpdateJson $newCurrentPath 4096
    if ($newCurrent.package_format_version -ne 1 -or $newCurrent.app_version -cne $ExpectedVersion -or
        $newCurrent.version_directory -cnotmatch '^[0-9A-Za-z][0-9A-Za-z._-]{0,115}-[0-9a-f]{12}$' -or
        $newCurrent.manifest_sha256 -cne $release.package_manifest_sha256 -or $newCurrent.pending_update) { throw '新包版本指针与固定发布清单不一致。' }
    $newVersionRoot = Assert-Contained $extracted (Join-Path (Join-Path $extracted 'versions') $newCurrent.version_directory)
    $newManifestPath = Join-Path $newVersionRoot 'manifest.json'
    $newManifest = Read-UpdateJson $newManifestPath 65536
    if ((Get-UpdateHash $newManifestPath) -cne $release.package_manifest_sha256 -or
        $newManifest.app_version -cne $ExpectedVersion -or $newManifest.version_directory -cne $newCurrent.version_directory -or
        $newManifest.commit -cne $release.commit -or $newManifest.package_format_version -ne 1 -or $newManifest.channel -cne 'stable' -or $newManifest.signature_status -cne 'signed' -or $newManifest.dirty -ne $false -or $newManifest.target -cne 'x86_64-pc-windows-msvc' -or
        $newManifest.schema_version -ne $oldManifest.schema_version -or $newManifest.layout_version -ne $oldManifest.layout_version -or
        $newManifest.protocol.major -ne $oldManifest.protocol.major -or $newManifest.protocol.minor -lt $oldManifest.protocol.minor) { throw '新旧包身份、数据库 schema、layout 或协议不兼容，未替换程序。' }
    $newHelper = Assert-Record $extracted $newManifest.launcher
    foreach ($kind in @('desktop', 'runtime')) { $null = Assert-Record $extracted $newManifest.$kind }
    foreach ($alias in @('LazyUI.exe', 'Create Desktop Shortcut.exe')) {
        $path = Join-Path $extracted $alias
        $null = Assert-RegularPath $path
        if ((Get-Item -LiteralPath $path).Length -ne [long]$newManifest.launcher.size_bytes -or (Get-UpdateHash $path) -cne $newManifest.launcher.sha256) { throw '新包根 EXE 与已固定的更新助手不一致。' }
    }
    $newScript = Join-Path $extracted 'Create Desktop Shortcut.ps1'
    $null = Assert-RegularPath $newScript
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $newHelper
    $info.Arguments = '--verify-package'
    $info.WorkingDirectory = $newVersionRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try { $null = $process.Start(); if (-not $process.WaitForExit(120000)) { throw '签名包验证助手未按时退出；未替换程序。' }; if ($process.ExitCode -ne 0) { throw '新更新助手拒绝包的生产签名或文件布局；未替换程序。' } }
    finally { $process.Dispose() }
    Assert-NoPackageProcesses $root
    $snapshots = @{}
    foreach ($name in @('LazyUI.exe', 'Create Desktop Shortcut.exe', 'Create Desktop Shortcut.ps1')) {
        $path = Join-Path $root $name
        if (Assert-RegularPath $path -AllowMissing) {
            if ((Get-Item -LiteralPath $path).PSIsContainer) { throw '根入口位置是目录，拒绝覆盖。' }
            $hash = Get-UpdateHash $path
            $newHash = Get-UpdateHash (Join-Path $extracted $name)
            if ($name.EndsWith('.exe')) {
                if ($hash -cne $newHash -and ($hash -cne $oldManifest.launcher.sha256 -or (Get-Item -LiteralPath $path).Length -ne [long]$oldManifest.launcher.size_bytes)) { throw '旧目录根 EXE 属于未知文件，拒绝覆盖。' }
            } else {
                $oldScript = Join-Path $oldVersionRoot $name
                if ($hash -cne $newHash -and (-not (Test-Path -LiteralPath $oldScript -PathType Leaf) -or (Get-UpdateHash $oldScript) -cne $hash)) { throw '旧目录根快捷方式脚本属于未知文件，拒绝覆盖。' }
            }
            $snapshots[$name] = $hash
        } else { $snapshots[$name] = $null }
    }
    Write-Output "将仅替换程序文件：$($oldCurrent.app_version) → $ExpectedVersion，目录：$root。用户数据、旧版本和原 CMD 入口均保留。"
    if ($DryRun) { Write-Output 'DryRun 验证完成，未修改旧程序目录。'; return }
    $destination = Assert-Contained $root (Join-Path (Join-Path $root 'versions') $newCurrent.version_directory)
    $destinationExists = Assert-RegularPath $destination -AllowMissing
    if ($destinationExists) { Assert-MatchingTree $newVersionRoot $destination }
    $lockExists = Assert-RegularPath $lockPath -AllowMissing
    if ($lockExists -and [IO.File]::ReadAllText($lockPath) -cne 'LazyUI portable file update v1') { throw '程序目录已有不属于本脚本的更新锁文件。' }
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $lockBytes = [Text.Encoding]::ASCII.GetBytes('LazyUI portable file update v1')
    $lock.SetLength(0); $lock.Write($lockBytes, 0, $lockBytes.Length); $lock.Flush($true)
    Assert-NoPackageProcesses $root
    Assert-Tree (Join-Path $root 'versions')
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'versions') -Recurse -File -Filter '*.exe')) {
        $fileLocks.Add([IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None))
    }
    if ((Get-UpdateHash $currentPath) -cne $oldCurrentHash) { throw '旧版本指针已被其他操作修改，停止替换。' }
    if ($destinationExists) {
        $null = Assert-RegularPath $destination
    } else {
        if (Test-Path -LiteralPath $destination) { throw '新版本目录在更新期间已被其他操作创建，拒绝覆盖。' }
        $copyTemporary = Assert-Contained $root (Join-Path (Join-Path $root 'versions') ('.file-update-' + [guid]::NewGuid().ToString('N')))
        Copy-Item -LiteralPath $newVersionRoot -Destination $copyTemporary -Recurse
        Assert-MatchingTree $newVersionRoot $copyTemporary
        [IO.Directory]::Move($copyTemporary, $destination)
        $copyTemporary = $null
        foreach ($file in @(Get-ChildItem -LiteralPath $destination -Recurse -File -Filter '*.exe')) { $fileLocks.Add([IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)) }
    }
    foreach ($name in @('LazyUI.exe', 'Create Desktop Shortcut.exe', 'Create Desktop Shortcut.ps1')) {
        $path = Join-Path $root $name
        $exists = Assert-RegularPath $path -AllowMissing
        if (($snapshots[$name] -and (-not $exists -or (Get-UpdateHash $path) -cne $snapshots[$name])) -or (-not $snapshots[$name] -and $exists)) { throw '根入口在更新期间已被其他操作修改，停止替换。' }
        Write-AtomicUpdateFile $path ([IO.File]::ReadAllBytes((Join-Path $extracted $name)))
        if ((Get-UpdateHash $path) -cne (Get-UpdateHash (Join-Path $extracted $name))) { throw '根入口写入后 SHA-256 读回不一致。' }
    }
    Assert-NoPackageProcesses $root
    if ((Get-UpdateHash $currentPath) -cne $oldCurrentHash) { throw '旧版本指针已被其他操作修改，未提交新版本。' }
    Write-AtomicUpdateFile $currentPath ([IO.File]::ReadAllBytes($newCurrentPath))
    $pointerSwitched = $true
    if ((Get-UpdateHash $currentPath) -cne (Get-UpdateHash $newCurrentPath)) { throw '版本指针写入后读回不一致。' }
    Write-Output "程序文件已更新为 $ExpectedVersion。未启动应用。现在可以双击目录中的 LazyUI.exe；用户 .lazyui 数据未被读写。"
} catch {
    if ($pointerSwitched) {
        try { Write-AtomicUpdateFile $currentPath $oldCurrentBytes }
        catch { throw '版本指针恢复失败，请保留完整程序目录和旧版本，停止启动并请求人工恢复。' }
    }
    throw "程序文件更新失败：$($_.Exception.Message) 原有用户数据没有修改；请保留旧版本目录，原 CMD 入口仍可选择旧版本。"
} finally {
    foreach ($held in $fileLocks) { $held.Dispose() }
    if ($lock) { $lock.Dispose(); if (Test-Path -LiteralPath $lockPath -PathType Leaf) { Remove-Item -LiteralPath $lockPath -Force } }
    if ($copyTemporary -and (Test-Path -LiteralPath $copyTemporary)) { $safeCopy = Assert-Contained $versionsRoot $copyTemporary; Assert-Tree $safeCopy; Remove-Item -LiteralPath $safeCopy -Recurse -Force }
    if (Test-Path -LiteralPath $staging) { $safeStaging = Assert-Contained $tempBase $staging; Assert-Tree $safeStaging; Remove-Item -LiteralPath $safeStaging -Recurse -Force }
}
