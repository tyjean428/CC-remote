[CmdletBinding()]
param([ValidateSet('Plan','Prepare','Build')][string]$Action='Plan')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$cache=Join-Path $root 'tools/desktop-build'
$source=Join-Path $cache 'source'
$python=(Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$sdk=Join-Path $root 'tools/flutter-sdk'
$compiler='C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.44.35207'
$kit='C:\Program Files (x86)\Windows Kits\10'
$kitVersion='10.0.22621.0'
$cmake='C:\Program Files\CMake\bin\cmake.exe'
if ($Action -eq 'Plan') {
 [ordered]@{product='XiXi Remote Desktop 0.5.4-preview';frontend='Own compiled Flutter desktop product';engine='Pinned bundled native DLL, no upstream client installation';compiler=$compiler;toolchain='Existing MSVC/Windows SDK, manual CMake NMake frontend';source=$source} | ConvertTo-Json
 return
}
if($Action -eq 'Prepare') {
 & (Join-Path $PSScriptRoot 'Extract-Engine.ps1')
 & $python (Join-Path $PSScriptRoot 'prepare_desktop_source.py') --project $root
 if($LASTEXITCODE -ne 0){throw 'Desktop source preparation failed'}
 return
}
if(-not(Test-Path -LiteralPath (Join-Path $source '.xixi-desktop-source.json'))){throw 'Prepare owned source before building'}
foreach($path in @($cmake,(Join-Path $compiler 'bin/HostX64/x64/cl.exe'),(Join-Path $kit "bin/$kitVersion/x64/rc.exe"))){if(-not(Test-Path -LiteralPath $path)){throw ('Existing build tool unavailable: '+$path)}}
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class XiXiDesktopDosPath {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 public static extern uint QueryDosDevice(string device,StringBuilder target,int count);
 public static string Target(string device){var b=new StringBuilder(32768);return QueryDosDevice(device,b,b.Capacity)==0?null:b.ToString();}
}
'@
$alias=$null
foreach($candidate in @('X:','Y:','Z:','W:','V:')){if(-not [XiXiDesktopDosPath]::Target($candidate)){$alias=$candidate;break}}
if(-not $alias){throw 'No free temporary ASCII drive alias'}
$saved=@{};$created=$false
function Run-DesktopTool([string]$Exe,[string[]]$Arguments){ & $Exe @Arguments; if($LASTEXITCODE -ne 0){throw ('Desktop build tool failed ('+$LASTEXITCODE+'): '+$Exe)} }
try {
 Run-DesktopTool (Join-Path $env:WINDIR 'System32/subst.exe') @($alias,$root)
 $created=$true
 if([XiXiDesktopDosPath]::Target($alias) -ine ('\??\'+$root)){throw 'Temporary drive alias does not match project'}
 $ascii=$alias+'/'
 $flutterProject=$ascii+'tools/desktop-build/source/flutter'
 $envs=[ordered]@{
  PATH=((Join-Path $compiler 'bin/HostX64/x64')+';'+(Join-Path $kit "bin/$kitVersion/x64")+';'+$env:PATH)
  INCLUDE=((Join-Path $compiler 'include')+';'+(Join-Path $kit "Include/$kitVersion/ucrt")+';'+(Join-Path $kit "Include/$kitVersion/shared")+';'+(Join-Path $kit "Include/$kitVersion/um")+';'+(Join-Path $kit "Include/$kitVersion/winrt"))
  LIB=((Join-Path $compiler 'lib/x64')+';'+(Join-Path $kit "Lib/$kitVersion/ucrt/x64")+';'+(Join-Path $kit "Lib/$kitVersion/um/x64"))
  PUB_CACHE=($ascii+'tools/bridge-prep/pub-cache')
  APPDATA=($ascii+'tools/desktop-build/profile/AppData/Roaming')
  LOCALAPPDATA=($ascii+'tools/desktop-build/profile/AppData/Local')
  USERPROFILE=($ascii+'tools/desktop-build/profile')
  TEMP=($ascii+'tools/desktop-build/temp');TMP=($ascii+'tools/desktop-build/temp')
  FLUTTER_SUPPRESS_ANALYTICS='true';DART_SUPPRESS_ANALYTICS='true';CI='true'
 }
 foreach($name in $envs.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process');[Environment]::SetEnvironmentVariable($name,$envs[$name],'Process')}
 foreach($path in @($envs.TEMP,$envs.APPDATA,$envs.LOCALAPPDATA)){New-Item -ItemType Directory -Path $path -Force | Out-Null}
 Push-Location $flutterProject
 try {
  Run-DesktopTool ($ascii+'tools/flutter-sdk/bin/flutter.bat') @('--suppress-analytics','config','--enable-windows-desktop','--no-enable-linux-desktop','--no-enable-macos-desktop')
  # Pub resolves first. Existing project-only directory junctions avoid requiring
  # a global Windows Developer Mode change. Retry once after reading its plugin list.
  & ($ascii+'tools/flutter-sdk/bin/flutter.bat') --suppress-analytics pub get
  $pubExit=$LASTEXITCODE
  $plugins=Get-Content -LiteralPath '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
  foreach($platform in @('windows','linux')) {
   $links=Join-Path $flutterProject ($platform+'/flutter/ephemeral/.plugin_symlinks')
   New-Item -ItemType Directory -Path $links -Force | Out-Null
   foreach($plugin in $plugins.plugins.$platform){
    $target=[IO.Path]::GetFullPath([string]$plugin.path)
    if(-not($target.StartsWith([IO.Path]::GetFullPath($envs.PUB_CACHE)+'\',[StringComparison]::OrdinalIgnoreCase) -or $target.StartsWith((Join-Path $root 'tools/bridge-prep/pub-cache')+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'Plugin cache escaped project'}
    $link=Join-Path $links $plugin.name
    if(-not(Test-Path -LiteralPath $link)){New-Item -ItemType Junction -Path $link -Target $target | Out-Null}
   }
  }
  if($pubExit -ne 0){Run-DesktopTool ($ascii+'tools/flutter-sdk/bin/flutter.bat') @('--suppress-analytics','pub','get')}
  Run-DesktopTool ($ascii+'tools/flutter-sdk/bin/cache/dart-sdk/bin/dart.exe') @('analyze','lib/xixi_desktop','lib/xixi')
  $generated=@"
file(TO_CMAKE_PATH "${ascii}tools/flutter-sdk" FLUTTER_ROOT)
file(TO_CMAKE_PATH "$flutterProject" PROJECT_DIR)
set(FLUTTER_VERSION "0.5.4-preview" PARENT_SCOPE)
set(FLUTTER_VERSION_MAJOR 0 PARENT_SCOPE)
set(FLUTTER_VERSION_MINOR 5 PARENT_SCOPE)
set(FLUTTER_VERSION_PATCH 4 PARENT_SCOPE)
set(FLUTTER_VERSION_BUILD 1 PARENT_SCOPE)
list(APPEND FLUTTER_TOOL_ENVIRONMENT
 "FLUTTER_ROOT=${ascii}tools/flutter-sdk"
 "PROJECT_DIR=$flutterProject"
 "FLUTTER_TARGET=lib/main.dart"
 "TREE_SHAKE_ICONS=true"
 "DART_OBFUSCATION=false"
 "TRACK_WIDGET_CREATION=false"
)
"@
  [IO.File]::WriteAllText((Join-Path $flutterProject 'windows/flutter/ephemeral/generated_config.cmake'),$generated,[Text.UTF8Encoding]::new($false))
  # Supply Flutter's ordinary Windows assets/AOT targets. No Visual Studio install
  # discovery or SDK modification is needed with the existing explicit compiler.
  Run-DesktopTool ($ascii+'tools/flutter-sdk/bin/flutter.bat') @('--suppress-analytics','assemble','--no-version-check','--output=build','-dTargetPlatform=windows-x64','-dBuildMode=release','-dTargetFile=lib/main.dart','-dTreeShakeIcons=true','-dDartObfuscation=false','release_bundle_windows-x64_assets')
  # Concurrent mobile builds may occupy the previous DOS alias. CMake's cache
  # contains absolute paths, so regenerate only this owned native build cache.
  Run-DesktopTool $cmake @('--fresh','-S','windows','-B','build/windows-native','-G','NMake Makefiles','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_POLICY_VERSION_MINIMUM=3.5','-DFLUTTER_TARGET_PLATFORM=windows-x64',('-DCMAKE_INSTALL_PREFIX='+$ascii+'tools/desktop-build/bundle'))
  Run-DesktopTool $cmake @('--build','build/windows-native','--config','Release','--target','install')
  Write-Output ('Built independent XiXiRemote.exe and its bundled DLLs in '+$cache+'/bundle')
 } finally {Pop-Location}
} finally {
 foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
 if($created -and [XiXiDesktopDosPath]::Target($alias) -ieq ('\??\'+$root)){ & (Join-Path $env:WINDIR 'System32/subst.exe') $alias /D }
}
