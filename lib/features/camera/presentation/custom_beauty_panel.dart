import 'package:flutter/material.dart';
import '../domain/beauty_lens.dart';

/// Floats over the viewfinder; only one adjustment slider is shown at a time.
class CustomBeautyPanel extends StatelessWidget {
  final CustomBeautyLook look;
  final BeautyAdjustment selected;
  final bool enabled, comparing;
  final ValueChanged<BeautyAdjustment> onSelect;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset, onCompare;

  const CustomBeautyPanel({
    super.key,
    required this.look,
    required this.selected,
    required this.enabled,
    required this.comparing,
    required this.onSelect,
    required this.onChanged,
    required this.onReset,
    required this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    final value = look.amount(selected);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final adjustment in BeautyAdjustment.values)
                      Semantics(
                        selected: selected == adjustment,
                        child: TextButton(
                          key: ValueKey('beauty_${adjustment.name}'),
                          onPressed: enabled
                              ? () => onSelect(adjustment)
                              : null,
                          style: TextButton.styleFrom(
                            foregroundColor: selected == adjustment
                                ? Colors.white
                                : Colors.white60,
                            overlayColor: Colors.transparent,
                            splashFactory: NoSplash.splashFactory,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: Text(
                            adjustment.label,
                            style: TextStyle(
                              fontWeight: selected == adjustment
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Reset my look',
              onPressed: enabled && !look.isOriginal ? onReset : null,
              icon: const Icon(Icons.restart_alt_rounded),
              color: Colors.white,
              disabledColor: Colors.white30,
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '${(value * 100).round()}%',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('custom_beauty_slider'),
                value: value,
                label: '${selected.label} ${(value * 100).round()}%',
                semanticFormatterCallback: (amount) =>
                    '${selected.label} ${(amount * 100).round()} percent',
                onChanged: enabled && !comparing ? onChanged : null,
              ),
            ),
            IconButton(
              tooltip: comparing ? 'Show my look' : 'Compare original',
              onPressed: enabled ? onCompare : null,
              icon: const Icon(Icons.compare_rounded),
              style: IconButton.styleFrom(
                foregroundColor: comparing ? Colors.black : Colors.white,
                backgroundColor: comparing ? Colors.white : Colors.transparent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
