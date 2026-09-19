import 'package:flutter/material.dart';
import '../domain/photo_processing.dart';

enum _PhotoTool {
  smooth('Smooth', Icons.face_retouching_natural),
  light('Light', Icons.light_mode_outlined),
  warmth('Warmth', Icons.thermostat_outlined);

  final String label;
  final IconData icon;
  const _PhotoTool(this.label, this.icon);
}

/// One adjustment at a time, leaving room for the photo above it.
class PhotoAdjustmentsPanel extends StatefulWidget {
  final PhotoAdjustments settings;
  final bool faceDetected;
  final bool enabled;
  final String? notice;
  final ValueChanged<PhotoAdjustments> onChanged;
  final VoidCallback onReset;

  const PhotoAdjustmentsPanel({
    super.key,
    required this.settings,
    required this.faceDetected,
    required this.enabled,
    required this.onChanged,
    required this.onReset,
    this.notice,
  });

  @override
  State<PhotoAdjustmentsPanel> createState() => _PhotoAdjustmentsPanelState();
}

class _PhotoAdjustmentsPanelState extends State<PhotoAdjustmentsPanel> {
  late _PhotoTool _tool = widget.faceDetected
      ? _PhotoTool.smooth
      : _PhotoTool.light;

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final value = switch (_tool) {
      _PhotoTool.smooth => settings.smoothing,
      _PhotoTool.light => settings.brightness,
      _PhotoTool.warmth => settings.warmth,
    };
    final available = _tool != _PhotoTool.smooth || widget.faceDetected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _PhotoTool.values
                .map(
                  (tool) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      showCheckmark: false,
                      avatar: Icon(tool.icon, size: 18),
                      label: Text(tool.label),
                      selected: _tool == tool,
                      onSelected: widget.enabled
                          ? (_) => setState(() => _tool = tool)
                          : null,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                label: '${_tool.label} ${(value * 100).round()}',
                semanticFormatterCallback: (value) =>
                    '${_tool.label} ${(value * 100).round()}',
                value: value,
                min: _tool == _PhotoTool.smooth ? 0 : -1,
                onChanged: widget.enabled && available
                    ? (value) => widget.onChanged(switch (_tool) {
                        _PhotoTool.smooth => settings.copyWith(
                          smoothing: value,
                        ),
                        _PhotoTool.light => settings.copyWith(
                          brightness: value,
                        ),
                        _PhotoTool.warmth => settings.copyWith(warmth: value),
                      })
                    : null,
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${(value * 100).round()}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            IconButton(
              tooltip: 'Reset adjustments',
              onPressed: widget.enabled ? widget.onReset : null,
              icon: const Icon(Icons.restart_alt, size: 22),
            ),
          ],
        ),
        if (!available && widget.notice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              widget.notice!,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
          ),
      ],
    );
  }
}
