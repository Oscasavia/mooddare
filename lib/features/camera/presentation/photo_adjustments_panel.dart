import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late int _page;
  late final PageController _wheel;
  _PhotoTool get _tool => _PhotoTool.values[_page % _PhotoTool.values.length];

  @override
  void initState() {
    super.initState();
    _page = 3000 + (widget.faceDetected ? 0 : 1);
    _wheel = PageController(initialPage: _page, viewportFraction: 1 / 3);
  }

  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  void _select(int page) {
    if (!widget.enabled) return;
    _wheel.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

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
        Semantics(
          liveRegion: true,
          child: Text(
            _tool.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: SizedBox(
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const IgnorePointer(
                    child: SizedBox(
                      width: 66,
                      height: 66,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(color: Colors.white70, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  PageView.builder(
                    key: const ValueKey('photo_adjustment_wheel'),
                    controller: _wheel,
                    physics: widget.enabled
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    onPageChanged: (page) {
                      setState(() => _page = page);
                      HapticFeedback.selectionClick();
                    },
                    itemBuilder: (context, page) {
                      final tool =
                          _PhotoTool.values[page % _PhotoTool.values.length];
                      final selected = page == _page;
                      final available =
                          tool != _PhotoTool.smooth || widget.faceDetected;
                      return Center(
                        child: Semantics(
                          button: true,
                          selected: selected,
                          label: 'Select ${tool.label}',
                          onTap: widget.enabled ? () => _select(page) : null,
                          enabled: widget.enabled,
                          child: Tooltip(
                            message: 'Select ${tool.label}',
                            excludeFromSemantics: true,
                            child: InkResponse(
                              splashFactory: NoSplash.splashFactory,
                              highlightColor: Colors.transparent,
                              excludeFromSemantics: true,
                              onTap: widget.enabled
                                  ? () => _select(page)
                                  : null,
                              radius: 30,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: selected ? 56 : 48,
                                height: selected ? 56 : 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                            .withValues(alpha: .25)
                                      : Colors.white.withValues(alpha: .07),
                                ),
                                child: Icon(
                                  tool.icon,
                                  size: selected ? 26 : 22,
                                  color: !widget.enabled || !available
                                      ? Colors.white38
                                      : selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final slider = Slider(
              label: '${_tool.label} ${(value * 100).round()}',
              semanticFormatterCallback: (value) =>
                  '${_tool.label} ${(value * 100).round()}',
              value: value,
              min: _tool == _PhotoTool.smooth ? 0 : -1,
              onChanged: widget.enabled && available
                  ? (value) => widget.onChanged(switch (_tool) {
                      _PhotoTool.smooth => settings.copyWith(smoothing: value),
                      _PhotoTool.light => settings.copyWith(brightness: value),
                      _PhotoTool.warmth => settings.copyWith(warmth: value),
                    })
                  : null,
            );
            final valueLabel = SizedBox(
              width: 44,
              child: Text(
                '${(value * 100).round()}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            );
            final reset = IconButton(
              tooltip: 'Reset adjustments',
              onPressed: widget.enabled ? widget.onReset : null,
              icon: const Icon(Icons.restart_alt, size: 22),
            );
            if (constraints.maxWidth < 180) {
              return Column(
                children: [
                  slider,
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [valueLabel, reset],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: slider),
                valueLabel,
                reset,
              ],
            );
          },
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
