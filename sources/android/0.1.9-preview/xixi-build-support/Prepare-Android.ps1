[CmdletBinding()]
param(
    [ValidateSet('Plan','Prepare')][string]$Action = 'Plan',
    [string]$SourceSdkPath = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Android\Sdk')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$cacheRoot = Join-Path $projectRoot 'tools\mobile-build'
$sdkRoot = Join-Path $cacheRoot 'sdk'
$downloads = Join-Path $cacheRoot 'downloads'
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'android-tools.lock.json') -Raw | ConvertFrom-Json
$sourceSdk = [IO.Path]::GetFullPath($SourceSdkPath)
foreach ($relative in @('build-tools\36.0.0\aapt2.exe','platform-tools\adb.exe','licenses\android-sdk-license','platforms\android-34\android.jar')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceSdk $relative) -PathType Leaf)) { throw ('Read-only source SDK is missing: ' + $relative) }
}
if ($sourceSdk.StartsWith($cacheRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'SourceSdkPath must be an existing SDK outside our destination cache.' }
if ($Action -eq 'Plan') {
    $pluginDownloadBytes=($lock.pluginPlatforms | Measure-Object -Property bytes -Sum).Sum
    [ordered]@{ cacheRoot=$cacheRoot; sourceSdk=$sourceSdk; sdkRoot=$sdkRoot; fixedDownloadBytes=($lock.jdk.bytes+$lock.platform.bytes+$pluginDownloadBytes); jdk=$lock.jdk.version; sdkApi=$lock.platform.api; pluginSdkApis=@($lock.pluginPlatforms.api)+@(34); sourceSdkAccess='Read-only copy of build-tools 36.0.0, API34, platform-tools and existing licenses'; extraDownloads='Gradle 8.11.1, Flutter Android artifacts and Maven dependencies during the build. No Rust native build, NDK or vcpkg planned.' } | ConvertTo-Json -Depth 4
    return
}
function Invoke-Checked([string]$Executable,[string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Executable" }
}
function Get-Archive([string]$File,[string]$Url,[long]$Bytes,[string]$Algorithm,[string]$Hash) {
    $path = Join-Path $downloads $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $partial = "$path.partial"
        Invoke-Checked (Get-Command curl.exe -ErrorAction Stop).Source @('--fail','--location','--silent','--show-error','--connect-timeout','30','--retry','2','--output',$partial,$Url)
        Move-Item -LiteralPath $partial -Destination $path
    }
    if ((Get-Item -LiteralPath $path).Length -ne $Bytes -or (Get-FileHash -LiteralPath $path -Algorithm $Algorithm).Hash -ine $Hash) { throw "Archive verification failed: $File" }
    return $path
}
New-Item -ItemType Directory -Path $downloads,$sdkRoot,(Join-Path $cacheRoot 'temp') -Force | Out-Null
$savedTemp = [Environment]::GetEnvironmentVariable('TEMP','Process')
$savedTmp = [Environment]::GetEnvironmentVariable('TMP','Process')
try {
    [Environment]::SetEnvironmentVariable('TEMP',(Join-Path $cacheRoot 'temp'),'Process')
    [Environment]::SetEnvironmentVariable('TMP',(Join-Path $cacheRoot 'temp'),'Process')
    $tar = (Get-Command tar.exe -ErrorAction Stop).Source
    $jdkArchive = Get-Archive $lock.jdk.file $lock.jdk.url $lock.jdk.bytes 'SHA256' $lock.jdk.sha256
    $jdkRoot = Join-Path $cacheRoot 'jdk'
    New-Item -ItemType Directory -Path $jdkRoot -Force | Out-Null
    Invoke-Checked $tar @('-xf',$jdkArchive,'-C',$jdkRoot)
    $jdkCandidates = @(Get-ChildItem -LiteralPath $jdkRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe') })
    if ($jdkCandidates.Count -ne 1) { throw 'Unexpected JDK archive layout.' }
    $platformRecords=@()
    foreach ($platform in @($lock.platform)+@($lock.pluginPlatforms)) {
        $platformArchive = Get-Archive $platform.file $platform.url $platform.bytes 'SHA1' $platform.sha1
        $platformStage = Join-Path $cacheRoot ('platform-' + $platform.api + '-extract')
        New-Item -ItemType Directory -Path $platformStage -Force | Out-Null
        Invoke-Checked $tar @('-xf',$platformArchive,'-C',$platformStage)
        $platformCandidates = @(Get-ChildItem -LiteralPath $platformStage -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'android.jar') })
        if ($platformCandidates.Count -ne 1) { throw 'Unexpected Android platform archive layout.' }
        $platformDestination = Join-Path $sdkRoot ('platforms\android-' + $platform.api)
        New-Item -ItemType Directory -Path $platformDestination -Force | Out-Null
        Get-ChildItem -LiteralPath $platformCandidates[0].FullName | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $platformDestination -Recurse -Force }
        $platformRecords += [ordered]@{api=$platform.api; officialSha1=$platform.sha1; localSha256=(Get-FileHash -LiteralPath $platformArchive -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    foreach ($relative in @('build-tools\36.0.0','platforms\android-34','platform-tools','licenses')) {
        $destination = Join-Path $sdkRoot $relative
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $sourceSdk $relative) | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force }
    }
    [ordered]@{ preparedUtc=[DateTime]::UtcNow.ToString('o'); javaHome=$jdkCandidates[0].FullName; sdkRoot=$sdkRoot; sourceSdkReadOnly=$sourceSdk; applicationId=$lock.applicationId; jdkSha256=$lock.jdk.sha256; platforms=$platformRecords; copiedPlatform34='Read-only existing Android SDK' } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $cacheRoot 'android-tools.json') -Encoding UTF8
    Write-Output "Prepared project-local JDK17 and Android SDK36: $cacheRoot"
    Write-Output 'No SDK installer, ADB command, device install, NDK, Rust native build or system setting change was run.'
} finally {
    if ($null -eq $savedTemp) { Remove-Item Env:TEMP -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('TEMP',$savedTemp,'Process') }
    if ($null -eq $savedTmp) { Remove-Item Env:TMP -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('TMP',$savedTmp,'Process') }
}
