[CmdletBinding()]
param(
    [ValidateSet('Plan','Prepare','Diagnose','Verify','Build')][string]$Action = 'Plan',
    [string]$PythonPath = 'python.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$cacheRoot = Join-Path $projectRoot 'tools\mobile-build'
$sourceRoot = Join-Path $cacheRoot 'source'
$upstreamRoot = Join-Path $projectRoot 'upstream\rustdesk-1.5.0'
$lock = Get-Content -LiteralPath (Join-Path $projectRoot 'mobile\source.lock.json') -Raw | ConvertFrom-Json
$androidLock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'android-tools.lock.json') -Raw | ConvertFrom-Json
$previewVersionName=[string]$androidLock.previewVersionName
if ($previewVersionName -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+-preview$') { throw 'previewVersionName must be an explicit numeric preview version in the Android lock.' }
$rawVersionCode=[string]$androidLock.previewVersionCode
if ($rawVersionCode -notmatch '^[1-9][0-9]{0,9}$' -or [long]$rawVersionCode -gt 2100000000) { throw 'previewVersionCode must be a positive Android version code in the lock.' }
$previewVersionCode=[int]$rawVersionCode
$flutterRoot = Join-Path $projectRoot 'tools\flutter-sdk'
$git = (Get-Command git.exe -ErrorAction Stop).Source
$tar = (Get-Command tar.exe -ErrorAction Stop).Source
$head = (& $git -C $upstreamRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $lock.upstream.commit) { throw 'Upstream source differs from the fixed source lock.' }
$commonRoot = Join-Path $upstreamRoot 'libs\hbb_common'
$commonHead = (& $git -C $commonRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commonHead -ne $lock.upstream.hbbCommonCommit) { throw 'hbb_common differs from the fixed source lock.' }
$flutterHead = (& $git -C $flutterRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $flutterHead -ne $lock.flutter.commit) { throw 'Flutter build SDK differs from the pinned 3.24.5 commit.' }
$toolRecordPath = Join-Path $cacheRoot 'android-tools.json'
if ($Action -eq 'Plan') {
    [ordered]@{ applicationId=$androidLock.applicationId; versionName=$previewVersionName; versionCode=$previewVersionCode; label=([string][char]0x897f + [char]0x897f + [char]0x8fdc + [char]0x7a0b); namespace=$androidLock.kotlinNamespace; sourceCommit=$head; flutter=$lock.flutter.version; sourceRoot=$sourceRoot; toolsPrepared=(Test-Path -LiteralPath $toolRecordPath); native='Reuse verified official 1.5.0 Rust/C++ libraries for three ABIs; compile our own Flutter AOT/Kotlin. Static symbol matching is not runtime validation.'; signing='Project-only preview key protected by Windows DPAPI; not production signing'; systemChanges='None. No ADB/device install, remote service changes, global PATH/proxy or Developer Mode changes.' } | ConvertTo-Json -Depth 4
    return
}
$PythonPath = (Get-Command -Name $PythonPath -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw 'Provide an existing Python executable with -PythonPath; no Python installer is run.' }
if (-not (Test-Path -LiteralPath $toolRecordPath -PathType Leaf)) { throw 'Run Prepare-Android.ps1 -Action Prepare first.' }
$toolsRecord = Get-Content -LiteralPath $toolRecordPath -Raw | ConvertFrom-Json
$sdkRoot = $toolsRecord.sdkRoot
$javaRoot = $toolsRecord.javaHome
if (-not $sdkRoot.StartsWith($cacheRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $javaRoot.StartsWith($cacheRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'JDK and writable SDK must remain inside the project mobile-build cache.' }
$integration = & (Join-Path $projectRoot 'mobile\prepare-source.ps1') -CheckOnly
if (-not $integration.HomeIntegrated -or -not $integration.GeneratedBridgeReady) { throw 'The current mobile homepage and bridge integration are not verified; do not build a stale overlay.' }
function Invoke-Checked([string]$Executable,[string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Executable" }
}
$markerPath = Join-Path $sourceRoot '.xixi-preview-source.json'
if (Test-Path -LiteralPath $sourceRoot) {
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'Existing preview source has no ownership marker; refusing to overwrite.' }
    $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    if ($marker.sourceCommit -ne $head -or $marker.commonCommit -ne $commonHead) { throw 'Preview source identity differs from this fixed build.' }
    if ($Action -in @('Diagnose','Verify')) {
        if ($marker.PSObject.Properties.Match('previewVersionName').Count -ne 1 -or $marker.PSObject.Properties.Match('previewVersionCode').Count -ne 1) { throw 'Existing source stage predates the locked version; prepare/build the current frontend before diagnosing or verifying.' }
        if ($marker.previewVersionName -ne $previewVersionName -or $marker.previewVersionCode -ne $previewVersionCode) { throw 'Existing source stage has a different preview version; prepare/build the current frontend first.' }
    }
} else { New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null }
if ($Action -notin @('Diagnose','Verify')) {
$sourceArchive = Join-Path $cacheRoot 'fixed-source.zip'
Invoke-Checked $git @('-C',$upstreamRoot,'archive','--format=zip',('--output=' + $sourceArchive),$head)
Invoke-Checked $tar @('-xf',$sourceArchive,'-C',$sourceRoot)
$commonArchive = Join-Path $cacheRoot 'fixed-common.zip'
Invoke-Checked $git @('-C',$commonRoot,'archive','--format=zip',('--output=' + $commonArchive),$commonHead)
New-Item -ItemType Directory -Path (Join-Path $sourceRoot 'libs\hbb_common') -Force | Out-Null
Invoke-Checked $tar @('-xf',$commonArchive,'-C',(Join-Path $sourceRoot 'libs\hbb_common'))
[ordered]@{ sourceCommit=$head; commonCommit=$commonHead; applicationId=$androidLock.applicationId; previewVersionName=$previewVersionName; previewVersionCode=$previewVersionCode } | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding UTF8
Invoke-Checked $PythonPath @((Join-Path $PSScriptRoot 'prepare_android_source.py'),'--project',$projectRoot,'--source',$sourceRoot)
} elseif (-not (Test-Path -LiteralPath (Join-Path $cacheRoot 'native-reuse.json') -PathType Leaf)) {
    throw 'Diagnose/Verify requires the previously prepared, owned source and native reuse record.'
}

$signingRoot = Join-Path $cacheRoot 'signing'
New-Item -ItemType Directory -Path $signingRoot -Force | Out-Null
$keystore = Join-Path $signingRoot 'xixi-preview.p12'
$protectedPassword = Join-Path $signingRoot 'preview-password.dpapi'
if (Test-Path -LiteralPath $protectedPassword -PathType Leaf) {
    $securePassword = (Get-Content -LiteralPath $protectedPassword -Raw).Trim() | ConvertTo-SecureString
} else {
    if (Test-Path -LiteralPath $keystore) { throw 'Existing signing key has no protected password record; refusing to replace it.' }
    $randomBytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
    $securePassword = ConvertTo-SecureString ([Convert]::ToBase64String($randomBytes)) -AsPlainText -Force
    $securePassword | ConvertFrom-SecureString | Set-Content -LiteralPath $protectedPassword -Encoding UTF8
}
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
$canonicalProjectRoot=$projectRoot
$canonicalCacheRoot=$cacheRoot
$canonicalSourceRoot=$sourceRoot
$savedEnv=@{}
$processEnv=[ordered]@{}
$substDrive=$null
$substCreated=$false
$substExe=(Get-Command subst.exe -ErrorAction Stop).Source
try {
foreach ($tempName in @('TEMP','TMP')) {
    $savedEnv[$tempName]=[Environment]::GetEnvironmentVariable($tempName,'Process')
    [Environment]::SetEnvironmentVariable($tempName,(Join-Path $canonicalCacheRoot 'temp'),'Process')
}
New-Item -ItemType Directory -Path (Join-Path $canonicalCacheRoot 'temp') -Force | Out-Null
if ($projectRoot -match '[^\x00-\x7f]') {
    # Old gen_snapshot/impellerc cannot safely handle this non-ASCII workspace.
    # Query the DOS-device mapping in Unicode, rather than parsing localized CLI output.
    if (-not ('XixiBuildDosDevice' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class XixiBuildDosDevice {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern uint QueryDosDevice(string device, StringBuilder target, int capacity);
}
'@
    }
    function Get-BuildDosTarget([string]$Drive) {
        $buffer=New-Object Text.StringBuilder 4096
        $count=[XixiBuildDosDevice]::QueryDosDevice($Drive,$buffer,$buffer.Capacity)
        if ($count -eq 0) { return $null }
        return $buffer.ToString().Split([char]0)[0]
    }
    $occupied=@([IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0,2).ToUpperInvariant() })
    foreach ($candidate in @('X:','Y:','Z:','W:','V:','U:','T:','S:','R:','Q:','P:')) {
        if ($occupied -contains $candidate) { continue }
        if ($null -ne (Get-BuildDosTarget $candidate)) { continue }
        $substDrive=$candidate
        break
    }
    if (-not $substDrive) { throw 'No unoccupied drive letter is available for the temporary project build alias.' }
    Invoke-Checked $substExe @($substDrive,$canonicalProjectRoot)
    $substCreated=$true
    $expectedDosTarget='\??\' + $canonicalProjectRoot.TrimEnd('\')
    if ((Get-BuildDosTarget $substDrive) -ine $expectedDosTarget) { throw 'Temporary build mapping did not resolve to the expected project root.' }
    function Convert-BuildPath([string]$Path) {
        $full=[IO.Path]::GetFullPath($Path)
        if (-not $full.StartsWith($canonicalProjectRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Build path must stay inside the project.' }
        return $substDrive + $full.Substring($canonicalProjectRoot.Length)
    }
    $projectRoot=$substDrive + '\'
    $cacheRoot=Convert-BuildPath $cacheRoot
    $sourceRoot=Convert-BuildPath $sourceRoot
    $sdkRoot=Convert-BuildPath $sdkRoot
    $javaRoot=Convert-BuildPath $javaRoot
    $flutterRoot=Convert-BuildPath $flutterRoot
    $keystore=Convert-BuildPath $keystore
    Write-Output ('Using temporary ASCII build alias ' + $substDrive + ' for this project; it will be removed in finally.')
}
$processEnv = [ordered]@{
    JAVA_HOME=$javaRoot; ANDROID_HOME=$sdkRoot; ANDROID_SDK_ROOT=$sdkRoot; ANDROID_USER_HOME=(Join-Path $cacheRoot 'android-home')
    # AGP rejects conflicting preference locations. Restore this inherited legacy variable in finally.
    ANDROID_SDK_HOME=$null; ANDROID_PREFS_ROOT=$null
    GRADLE_USER_HOME=(Join-Path $cacheRoot 'gradle-home'); PUB_CACHE=(Join-Path $projectRoot 'tools\bridge-prep\pub-cache'); FLUTTER_ROOT=$flutterRoot
    CARGO_HOME=(Join-Path $projectRoot 'tools\bridge-prep\cargo-home'); RUSTUP_HOME=(Join-Path $projectRoot 'tools\bridge-prep\rustup-home')
    TEMP=(Join-Path $cacheRoot 'temp'); TMP=(Join-Path $cacheRoot 'temp')
    APPDATA=(Join-Path $cacheRoot 'profile\AppData\Roaming'); LOCALAPPDATA=(Join-Path $cacheRoot 'profile\AppData\Local'); USERPROFILE=(Join-Path $cacheRoot 'profile')
    FLUTTER_SUPPRESS_ANALYTICS='true'; DART_SUPPRESS_ANALYTICS='true'; CI='true'
    XIXI_PREVIEW_KEYSTORE=$keystore; XIXI_PREVIEW_STORE_PASSWORD=$password; XIXI_RUSTLS_MAVEN=(Join-Path $cacheRoot 'rustls-maven')
    PATH=((Join-Path $javaRoot 'bin') + ';' + (Join-Path $flutterRoot 'bin') + ';' + (Join-Path $flutterRoot 'bin\cache\dart-sdk\bin') + ';' + $env:PATH)
}
$jvmOptions = '-Duser.home="' + (Join-Path $cacheRoot 'profile').Replace('\','/') + '"'
if ($env:JAVA_TOOL_OPTIONS) { $jvmOptions = $env:JAVA_TOOL_OPTIONS + ' ' + $jvmOptions }
foreach ($scheme in @('http','https')) {
    $proxyValue = [Environment]::GetEnvironmentVariable(($scheme.ToUpperInvariant() + '_PROXY'),'Process')
    if ($proxyValue) {
        $proxyUri = [Uri]$proxyValue
        if ($proxyUri.UserInfo) { throw 'Authenticated proxy requires an explicit supported build configuration; credentials will not be copied into logs or source.' }
        if ($proxyUri.Scheme -ne 'http') { throw 'Only the existing HTTP CONNECT proxy environment is supported by the JDK build process.' }
        $jvmOptions += ' -D' + $scheme + '.proxyHost=' + $proxyUri.Host + ' -D' + $scheme + '.proxyPort=' + $proxyUri.Port
    }
}
$processEnv['JAVA_TOOL_OPTIONS']=$jvmOptions
foreach ($name in $processEnv.Keys) {
    if (-not $savedEnv.ContainsKey($name)) { $savedEnv[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
    if ($null -eq $processEnv[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
    else { [Environment]::SetEnvironmentVariable($name,$processEnv[$name],'Process') }
}
foreach ($path in @($processEnv.ANDROID_USER_HOME,$processEnv.GRADLE_USER_HOME,$processEnv.TEMP,$processEnv.USERPROFILE,$processEnv.APPDATA,$processEnv.LOCALAPPDATA)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $keystore -PathType Leaf)) {
        Invoke-Checked (Join-Path $javaRoot 'bin\keytool.exe') @('-genkeypair','-alias','xixi_preview','-keyalg','RSA','-keysize','3072','-validity','3650','-storetype','PKCS12','-keystore',$keystore,'-storepass:env','XIXI_PREVIEW_STORE_PASSWORD','-keypass:env','XIXI_PREVIEW_STORE_PASSWORD','-dname','CN=Xixi Remote Preview','-noprompt')
    }
    $androidDir=Join-Path $sourceRoot 'flutter\android'
    $localProperties='sdk.dir=' + $sdkRoot.Replace('\','/') + "`nflutter.sdk=" + $flutterRoot.Replace('\','/') + "`nflutter.versionName=" + $previewVersionName + "`nflutter.versionCode=" + $previewVersionCode + "`n"
    [IO.File]::WriteAllText((Join-Path $androidDir 'local.properties'),$localProperties,[Text.UTF8Encoding]::new($false))
    $gradleProperties=Join-Path $androidDir 'gradle.properties'
    if ($Action -notin @('Diagnose','Verify')) { Add-Content -LiteralPath $gradleProperties -Value "`nandroid.overridePathCheck=true`nandroid.builder.sdkDownload=false`n" -Encoding UTF8 }
    Push-Location (Join-Path $sourceRoot 'flutter')
    try {
        if ($Action -notin @('Diagnose','Verify')) {
        Invoke-Checked (Join-Path $flutterRoot 'bin\flutter.bat') @('--suppress-analytics','config','--no-enable-windows-desktop','--no-enable-macos-desktop','--no-enable-linux-desktop')
        Invoke-Checked (Join-Path $flutterRoot 'bin\flutter.bat') @('--suppress-analytics','pub','get')
        Invoke-Checked (Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dart.exe') @('analyze','lib/xixi','lib/generated_bridge.dart','lib/generated_bridge.freezed.dart')
        }
        if ($Action -eq 'Diagnose') {
            Push-Location $androidDir
            try { Invoke-Checked (Join-Path $androidDir 'gradlew.bat') @(':app:packageRelease','-x',':app:compileFlutterBuildRelease','--stacktrace','--no-daemon','--console=plain','-Ptarget-platform=android-arm,android-arm64,android-x64') } finally { Pop-Location }
        } elseif ($Action -in @('Build','Verify')) {
            if ($Action -eq 'Build') {
                Invoke-Checked (Join-Path $flutterRoot 'bin\flutter.bat') @('--suppress-analytics','build','apk','--release','--no-pub','--target-platform','android-arm,android-arm64,android-x64','--build-name',$previewVersionName,'--build-number',([string]$previewVersionCode))
                $apk=Join-Path $sourceRoot 'flutter\build\app\outputs\flutter-apk\app-release.apk'
            } else { $apk=Join-Path $sourceRoot 'flutter\build\app\outputs\apk\release\app-release.apk' }
            if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw 'Build returned without the expected APK.' }
            Invoke-Checked $PythonPath @((Join-Path $PSScriptRoot 'verify_android_preview.py'),'--project',$projectRoot,'--apk',$apk)
            Copy-Item -LiteralPath $apk -Destination (Join-Path $cacheRoot 'xixi-remote-preview.apk') -Force
            [ordered]@{ verifiedUtc=[DateTime]::UtcNow.ToString('o'); sourceCommit=$head; applicationId=$androidLock.applicationId; versionName=$previewVersionName; versionCode=$previewVersionCode; apkSha256=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant(); apkBytes=(Get-Item -LiteralPath $apk).Length; nativeReuse='Verified official Rust/C++ libraries, no native Rust rebuild'; verificationAction=$Action; installed=$false; remoteSessionVerified=$false } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $cacheRoot 'preview-build.json') -Encoding UTF8
            Write-Output ('Built project-local preview APK: ' + (Join-Path $canonicalCacheRoot 'xixi-remote-preview.apk'))
        } else { Write-Output 'Preview source, JNI libraries, isolated signing and pub dependencies prepared. No APK install was run.' }
    } finally { Pop-Location }
} finally {
    foreach ($name in $savedEnv.Keys) {
        if ($null -eq $savedEnv[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name,$savedEnv[$name],'Process') }
    }
    $password=$null
    $securePassword.Dispose()
    if ($substCreated) {
        $expectedDosTarget='\??\' + $canonicalProjectRoot.TrimEnd('\')
        if ((Get-BuildDosTarget $substDrive) -ieq $expectedDosTarget) {
            & $substExe $substDrive '/D'
            if ($LASTEXITCODE -ne 0) { Write-Warning ('Could not remove the owned temporary build mapping: ' + $substDrive) }
        } else { Write-Warning ('Temporary mapping no longer belongs to this project; leaving it untouched: ' + $substDrive) }
    }
}
