[CmdletBinding()]
param([ValidateSet('Plan', 'Prepare')][string]$Action = 'Plan')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$cacheRoot = Join-Path $projectRoot 'tools\bridge-prep'
$downloadRoot = Join-Path $cacheRoot 'downloads'
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bridge-tools.lock.json') -Raw | ConvertFrom-Json
$sourceLock = Get-Content -LiteralPath (Join-Path $projectRoot 'mobile\source.lock.json') -Raw | ConvertFrom-Json
if ($sourceLock.upstream.commit -ne $lock.sourceCommit -or $sourceLock.bridgeGeneration.flutter -ne $lock.flutter.version -or $sourceLock.bridgeGeneration.flutterRustBridgeCodegen -ne $lock.frb.version) {
    throw 'Source/tool versions differ from the pinned mobile source lock.'
}
$plan = [ordered]@{
    action = $Action; cacheRoot = $cacheRoot; sourceCommit = $lock.sourceCommit
    rust = $lock.rust.version; flutter = $lock.flutter.version; codegen = $lock.frb.version; llvm = $lock.llvm.version
    fixedDownloadBytes = (($lock.rust.components | Measure-Object -Property bytes -Sum).Sum + $lock.frb.bytes + $lock.flutter.dartBytes + $lock.llvm.bytes)
    additionalDownloads = 'Flutter git source, Flutter tool packages, Cargo metadata dependencies and Dart pub dependencies.'
    systemChanges = 'None. No installer, rustup, global PATH, proxy or user-home changes.'
}
if ($Action -eq 'Plan') { $plan | ConvertTo-Json -Depth 5; return }

function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Executable" }
}
function Get-VerifiedDownload([string]$Url, [string]$File, [long]$Bytes, [string]$Sha256, [string]$Md5Base64) {
    $filePath = Join-Path $downloadRoot $File
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        $partial = "$filePath.partial"
        Invoke-Checked (Get-Command curl.exe -ErrorAction Stop).Source @('--fail','--location','--silent','--show-error','--connect-timeout','30','--retry','2','--output',$partial,$Url)
        Move-Item -LiteralPath $partial -Destination $filePath
    }
    if ((Get-Item -LiteralPath $filePath).Length -ne $Bytes) { throw "Size mismatch: $File" }
    if ($Sha256 -and (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash -ine $Sha256) { throw "SHA256 mismatch: $File" }
    if ($Md5Base64) {
        $actualHex = (Get-FileHash -LiteralPath $filePath -Algorithm MD5).Hash
        $expectedHex = [BitConverter]::ToString([Convert]::FromBase64String($Md5Base64)).Replace('-','')
        if ($actualHex -ine $expectedHex) { throw "Official transport MD5 mismatch: $File" }
    }
    return $filePath
}

New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
$tempRoot = Join-Path $cacheRoot 'temp'
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$savedTemp = [Environment]::GetEnvironmentVariable('TEMP','Process')
$savedTmp = [Environment]::GetEnvironmentVariable('TMP','Process')
try {
[Environment]::SetEnvironmentVariable('TEMP',$tempRoot,'Process')
[Environment]::SetEnvironmentVariable('TMP',$tempRoot,'Process')
$tar = (Get-Command tar.exe -ErrorAction Stop).Source
$git = (Get-Command git.exe -ErrorAction Stop).Source
$sevenZip = (Get-Command 7z.exe -ErrorAction Stop).Source
$rustRoot = Join-Path $cacheRoot 'rust-1.75.0'
New-Item -ItemType Directory -Path $rustRoot -Force | Out-Null
foreach ($component in $lock.rust.components) {
    $archive = Get-VerifiedDownload ('https://static.rust-lang.org/dist/2023-12-28/' + $component.file) $component.file $component.bytes $component.sha256 ''
    $extractRoot = Join-Path $cacheRoot ('extract-' + $component.name)
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    Invoke-Checked $tar @('-xf',$archive,'-C',$extractRoot)
    $packageDir = @((Get-ChildItem -LiteralPath $extractRoot -Directory))
    if ($packageDir.Count -ne 1) { throw "Unexpected Rust archive layout: $archive" }
    $payload = Join-Path $packageDir[0].FullName $component.directory
    if (-not (Test-Path -LiteralPath (Join-Path $payload 'manifest.in') -PathType Leaf)) { throw "Missing component manifest: $payload" }
    Get-ChildItem -LiteralPath $payload | Where-Object { $_.Name -ne 'manifest.in' } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $rustRoot -Recurse -Force
    }
    $licenseDir = Join-Path $rustRoot ('licenses\' + $component.name)
    New-Item -ItemType Directory -Path $licenseDir -Force | Out-Null
    Get-ChildItem -LiteralPath $packageDir[0].FullName -File | Where-Object { $_.Name -match 'LICENSE|COPYRIGHT|README' } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $licenseDir -Force
    }
}

$frbArchive = Get-VerifiedDownload $lock.frb.url 'frb-codegen.zip' $lock.frb.bytes $lock.frb.sha256 ''
$frbRoot = Join-Path $cacheRoot 'frb-1.80.1'
New-Item -ItemType Directory -Path $frbRoot -Force | Out-Null
Invoke-Checked $tar @('-xf',$frbArchive,'-C',$frbRoot)
$llvmArchive = Get-VerifiedDownload $lock.llvm.url 'LLVM-14.0.6-win64.exe' $lock.llvm.bytes '' $lock.llvm.md5Base64
$llvmRoot = Join-Path $cacheRoot 'llvm-14.0.6'
New-Item -ItemType Directory -Path $llvmRoot -Force | Out-Null
Invoke-Checked $sevenZip @('x',$llvmArchive,('-o' + $llvmRoot),'-y','bin/libclang.dll','lib/clang/14.0.6/include/*','LICENSE.TXT')
if (-not (Test-Path -LiteralPath (Join-Path $llvmRoot 'bin\libclang.dll') -PathType Leaf)) { throw 'LLVM archive did not yield libclang.dll; installer was not executed.' }
foreach ($license in $lock.licenses) {
    $licensePath = Get-VerifiedDownload $license.url $license.file $license.bytes $license.sha256 ''
    Copy-Item -LiteralPath $licensePath -Destination (Join-Path (Join-Path $cacheRoot $license.directory) $license.file) -Force
}

$flutterRoot = Join-Path $cacheRoot 'flutter-3.22.3'
if (-not (Test-Path -LiteralPath $flutterRoot)) { Invoke-Checked $git @('clone','--depth','1','--branch','3.22.3',$lock.flutter.url,$flutterRoot) }
$head = (& $git -C $flutterRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $lock.flutter.commit) { throw 'Flutter source is not the fixed 3.22.3 commit.' }
$engine = (Get-Content -LiteralPath (Join-Path $flutterRoot 'bin\internal\engine.version') -Raw).Trim()
if ($engine -ne $lock.flutter.engine) { throw 'Flutter engine version mismatch.' }
$dartArchive = Get-VerifiedDownload $lock.flutter.dartUrl 'dart-sdk-3.22.3-windows-x64.zip' $lock.flutter.dartBytes '' $lock.flutter.dartMd5Base64
$flutterCache = Join-Path $flutterRoot 'bin\cache'
New-Item -ItemType Directory -Path $flutterCache -Force | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $flutterCache 'dart-sdk\bin\dart.exe'))) { Invoke-Checked $tar @('-xf',$dartArchive,'-C',$flutterCache) }
[IO.File]::WriteAllText((Join-Path $flutterCache 'engine-dart-sdk.stamp'), $lock.flutter.engine)

$record = [ordered]@{ preparedUtc = [DateTime]::UtcNow.ToString('o'); sourceCommit = $lock.sourceCommit; files = @() }
foreach ($file in @($lock.rust.components.file) + @('frb-codegen.zip','LLVM-14.0.6-win64.exe','dart-sdk-3.22.3-windows-x64.zip')) {
    $itemPath = Join-Path $downloadRoot $file
    $record.files += [ordered]@{ file = $file; bytes = (Get-Item -LiteralPath $itemPath).Length; sha256 = (Get-FileHash -LiteralPath $itemPath -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $cacheRoot 'verified-downloads.json') -Encoding UTF8
Write-Output "Prepared project-local Rust, FRB, libclang and Flutter source/Dart SDK: $cacheRoot"
Write-Output 'No native RustDesk build or Android install was run. Use Generate-Bridge.ps1 for staged generation.'
} finally {
    if ($null -eq $savedTemp) { Remove-Item Env:TEMP -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('TEMP',$savedTemp,'Process') }
    if ($null -eq $savedTmp) { Remove-Item Env:TMP -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('TMP',$savedTmp,'Process') }
}
