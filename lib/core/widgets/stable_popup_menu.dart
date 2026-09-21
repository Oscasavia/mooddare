import 'package:flutter/material.dart';

/// Capture the anchor before opening. A selected action may remove the button
/// while the menu's exit animation is still laying out its route.
class StablePopupMenu<T> extends StatelessWidget {
  final String tooltip;
  final bool enabled;
  final Widget? icon;
  final ValueChanged<T> onSelected;
  final PopupMenuItemBuilder<T> itemBuilder;
  const StablePopupMenu({
    super.key,
    required this.tooltip,
    this.enabled = true,
    this.icon,
    required this.onSelected,
    required this.itemBuilder,
  });

  Future<void> _open(BuildContext context) async {
    final anchor = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect =
        anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
    final selected = await showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: itemBuilder(context),
    );
    if (selected != null && context.mounted) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: enabled ? () => _open(context) : null,
    icon: icon ?? const Icon(Icons.more_vert),
  );
}
