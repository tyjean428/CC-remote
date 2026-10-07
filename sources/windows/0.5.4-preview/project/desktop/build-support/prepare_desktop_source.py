"""Prepare an owned desktop source tree; never install an upstream client."""
import argparse, hashlib, json, subprocess, sys, zipfile
from pathlib import Path

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def replace(path, old, new, expected=1):
    text=path.read_text(encoding='utf-8')
    if text.count(old)!=expected:
        raise ValueError(f'Pinned source anchor differs: {path.name}: {old[:70]}')
    path.write_text(text.replace(old,new),encoding='utf-8',newline='\n')

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--project',required=True)
    args=parser.parse_args(); root=Path(args.project).resolve()
    lock=json.loads((root/'mobile/source.lock.json').read_text(encoding='utf-8-sig'))
    cache=root/'tools/desktop-build'; stage=cache/'source'; marker=stage/'.xixi-desktop-source.json'
    if stage.exists() and not marker.exists(): raise ValueError('Source stage has no ownership marker')
    stage.mkdir(parents=True,exist_ok=True)
    source=root/'upstream/rustdesk-1.5.0'
    for repo,commit,target,name in [
        (source,lock['upstream']['commit'],stage,'fixed-source.zip'),
        (source/'libs/hbb_common',lock['upstream']['hbbCommonCommit'],stage/'libs/hbb_common','fixed-common.zip')]:
        actual=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
        if actual!=commit: raise ValueError('Fixed source commit differs')
        archive=cache/name
        subprocess.run(['git','-C',str(repo),'archive','--format=zip','--output='+str(archive),commit],check=True)
        target.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist():
                if not (target/info.filename).resolve().is_relative_to(target.resolve()): raise ValueError('Unsafe source archive')
            z.extractall(target)
    marker.write_text(json.dumps({'sourceCommit':lock['upstream']['commit'],'version':'0.5.4-preview'}),encoding='utf-8')
    bridge=json.loads((root/'tools/bridge-prep/bridge-generation.json').read_text(encoding='utf-8-sig'))
    for entry in bridge['artifacts']:
        p=source/entry['path']
        if sha(p)!=entry['sha256']: raise ValueError('Generated bridge differs')
        dest=stage/entry['path']; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(p.read_bytes())
    for folder,target in [('mobile/lib','flutter/lib/xixi'),('desktop/lib','flutter/lib/xixi_desktop')]:
        for p in (root/folder).glob('*.dart'):
            dest=stage/target/p.name; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(p.read_bytes())
    sys.path.insert(0,str(root/'mobile/build-support'))
    from public_test_connection import previous_profile_bytes
    from windows_public_profile import current_windows_profile_bytes,previous_windows_public_profile_bytes,previous_windows_ip_profile_bytes
    for name,data in [('XIXI-DEFAULT-CONNECTION.json',current_windows_profile_bytes(root)),('XIXI-PREVIOUS-CONNECTION.json',previous_profile_bytes(root)),('XIXI-PREVIOUS-PUBLIC-CONNECTION.json',previous_windows_public_profile_bytes(root)),('XIXI-PREVIOUS-IP-CONNECTION.json',previous_windows_ip_profile_bytes(root))]:
        (stage/'flutter/assets'/name).write_bytes(data)
    replace(stage/'flutter/lib/desktop/pages/desktop_tab_page.dart',
        "import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../../xixi_desktop/xixi_desktop_home.dart';")
    replace(stage/'flutter/lib/desktop/pages/desktop_tab_page.dart',
        'page: DesktopHomePage(\n          key: const ValueKey(kTabLabelHomePage),\n        )',
        'page: const XixiDesktopHome()')
    replace(stage/'flutter/lib/desktop/pages/desktop_tab_page.dart',
        'onTap: DesktopTabPage.onAddSetting,', 'onTap: () {},')
    # Own settings live inside the product navigation; hide the old global settings tail.
    replace(stage/'flutter/lib/desktop/pages/desktop_tab_page.dart',
        'offstage: bind.isIncomingOnly() || bind.isDisableSettings(),', 'offstage: true,')
    replace(stage/'flutter/lib/desktop/widgets/tabbar_widget.dart', '"RustDesk",', '"西西远程",')
    replace(stage/'flutter/lib/desktop/widgets/tabbar_widget.dart', 'child: loadIcon(16),', 'child: const Icon(Icons.north_east_rounded, size: 16),')
    replace(stage/'flutter/lib/common.dart',
        'final name = bind.mainGetAppNameSync();\n  switch (overrideType ?? kWindowType)',
        "const name = '西西远程';\n  switch (overrideType ?? kWindowType)")
    replace(stage/'flutter/lib/main.dart',
        '  debugPrint("launch args: $args");', '  // Do not log connection arguments or credentials.')
    replace(stage/'flutter/lib/main.dart',
        "import 'dart:async';", "import 'dart:async';\nimport 'xixi_desktop/xixi_desktop_frame.dart';")
    replace(stage/'flutter/lib/main.dart', 'theme: MyTheme.lightTheme,', 'theme: xixiSilverTheme(MyTheme.lightTheme),', expected=2)
    replace(stage/'flutter/lib/main.dart', 'darkTheme: MyTheme.darkTheme,', 'darkTheme: xixiSilverTheme(MyTheme.lightTheme),', expected=2)
    replace(stage/'flutter/lib/main.dart',
        "title: isWeb\n              ? '${bind.mainGetAppNameSync()} Web Client V2 (Preview)'\n              : bind.mainGetAppNameSync(),", "title: '西西远程',")
    replace(stage/'flutter/lib/main.dart',
        '    await restoreWindowPosition(WindowType.Main);',
        '''    await restoreWindowPosition(WindowType.Main);
    // Upgrade the inherited compact window once; later user resizing is preserved.
    if (bind.mainGetLocalOption(key: 'xixi-desktop-workbench-v1') != 'Y') {
      await windowManager.setSize(const Size(1100, 740));
      await windowManager.center();
      await bind.mainSetLocalOption(key: 'xixi-desktop-workbench-v1', value: 'Y');
    }''')
    # Update checks are product-owned; never send users to install an upstream app.
    p=stage/'flutter/lib/main.dart'; text=p.read_text(encoding='utf-8'); text=text.replace('  checkUpdate();','  // Product preview update checks are not enabled.'); p.write_text(text,encoding='utf-8',newline='\n')
    replace(stage/'flutter/lib/xixi/xixi_connection_page.dart',
        'onShowSharing: isAndroid && !bind.isOutgoingOnly()', 'onShowSharing: !bind.isOutgoingOnly()')
    replace(stage/'flutter/lib/xixi/xixi_connection_page.dart',
        "import 'saved_devices.dart';", "import 'saved_devices.dart';\nimport '../xixi_desktop/xixi_desktop_device_screen.dart';")
    replace(stage/'flutter/lib/xixi/xixi_connection_page.dart',
        'return XixiDeviceScreen(', 'return XixiDesktopDeviceScreen(')
    page=stage/'flutter/lib/xixi/xixi_connection_page.dart'
    text=page.read_text(encoding='utf-8')
    start=text.index('    final fillTestServer = await showModalBottomSheet<bool>(')
    end=text.index('    if (!mounted || fillTestServer == null) return;',start)
    text=text[:start]+'''    final fillTestServer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接服务'),
        content: const SizedBox(width: 420, child: Text('西西连接服务已内置。可直接恢复默认服务，或查看高级服务器设置。')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('高级设置')),
          SizedBox(width: 200, child: XixiDesktopPrimaryButton(label: '恢复默认服务', icon: Icons.refresh_rounded,
            onPressed: () => Navigator.pop(context, true))),
        ],
      ),
    );
'''+text[end:]
    page.write_text(text,encoding='utf-8',newline='\n')
    desktop_view=stage/'flutter/lib/xixi_desktop/xixi_desktop_device_screen.dart'
    replace(desktop_view, "../../mobile/lib/", "../xixi/", expected=2)
    replace(stage/'flutter/windows/runner/main.cpp',
        'Win32Window::Size size(800u, 600u);', 'Win32Window::Size size(1100u, 740u);')
    replace(stage/'flutter/windows/CMakeLists.txt','set(BINARY_NAME "rustdesk")','set(BINARY_NAME "XiXiRemote")')
    replace(stage/'flutter/windows/CMakeLists.txt','/wd"4100"','/wd4100')
    replace(stage/'flutter/windows/CMakeLists.txt',
        'set(RUSTDESK_LIB "../../target/${RUSTDESK_LIB_BUILD_TYPE}/librustdesk.dll")',
        'set(RUSTDESK_LIB "${CMAKE_SOURCE_DIR}/../native/librustdesk.dll")')
    replace(stage/'flutter/windows/runner/main.cpp',
        '  // Uri links dispatch', '  app_name = L"西西远程";\n\n  // Uri links dispatch')
    p=stage/'flutter/windows/runner/Runner.rc'; text=p.read_text(encoding='utf-8')
    text=text.replace('"Purslane Tech Pte. Ltd."','"XiXi Remote"').replace('"RustDesk Remote Desktop"','"西西远程"').replace('"rustdesk"','"XiXiRemote"').replace('"rustdesk.exe"','"XiXiRemote.exe"').replace('"RustDesk"','"西西远程"')
    text=text.replace('Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved.','XiXi Remote; upstream components retain their respective licenses.')
    p.write_text(text,encoding='utf-8',newline='\n')
    replace(stage/'flutter/pubspec.yaml','version: 1.5.0+68','version: 0.5.4+1')
    (stage/'flutter/windows/runner/resources/app_icon.ico').write_bytes((root/'desktop/assets/app_icon.ico').read_bytes())
    # Native library is shipped alongside the own runner, not installed separately.
    native=cache/'native/librustdesk.dll'
    if sha(native)!='da4889603c26c6c29fdaa4bb3aec857f9e714e9e795a2c031184bff78fe7c597':raise ValueError('Native library differs')
    target=stage/'flutter/native/librustdesk.dll';target.parent.mkdir(exist_ok=True);target.write_bytes(native.read_bytes())
    record={'version':'0.5.4-preview','nativeLibrarySha256':sha(native),'defaultProfile':json.loads(current_windows_profile_bytes(root)),'ownModules':[],
        'sharedModuleSources':[{'path':p.relative_to(root).as_posix(),'sha256':sha(p)} for p in sorted((root/'mobile/lib').glob('*.dart'))]}
    for folder in ['flutter/lib/xixi','flutter/lib/xixi_desktop']:
        for p in sorted((stage/folder).glob('*.dart')):record['ownModules'].append({'path':p.relative_to(stage).as_posix(),'sha256':sha(p)})
    (cache/'desktop-sources.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Prepared own desktop frontend, runner branding, public defaults and bundled native library.')

if __name__=='__main__':main()
