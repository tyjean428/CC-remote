[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
$moduleRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $moduleRoot
$sourceRoot = Join-Path $projectRoot 'upstream\rustdesk-1.5.0'
$lock = Get-Content -LiteralPath (Join-Path $moduleRoot 'source.lock.json') -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot '.git'))) {
    throw '缺少官方源码。请先将 source.lock.json 中的固定 commit 和子模块获取到 upstream/rustdesk-1.5.0。'
}
$actualCommit = (& git -C $sourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $lock.upstream.commit) { throw '上游源码 commit 与锁定记录不一致。' }
$submoduleRoot = Join-Path $sourceRoot 'libs\hbb_common'
$actualSubmodule = (& git -C $submoduleRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualSubmodule -ne $lock.upstream.hbbCommonCommit) { throw 'hbb_common 子模块不完整或不是锁定 commit。' }

$homePath = Join-Path $sourceRoot 'flutter\lib\mobile\pages\home_page.dart'
$currentHome = [IO.File]::ReadAllText($homePath).Replace("`r`n", "`n")
$originalHome = ((& git -C $sourceRoot show HEAD:flutter/lib/mobile/pages/home_page.dart) -join "`n") + "`n"
if ($LASTEXITCODE -ne 0) { throw '无法读取锁定源码的 mobile 首页。' }
$importAnchor = "import 'connection_page.dart';"
$previousHook = @'
      _pages.add(const bool.fromEnvironment('XIXI_SILVER_HOME', defaultValue: true)
          ? XixiConnectionPage(
              appBarActions: [],
              onShowSharing: () => _showXixiTab(true),
              onOpenSettings: () => _showXixiTab(false),
            )
          : ConnectionPage(appBarActions: []));
'@
$hook = @'
      if (const bool.fromEnvironment('XIXI_SILVER_HOME', defaultValue: true)) {
        _pages.add(XixiConnectionPage(
          appBarActions: [],
          onShowSharing: () => _showXixiTab(true),
          onOpenSettings: () => _showXixiTab(false),
        ));
      } else {
        _pages.add(ConnectionPage(appBarActions: []));
      }
'@
$originalHook = @'
      _pages.add(ConnectionPage(
        appBarActions: [],
      ));
'@
$method = @'
  void _showXixiTab(bool sharing) {
    final index = _pages.indexWhere(
        (page) => sharing ? page is ServerPage : page is SettingsPage);
    if (index >= 0) setState(() => _selectedIndex = index);
  }

'@
if (-not $originalHome.Contains($originalHook)) { throw '原始首页结构不符合已核验版本，停止应用。' }
$legacyExpectedHome = $originalHome.Replace($importAnchor, $importAnchor + "`nimport '../../xixi/xixi_connection_page.dart';")
$legacyExpectedHome = $legacyExpectedHome.Replace($originalHook, $hook)
$legacyExpectedHome = $legacyExpectedHome.Replace('  void initPages() {', $method + "`n  void initPages() {")
$previousExpectedHome = $legacyExpectedHome.Replace($hook, $previousHook)
$expectedHome = $legacyExpectedHome.Replace("import '../../xixi/xixi_connection_page.dart';", "import '../../xixi/xixi_connection_page.dart';`nimport '../../xixi/xixi_sharing_page.dart';")
$expectedHome = $expectedHome.Replace('sharing ? page is ServerPage : page is SettingsPage', 'sharing ? (page is XixiSharingPage || page is ServerPage) : page is SettingsPage')
$sharingHook = @'
      _pages.add(ChatPage(type: ChatPageType.mobileMain));
      if (const bool.fromEnvironment('XIXI_SILVER_HOME', defaultValue: true)) {
        _pages.add(XixiSharingPage(
          appBarActions: const [],
          onOpenSettings: () => _showXixiTab(false),
        ));
      } else {
        _pages.add(ServerPage());
      }
'@
$expectedHome = $expectedHome.Replace('_pages.addAll([ChatPage(type: ChatPageType.mobileMain), ServerPage()]);', $sharingHook.TrimStart())
$expectedHome = $expectedHome.Replace('    return WillPopScope(', @'
    const silver = bool.fromEnvironment('XIXI_SILVER_HOME', defaultValue: true);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final silverSurface = Color(dark ? 0xff202632 : 0xffffffff);
    final silverInk = Color(dark ? 0xfff2f5fc : 0xff222c40);
    final silverMuted = Color(dark ? 0xffadb8cf : 0xff647085);
    final silverAccent = Color(dark ? 0xffaec7ff : 0xff245bea);
    return WillPopScope(
'@)
$expectedHome = $expectedHome.Replace('            centerTitle: true,', @'
            centerTitle: !silver,
            backgroundColor: silver ? silverSurface : null,
            foregroundColor: silver ? silverInk : null,
            elevation: silver ? 0 : null,
            titleTextStyle: silver ? TextStyle(color: silverInk, fontSize: 20, fontWeight: FontWeight.w600) : null,
'@)
$expectedHome = $expectedHome.Replace('            selectedItemColor: MyTheme.accent, //', '            backgroundColor: silver ? silverSurface : null,' + "`n" + '            selectedItemColor: silver ? silverAccent : MyTheme.accent, //')
$expectedHome = $expectedHome.Replace('            unselectedItemColor: MyTheme.darkGray,', '            unselectedItemColor: silver ? silverMuted : MyTheme.darkGray,')
$expectedHome = $expectedHome.Replace('    return Text(bind.mainGetAppNameSync());', @'
    return const bool.fromEnvironment('XIXI_SILVER_HOME', defaultValue: true)
        ? const Text('西西远程')
        : Text(bind.mainGetAppNameSync());
'@)
if ($currentHome -ne $originalHome -and $currentHome -ne $expectedHome -and $currentHome -ne $legacyExpectedHome -and $currentHome -ne $previousExpectedHome) {
    throw 'mobile 首页已有其它修改，请先人工合并；本工具不会覆盖。'
}

$targetRoot = Join-Path $sourceRoot 'flutter\lib\xixi'
$files = @(Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'lib') -Filter '*.dart' -File | Sort-Object Name | ForEach-Object { $_.Name })
if ($files.Count -lt 8 -or $files -notcontains 'xixi_sharing_page.dart' -or $files -notcontains 'xixi_sharing_screen.dart') { throw '缺少银线共享页模块。' }
foreach ($fileName in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot ('lib\' + $fileName)))) { throw "缺少模块文件：$fileName" }
}
if (-not $CheckOnly) {
    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
    foreach ($fileName in $files) {
        Copy-Item -LiteralPath (Join-Path $moduleRoot ('lib\' + $fileName)) -Destination (Join-Path $targetRoot $fileName)
    }
    [IO.File]::WriteAllText($homePath, $expectedHome, (New-Object Text.UTF8Encoding($false)))
    Write-Output '银线手机主入口、设备页与共享页已应用。授权、采集、输入、连接和会话仍调用原生实现。'
}

$bridgeOutputs = @('flutter/lib/generated_bridge.dart', 'flutter/lib/generated_bridge.freezed.dart', 'src/bridge_generated.rs', 'src/bridge_generated.io.rs', 'flutter/macos/Runner/bridge_generated.h', 'flutter/ios/Runner/bridge_generated.h')
$missing = @($bridgeOutputs | Where-Object { -not (Test-Path -LiteralPath (Join-Path $sourceRoot $_)) })
$bridgeVerified = $false
$bridgeRecordPath = Join-Path $projectRoot 'tools\bridge-prep\bridge-generation.json'
if ($missing.Count -eq 0 -and (Test-Path -LiteralPath $bridgeRecordPath)) {
    $record = Get-Content -LiteralPath $bridgeRecordPath -Raw | ConvertFrom-Json
    $bridgeVerified = $record.published -and $record.sourceCommit -eq $actualCommit -and $record.hbbCommonCommit -eq $actualSubmodule -and $record.headerDiagnosticCheck -eq 'No ffigen SEVERE or fatal error diagnostic.' -and @($record.artifacts).Count -eq 6
    foreach ($relative in $bridgeOutputs) {
        $entries = @($record.artifacts | Where-Object { $_.path -eq $relative })
        if ($entries.Count -ne 1 -or (Get-FileHash -LiteralPath (Join-Path $sourceRoot $relative) -Algorithm SHA256).Hash -ine $entries[0].sha256) { $bridgeVerified = $false }
    }
}
[pscustomobject]@{
    SourceCommit = $actualCommit
    SubmoduleCommit = $actualSubmodule
    HomeIntegrated = ($currentHome -eq $expectedHome -or -not $CheckOnly)
    GeneratedBridgeFilesPresent = ($missing.Count -eq 0)
    GeneratedBridgeReady = [bool]$bridgeVerified
    MissingGeneratedFiles = @($missing)
    ApkBuilt = $false
}
