[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$cache=Join-Path $root 'tools/desktop-build'
$python=(Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$bundle=Join-Path $cache 'bundle'
if(-not(Test-Path -LiteralPath (Join-Path $bundle 'data/app.so'))){throw 'Independent desktop build is not ready'}
& $python (Join-Path $PSScriptRoot 'package_desktop.py') $root
if($LASTEXITCODE -ne 0){throw 'Desktop product packaging validation failed'}
$release=Join-Path $root ('dist/windows/XiXiRemote-Desktop-0.5.4-preview-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
if(Test-Path -LiteralPath $release){throw 'Release already exists'}
New-Item -ItemType Directory -Path $release | Out-Null
$setup=Join-Path $release 'XiXiRemoteSetup.exe'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /utf8output ('/out:'+$setup) ('/win32manifest:'+(Join-Path $root 'desktop/installer/app.manifest')) ('/win32icon:'+(Join-Path $root 'desktop/assets/app_icon.ico')) ('/resource:'+(Join-Path $cache 'XiXiRemote-Desktop-payload.zip')+',XiXiRemote.Payload') /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll (Join-Path $root 'desktop/installer/XiXiRemoteSetup.cs')
if($LASTEXITCODE -ne 0){throw 'Own single installer compilation failed'}
$test=Start-Process -FilePath $setup -ArgumentList '--self-test' -WindowStyle Hidden -Wait -PassThru
if($test.ExitCode -ne 0){throw 'Installer embedded payload/path self-test failed'}
Copy-Item -LiteralPath (Join-Path $cache 'XiXiRemote-Desktop-source.zip') -Destination (Join-Path $release 'XiXiRemote-source.zip')
Copy-Item -LiteralPath (Join-Path $cache 'package-verification.json') -Destination (Join-Path $release 'verification.json')
$record=[ordered]@{schemaVersion=1;version='0.5.4-preview';installer=$setup;installerSha256=(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant();installerBytes=(Get-Item -LiteralPath $setup).Length;source=(Join-Path $release 'XiXiRemote-source.zip');verification=(Join-Path $release 'verification.json');installerSelfTestPassed=$true;externalRustDeskRequired=$false}
$record|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $root 'runtime/desktop-standalone-package.json') -Encoding utf8
$record|ConvertTo-Json -Depth 4
