import 'package:flutter/material.dart';

ThemeData xixiSilverTheme(ThemeData base) => base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xfff6f7fa),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff245bea)),
      dialogTheme: const DialogTheme(
          backgroundColor: Color(0xffffffff),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)))),
      popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xffffffff), surfaceTintColor: Colors.transparent),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xff245bea),
              backgroundColor: const Color(0xfffcfdff),
              side: const BorderSide(color: Color(0xffdde2eb)),
              minimumSize: const Size(64, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11)))),
    );

class XixiDesktopFrame extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  final Widget body;
  const XixiDesktopFrame(
      {super.key,
      required this.selected,
      required this.onSelected,
      required this.body});

  @override
  Widget build(BuildContext context) => Theme(
        data: xixiSilverTheme(Theme.of(context)),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final destinations = const [
            (Icons.devices_rounded, '设备'),
            (Icons.screen_share_outlined, '本机共享'),
            (Icons.tune_rounded, '设置'),
          ];
          return Scaffold(
            body: Column(children: [
              Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xffffffff), Color(0xfff7f9fd)]),
                      border:
                          Border(bottom: BorderSide(color: Color(0xffdde2eb)))),
                  child: Row(children: [
                    Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xff3874ff), Color(0xff174bd2)]),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x25245bea),
                                  blurRadius: 12,
                                  offset: Offset(0, 4))
                            ]),
                        child: const Icon(Icons.north_east_rounded,
                            color: Colors.white, size: 19)),
                    const SizedBox(width: 13),
                    const Text('西西远程',
                        style: TextStyle(
                            color: Color(0xff222c40),
                            fontWeight: FontWeight.w600,
                            fontSize: 17)),
                    if (wide) ...[
                      const SizedBox(width: 15),
                      const Text('远程控制',
                          style:
                              TextStyle(color: Color(0xff647085), fontSize: 12))
                    ],
                  ])),
              Expanded(
                  child: Row(children: [
                Container(
                    width: wide ? 164 : 64,
                    decoration: const BoxDecoration(
                        color: Color(0xfffafbfe),
                        border: Border(
                            right: BorderSide(color: Color(0xffdde2eb)))),
                    padding: EdgeInsets.fromLTRB(
                        wide ? 12 : 8, 20, wide ? 12 : 8, 20),
                    child: Column(children: [
                      for (var i = 0; i < destinations.length; i++)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Tooltip(
                                message: destinations[i].$2,
                                child: Material(
                                    color: i == selected
                                        ? const Color(0xffe9efff)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(11),
                                    child: InkWell(
                                        key: Key('desktop-nav-$i'),
                                        borderRadius: BorderRadius.circular(11),
                                        onTap: () => onSelected(i),
                                        child: Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: wide ? 12 : 13,
                                                vertical: 12),
                                            child: Row(children: [
                                              Icon(destinations[i].$1,
                                                  size: 21,
                                                  color: i == selected
                                                      ? const Color(0xff245bea)
                                                      : const Color(
                                                          0xff647085)),
                                              if (wide) ...[
                                                const SizedBox(width: 10),
                                                Flexible(
                                                    child: Text(
                                                        destinations[i].$2,
                                                        style: TextStyle(
                                                            color: i == selected
                                                                ? const Color(
                                                                    0xff245bea)
                                                                : const Color(
                                                                    0xff647085),
                                                            fontSize: 13,
                                                            fontWeight: i ==
                                                                    selected
                                                                ? FontWeight
                                                                    .w600
                                                                : FontWeight
                                                                    .w400)))
                                              ]
                                            ])))))),
                      const Spacer(),
                      if (wide)
                        const Text('西西远程 · 功能预览',
                            style: TextStyle(
                                color: Color(0xff8793a9), fontSize: 11)),
                    ])),
                Expanded(child: body),
              ])),
            ]),
          );
        }),
      );
}
