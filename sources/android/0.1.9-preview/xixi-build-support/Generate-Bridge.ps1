[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Generate')][string]$Action = 'Plan',
    [switch]$Publish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Publish -and $Action -ne 'Generate') { throw '-Publish requires -Action Generate.' }
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$cacheRoot = Join-Path $projectRoot 'tools\bridge-prep'
$sourceRoot = Join-Path $projectRoot 'upstream\rustdesk-1.5.0'
$stageRoot = Join-Path $cacheRoot 'source-fixed'
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bridge-tools.lock.json') -Raw | ConvertFrom-Json
$sourceLock = Get-Content -LiteralPath (Join-Path $projectRoot 'mobile\source.lock.json') -Raw | ConvertFrom-Json
$git = (Get-Command git.exe -ErrorAction Stop).Source
$tar = (Get-Command tar.exe -ErrorAction Stop).Source
$head = (& $git -C $sourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $lock.sourceCommit -or $head -ne $sourceLock.upstream.commit) { throw 'Main source commit differs from the fixed source lock.' }
$commonRoot = Join-Path $sourceRoot 'libs\hbb_common'
$commonHead = (& $git -C $commonRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commonHead -ne $lock.hbbCommonCommit) { throw 'hbb_common differs from the fixed submodule commit.' }
if ($sourceLock.bridgeGeneration.flutter -ne $lock.flutter.version -or $sourceLock.bridgeGeneration.rust -ne '1.75' -or $sourceLock.bridgeGeneration.flutterRustBridgeCodegen -ne $lock.frb.version) { throw 'Bridge generation versions differ from mobile/source.lock.json.' }
$rustRoot = Join-Path $cacheRoot 'rust-1.75.0'
$flutterRoot = Join-Path $cacheRoot 'flutter-3.22.3'
$frb = Join-Path $cacheRoot 'frb-1.80.1\flutter_rust_bridge_codegen.exe'
$llvmRoot = Join-Path $cacheRoot 'llvm-14.0.6'
$required = @(
    (Join-Path $rustRoot 'bin\cargo.exe'), (Join-Path $rustRoot 'bin\rustc.exe'), (Join-Path $rustRoot 'bin\rustfmt.exe'),
    (Join-Path $flutterRoot 'bin\flutter.bat'), (Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dart.exe'),
    $frb, (Join-Path $llvmRoot 'bin\libclang.dll'), (Join-Path $cacheRoot 'verified-downloads.json')
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
$outputs = @('src/bridge_generated.rs','src/bridge_generated.io.rs','flutter/lib/generated_bridge.dart','flutter/lib/generated_bridge.freezed.dart','flutter/macos/Runner/bridge_generated.h','flutter/ios/Runner/bridge_generated.h')
$previousRecordPath = Join-Path $cacheRoot 'bridge-generation.json'
$previousRecord = $null
if (Test-Path -LiteralPath $previousRecordPath -PathType Leaf) {
    $previousRecord = Get-Content -LiteralPath $previousRecordPath -Raw | ConvertFrom-Json
    if ($previousRecord.sourceCommit -ne $head -or $previousRecord.hbbCommonCommit -ne $commonHead) { throw 'Existing generation record belongs to another source identity.' }
}
if ($Action -eq 'Plan') {
    [ordered]@{ sourceCommit = $head; commonCommit = $commonHead; stageRoot = $stageRoot; missingTools = $missing; outputs = $outputs; publish = [bool]$Publish; scope = 'Generate in a fixed source copy. Only the six bridge artifacts may be published; no homepage or functional source changes.' } | ConvertTo-Json -Depth 5
    return
}
if ($missing.Count -gt 0) { throw ('Missing project-local bridge tools: ' + ($missing -join ', ')) }
$clangInclude = Join-Path $llvmRoot 'lib\clang\14.0.6\include'
$vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vsWhere -PathType Leaf)) { throw 'Existing Visual Studio C headers are required; this script does not install them.' }
$vsRoot = (& $vsWhere -latest -products '*' -property installationPath).Trim()
if ($LASTEXITCODE -ne 0 -or -not $vsRoot) { throw 'Cannot locate an existing Visual Studio installation.' }
$vcVersions = @(Get-ChildItem -LiteralPath (Join-Path $vsRoot 'VC\Tools\MSVC') -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'include\vcruntime.h') -PathType Leaf } | Sort-Object Name -Descending)
$sdkVersions = @(Get-ChildItem -LiteralPath (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Include') -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'ucrt\stdlib.h') -PathType Leaf } | Sort-Object Name -Descending)
if ($vcVersions.Count -eq 0 -or $sdkVersions.Count -eq 0) { throw 'Existing MSVC/UCRT standard headers are missing.' }
$vcInclude = Join-Path $vcVersions[0].FullName 'include'
$ucrtInclude = Join-Path $sdkVersions[0].FullName 'ucrt'
foreach ($header in @((Join-Path $clangInclude 'stdbool.h'),(Join-Path $vcInclude 'vcruntime.h'),(Join-Path $ucrtInclude 'stdlib.h'))) {
    if (-not (Test-Path -LiteralPath $header -PathType Leaf)) { throw ('Missing C standard header: ' + $header) }
}
$compilerOpts = '-I "' + $clangInclude.Replace('\','/') + '" -I "' + $vcInclude.Replace('\','/') + '" -I "' + $ucrtInclude.Replace('\','/') + '"'
$flutterHead = (& $git -C $flutterRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $flutterHead -ne $lock.flutter.commit) { throw 'Flutter tool source differs from fixed 3.22.3 commit.' }
$verified = Get-Content -LiteralPath (Join-Path $cacheRoot 'verified-downloads.json') -Raw | ConvertFrom-Json
if ($verified.sourceCommit -ne $head) { throw 'Tool verification record is for another source commit.' }
foreach ($entry in $verified.files) {
    $archivePath = Join-Path (Join-Path $cacheRoot 'downloads') $entry.file
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ine $entry.sha256) { throw ('Cached tool archive changed: ' + $entry.file) }
}

function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Executable" }
}
if (Test-Path -LiteralPath $stageRoot) {
    $existingMarker = Join-Path $stageRoot '.xixi-bridge-source.json'
    if (-not (Test-Path -LiteralPath $existingMarker -PathType Leaf)) { throw 'Existing source staging directory has no ownership marker; refusing to overwrite.' }
    $existing = Get-Content -LiteralPath $existingMarker -Raw | ConvertFrom-Json
    if ($existing.sourceCommit -ne $head -or $existing.hbbCommonCommit -ne $commonHead) { throw 'Existing staging directory has a different source identity.' }
} else {
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    $sourceArchive = Join-Path $cacheRoot 'rustdesk-fixed-source.zip'
    Invoke-Checked $git @('-C',$sourceRoot,'archive','--format=zip',('--output=' + $sourceArchive),$head)
    Invoke-Checked $tar @('-xf',$sourceArchive,'-C',$stageRoot)
    $commonArchive = Join-Path $cacheRoot 'hbb-common-fixed-source.zip'
    Invoke-Checked $git @('-C',$commonRoot,'archive','--format=zip',('--output=' + $commonArchive),$commonHead)
    New-Item -ItemType Directory -Path (Join-Path $stageRoot 'libs\hbb_common') -Force | Out-Null
    Invoke-Checked $tar @('-xf',$commonArchive,'-C',(Join-Path $stageRoot 'libs\hbb_common'))
    [ordered]@{ sourceCommit = $head; hbbCommonCommit = $commonHead } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stageRoot '.xixi-bridge-source.json') -Encoding UTF8
}
$pubspecPath = Join-Path $stageRoot 'flutter\pubspec.yaml'
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
if ($pubspec.Contains('extended_text: 14.0.0')) {
    [IO.File]::WriteAllText($pubspecPath,$pubspec.Replace('extended_text: 14.0.0','extended_text: 13.0.0'),[Text.UTF8Encoding]::new($false))
} elseif (-not $pubspec.Contains('extended_text: 13.0.0')) { throw 'Unexpected extended_text dependency; cannot reproduce the fixed official bridge workflow.' }

$processEnv = [ordered]@{
    CARGO_HOME = (Join-Path $cacheRoot 'cargo-home'); RUSTUP_HOME = (Join-Path $cacheRoot 'rustup-home')
    CARGO_TARGET_DIR = (Join-Path $cacheRoot 'target'); PUB_CACHE = (Join-Path $cacheRoot 'pub-cache')
    TEMP = (Join-Path $cacheRoot 'temp'); TMP = (Join-Path $cacheRoot 'temp')
    APPDATA = (Join-Path $cacheRoot 'profile\AppData\Roaming'); LOCALAPPDATA = (Join-Path $cacheRoot 'profile\AppData\Local')
    USERPROFILE = (Join-Path $cacheRoot 'profile')
    FLUTTER_SUPPRESS_ANALYTICS = 'true'; DART_SUPPRESS_ANALYTICS = 'true'; CI = 'true'
    FLUTTER_ROOT = $flutterRoot; PUB_ENVIRONMENT = 'flutter_cli:bridge_codegen'
    RUST_LOG = 'info'
    LIBCLANG_PATH = (Join-Path $llvmRoot 'bin'); CARGO_NET_GIT_FETCH_WITH_CLI = 'true'
    PATH = ((Join-Path $rustRoot 'bin') + ';' + (Join-Path $flutterRoot 'bin') + ';' + (Join-Path $flutterRoot 'bin\cache\dart-sdk\bin') + ';' + $env:PATH)
}
$savedEnv = @{}
try {
foreach ($name in $processEnv.Keys) {
    $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
    [Environment]::SetEnvironmentVariable($name,$processEnv[$name],'Process')
}
foreach ($path in @($processEnv.CARGO_HOME,$processEnv.RUSTUP_HOME,$processEnv.CARGO_TARGET_DIR,$processEnv.PUB_CACHE,$processEnv.TEMP,$processEnv.APPDATA,$processEnv.LOCALAPPDATA,$processEnv.USERPROFILE)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    $rustVersion = (& (Join-Path $rustRoot 'bin\rustc.exe') --version).Trim()
    if ($LASTEXITCODE -ne 0 -or $rustVersion -notmatch '^rustc 1\.75\.0 ') { throw 'Rust compiler version mismatch.' }
    $frbVersion = (& $frb --version).Trim()
    if ($LASTEXITCODE -ne 0 -or $frbVersion -notmatch '1\.80\.1$') { throw 'FRB codegen version mismatch.' }
    Invoke-Checked (Join-Path $flutterRoot 'bin\flutter.bat') @('--suppress-analytics','precache','--universal','--no-android','--no-ios','--no-web','--no-linux','--no-windows','--no-macos','--no-fuchsia')
    Push-Location (Join-Path $stageRoot 'flutter')
    try { Invoke-Checked (Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dart.exe') @('pub','--suppress-analytics','get') } finally { Pop-Location }
    Push-Location $stageRoot
    try {
        $codegenLog = Join-Path $cacheRoot 'codegen-output.log'
        $frbArgs = @('--rust-input','./src/flutter_ffi.rs','--dart-output','./flutter/lib/generated_bridge.dart','--c-output','./flutter/macos/Runner/bridge_generated.h','--llvm-path',$llvmRoot,('--llvm-compiler-opts=' + $compilerOpts),'--skip-add-mod-to-lib')
        & $frb @frbArgs 2>&1 | Tee-Object -FilePath $codegenLog
        if ($LASTEXITCODE -ne 0) { throw "FRB codegen failed ($LASTEXITCODE); inspect $codegenLog" }
        if (Select-String -LiteralPath $codegenLog -Pattern '\[SEVERE\]|fatal error:' -Quiet) { throw 'ffigen emitted a severe header diagnostic; generated output will not be published.' }
        Push-Location (Join-Path $stageRoot 'flutter')
        try { Invoke-Checked (Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dart.exe') @('analyze','lib/generated_bridge.dart','lib/generated_bridge.freezed.dart') } finally { Pop-Location }
        Copy-Item -LiteralPath (Join-Path $stageRoot 'flutter\macos\Runner\bridge_generated.h') -Destination (Join-Path $stageRoot 'flutter\ios\Runner\bridge_generated.h') -Force
    } finally { Pop-Location }
    $record = [ordered]@{
        generatedUtc = [DateTime]::UtcNow.ToString('o'); sourceCommit = $head; hbbCommonCommit = $commonHead
        flutterCommit = $flutterHead; flutterVersion = $lock.flutter.version; rustVersion = $rustVersion; codegenVersion = $frbVersion
        preparation = 'Official Windows codegen with UUID enabled by its default features; official CI extended_text downgrade in staging only. No Rust native build. cargo-expand is not invoked by this codegen.'
        workflowSha256 = (Get-FileHash -LiteralPath (Join-Path $stageRoot '.github\workflows\bridge.yml') -Algorithm SHA256).Hash.ToLowerInvariant()
        cargoLockSha256 = (Get-FileHash -LiteralPath (Join-Path $stageRoot 'Cargo.lock') -Algorithm SHA256).Hash.ToLowerInvariant()
        pubLockSha256 = (Get-FileHash -LiteralPath (Join-Path $stageRoot 'flutter\pubspec.lock') -Algorithm SHA256).Hash.ToLowerInvariant()
        headerDiagnosticCheck = 'No ffigen SEVERE or fatal error diagnostic.'
        dartAnalysis = 'dart analyze lib/generated_bridge.dart lib/generated_bridge.freezed.dart: exit 0'
        cHeaders = @{ llvm = $clangInclude; msvc = $vcInclude; ucrt = $ucrtInclude }
        artifacts = @(); published = [bool]$Publish
    }
    foreach ($relative in $outputs) {
        $artifact = Join-Path $stageRoot $relative
        if (-not (Test-Path -LiteralPath $artifact -PathType Leaf) -or (Get-Item -LiteralPath $artifact).Length -eq 0) { throw "Missing or empty generated artifact: $relative" }
        $record.artifacts += [ordered]@{ path = $relative; bytes = (Get-Item -LiteralPath $artifact).Length; sha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    if ($Publish) {
        foreach ($entry in $record.artifacts) {
            $destination = Join-Path $sourceRoot $entry.path
            if ((Test-Path -LiteralPath $destination) -and (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ine $entry.sha256) {
                $previous = @()
                if ($previousRecord -and $previousRecord.published) { $previous = @($previousRecord.artifacts | Where-Object { $_.path -eq $entry.path }) }
                if ($previous.Count -ne 1 -or (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ine $previous[0].sha256) { throw "Existing bridge artifact is not an unchanged artifact from our previous generation; refusing to replace: $destination" }
            }
        }
        foreach ($entry in $record.artifacts) { Copy-Item -LiteralPath (Join-Path $stageRoot $entry.path) -Destination (Join-Path $sourceRoot $entry.path) -Force }
    }
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $cacheRoot 'bridge-generation.json') -Encoding UTF8
    Write-Output ('Generated all six bridge artifacts: ' + $stageRoot)
    if ($Publish) { Write-Output ('Published only the six bridge artifacts to: ' + $sourceRoot) }
} finally {
    foreach ($name in $savedEnv.Keys) {
        if ($null -eq $savedEnv[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name,$savedEnv[$name],'Process') }
    }
}
