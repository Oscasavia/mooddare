import 'package:flutter/material.dart';
import 'share_icon.dart';

enum MenuAction { edit, delete, report, block, download, saveDare, hide, share }

/// Shared visual language for overflow actions; the parent keeps its existing
/// permissions, enabled state, confirmations and action handling.
class ActionMenuLabel extends StatelessWidget {
  final MenuAction action;
  final String text;
  final bool enabled;
  const ActionMenuLabel({
    super.key,
    required this.action,
    required this.text,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = !enabled
        ? theme.disabledColor
        : action == MenuAction.delete || action == MenuAction.block
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    final icon = switch (action) {
      MenuAction.edit => Icons.edit_outlined,
      MenuAction.delete => Icons.delete_outline_rounded,
      MenuAction.report => Icons.flag_outlined,
      MenuAction.block => Icons.block_outlined,
      MenuAction.download => Icons.download_outlined,
      MenuAction.saveDare => Icons.bookmark_border_rounded,
      MenuAction.hide => Icons.visibility_off_outlined,
      MenuAction.share => Icons.share_outlined,
    };
    return Row(
      children: [
        ExcludeSemantics(
          child: action == MenuAction.share
              ? ShareIcon(size: 20, color: color)
              : Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
