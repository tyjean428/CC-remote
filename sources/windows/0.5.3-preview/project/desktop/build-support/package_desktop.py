import hashlib,json,shutil,sys,zipfile,datetime,os
from pathlib import Path

root=Path(sys.argv[1]).resolve();cache=root/'tools/desktop-build';bundle=cache/'bundle';stage=cache/'source'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
if sha(bundle/'librustdesk.dll')!='da4889603c26c6c29fdaa4bb3aec857f9e714e9e795a2c031184bff78fe7c597':raise ValueError('Native library differs')
native=json.loads((cache/'native/.xixi-engine.json').read_text(encoding='utf-8-sig'))
for name in ['dylib_virtual_display.dll','printer_driver_adapter.dll','WindowInjection.dll']:
    entry=next(e for e in native['files'] if e['path']==name)
    src=cache/'native'/name
    if sha(src)!=entry['sha256']:raise ValueError('Auxiliary native library differs')
    shutil.copy2(src,bundle/name)
redist=Path('C:/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/VC/Redist/MSVC/14.44.35112/x64/Microsoft.VC143.CRT')
for p in redist.glob('*.dll'):shutil.copy2(p,bundle/p.name)
if (bundle/'rustdesk.exe').exists():raise ValueError('Upstream executable must not be the product entry point')
if sha(bundle/'data/app.so')==sha(cache/'native/data/app.so'):raise ValueError('Frontend must be newly compiled, not copied from upstream')
from windows_public_profile import current_windows_profile_bytes,previous_windows_public_profile_bytes
public=json.loads(current_windows_profile_bytes(root))
sources=json.loads((cache/'desktop-sources.json').read_text(encoding='utf-8'))
if sources['version']!='0.5.3-preview' or sources['defaultProfile']!=public:raise ValueError('Prepared desktop release contract differs')
for entry in sources['ownModules']:
    if sha(stage/entry['path'])!=entry['sha256']:raise ValueError('Staged product module changed after preparation')
for entry in sources['sharedModuleSources']:
    if sha(root/entry['path'])!=entry['sha256']:raise ValueError('Shared product source changed after staging; prepare and build again')
asset=bundle/'data/flutter_assets/assets/XIXI-DEFAULT-CONNECTION.json'
if json.loads(asset.read_text(encoding='utf-8'))!=public:raise ValueError('Compiled default profile differs')
previous_asset=bundle/'data/flutter_assets/assets/XIXI-PREVIOUS-PUBLIC-CONNECTION.json'
if json.loads(previous_asset.read_text(encoding='utf-8'))!=json.loads(previous_windows_public_profile_bytes(root)):raise ValueError('Compiled previous public profile differs')
for p in (root/'desktop/lib').glob('*.dart'):
    expected=p.read_text(encoding='utf-8').replace('../../mobile/lib/','../xixi/')
    if expected!=(stage/'flutter/lib/xixi_desktop'/p.name).read_text(encoding='utf-8'):raise ValueError('Desktop source changed after staging')
shutil.copy2(root/'mobile/LICENCE',bundle/'LICENSE-AGPL-3.0.txt')
shutil.copy2(root/'THIRD-PARTY-NOTICES.md',bundle/'THIRD-PARTY-NOTICES.md')
(bundle/'使用说明.txt').write_text('西西远程 0.5.3-preview\n\n安装一次，打开西西远程，输入对方设备 ID，点连接。服务器和引擎已内置。\n被控手机需按系统提示开启屏幕共享和输入权限。接入仍需密码或本机接受。\n本版电脑共享需保持程序运行。重启、登录屏幕、跨网络、长时间后台仍需专项联测。\n无需单独安装 RustDesk。开源引擎来源及许可见随包说明；对应源码 ZIP 随包提供。\n',encoding='utf-8')
source_zip=cache/'XiXiRemote-Desktop-source.zip'
excluded={'build','.dart_tool','.git','ephemeral','.plugin_symlinks','native'}
with zipfile.ZipFile(source_zip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for directory,dirs,names in os.walk(stage,topdown=True,followlinks=False):
        dirs[:]=[name for name in dirs if name not in excluded and not (Path(directory)/name).lstat().st_file_attributes & 0x400]
        for name in sorted(names):
            p=Path(directory)/name;rel=p.relative_to(stage)
            if name not in {'local.properties','key.properties','.flutter-plugins','.flutter-plugins-dependencies'} and not p.is_symlink():
                z.write(p,'source/'+rel.as_posix())
    for prefix in ['desktop','mobile/lib','mobile/test','mobile/build-support']:
        for p in sorted((root/prefix).rglob('*')):
            rel=p.relative_to(root)
            if p.is_file() and '__pycache__' not in p.parts and p.suffix not in {'.pyc','.p12','.dpapi'}:
                z.write(p,'project/'+rel.as_posix())
    for name in ['mobile/source.lock.json','mobile/pubspec.yaml','mobile/pubspec.lock','mobile/LICENCE','THIRD-PARTY-NOTICES.md','docs/standalone-client-target.md']:
        z.write(root/name,'project/'+name)
shutil.copy2(source_zip,bundle/'XiXiRemote-source.zip')
files=[]
for p in sorted(bundle.rglob('*')):
    if p.is_file() and p.name!='product-manifest.json':files.append({'path':p.relative_to(bundle).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
manifest={'schemaVersion':1,'product':'XiXiRemote','version':'0.5.3-preview','entryPoint':'XiXiRemote.exe','files':files}
(bundle/'product-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
payload=cache/'XiXiRemote-Desktop-payload.zip'
with zipfile.ZipFile(payload,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(bundle.rglob('*')):
        if p.is_file():z.write(p,p.relative_to(bundle).as_posix())
record={'version':'0.5.3-preview','createdAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'defaultProfile':public,'payloadSha256':sha(payload),'payloadBytes':payload.stat().st_size,'sourceSha256':sha(source_zip),'sourceBytes':source_zip.stat().st_size,'fileCount':len(files),'bundledNativeSha256':sha(bundle/'librustdesk.dll'),'ownAotSha256':sha(bundle/'data/app.so'),'upstreamAotReused':False,'upstreamExecutableRequired':False}
(cache/'package-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(record,ensure_ascii=False))
