import 'package:flutter/material.dart';
import 'xixi_desktop_device_screen.dart' show XixiDesktopPrimaryButton;

const _ink = Color(0xff222c40);
const _muted = Color(0xff647085);

class XixiDesktopSectionPage extends StatelessWidget {
  final String title;
  final String description;
  final List<Widget> sections;
  const XixiDesktopSectionPage(
      {super.key,
      required this.title,
      required this.description,
      required this.sections});
  @override
  Widget build(BuildContext context) => ColoredBox(
      color: const Color(0xfff6f7fa),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        Text(title,
            style: const TextStyle(
                fontSize: 23, fontWeight: FontWeight.w600, color: _ink)),
        const SizedBox(height: 8),
        Text(description, style: const TextStyle(fontSize: 14, color: _muted)),
        const SizedBox(height: 24),
        for (final section in sections)
          Padding(padding: const EdgeInsets.only(bottom: 18), child: section),
      ]));
}

class XixiDesktopSection extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const XixiDesktopSection(
      {super.key, required this.title, required this.rows});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xffffffff), Color(0xfffcfdff)]),
          border: Border.all(color: const Color(0xffdde2eb)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Color(0x090e254b), blurRadius: 10, offset: Offset(0, 3))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title,
            style: const TextStyle(
                color: _ink, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 32, color: Color(0xffe8ecf3)),
          rows[i],
        ],
      ]));
}

/// Every desktop settings/share row uses the same label, value and action columns.
class XixiDesktopSettingRow extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final bool prominent;
  final Widget? action;
  const XixiDesktopSettingRow(
      {super.key,
      required this.label,
      required this.value,
      this.hint,
      this.prominent = false,
      this.action});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final horizontal = size.maxWidth >= 720 &&
            MediaQuery.textScalerOf(context).scale(14) <= 18;
        final heading = Text(label,
            style: const TextStyle(
                color: _muted, fontSize: 14, fontWeight: FontWeight.w500));
        final content =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(value,
              style: TextStyle(
                  color: _ink,
                  fontSize: prominent ? 24 : 14,
                  fontWeight: prominent ? FontWeight.w600 : FontWeight.w400)),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint!,
                style:
                    const TextStyle(color: _muted, fontSize: 13, height: 1.5))
          ],
        ]);
        final button = SizedBox(width: 218, child: action);
        return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: horizontal
                ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    SizedBox(width: 124, child: heading),
                    Expanded(child: content),
                    const SizedBox(width: 24),
                    button,
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        heading,
                        const SizedBox(height: 10),
                        content,
                        if (action != null) ...[
                          const SizedBox(height: 16),
                          button
                        ],
                      ]));
      });
}

class XixiDesktopAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  const XixiDesktopAction(
      {super.key,
      required this.label,
      required this.icon,
      this.onPressed,
      this.primary = false});
  @override
  Widget build(BuildContext context) => primary
      ? XixiDesktopPrimaryButton(label: label, icon: icon, onPressed: onPressed)
      : OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(218, 46),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          icon: Icon(icon, size: 18),
          label: Text(label));
}
