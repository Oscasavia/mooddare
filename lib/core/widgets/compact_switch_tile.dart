import 'package:flutter/material.dart';

/// A smaller visual switch with the full row and original control hit area.
class CompactSwitchTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final bool showSplash;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;
  const CompactSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.contentPadding = EdgeInsets.zero,
    this.showSplash = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: showSplash
          ? theme
          : theme.copyWith(
              splashFactory: NoSplash.splashFactory,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
            ),
      child: MergeSemantics(
        child: ListTile(
          contentPadding: contentPadding,
          title: title,
          subtitle: subtitle,
          enabled: onChanged != null,
          onTap: onChanged == null ? null : () => onChanged!(!value),
          trailing: Transform.scale(
            scale: .8,
            alignment: Alignment.centerRight,
            transformHitTests: false,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              overlayColor: showSplash
                  ? null
                  : const WidgetStatePropertyAll(Colors.transparent),
            ),
          ),
        ),
      ),
    );
  }
}
