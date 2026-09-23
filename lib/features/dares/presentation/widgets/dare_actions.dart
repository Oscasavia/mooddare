import 'package:flutter/material.dart';
import 'package:mooddare/features/feed/presentation/screens/camera_screen.dart';
import '../../data/repositories/dare_library_repository.dart';
import '../../data/repositories/dares_repository.dart';

Future<void> openDareCamera(
  BuildContext context,
  DarePrompt prompt, {
  DaresRepository? catalog,
  Widget Function(DarePrompt)? cameraBuilder,
}) async {
  if (!prompt.isValid) throw StateError('This dare is unavailable.');
  if (prompt.moodId != null) {
    final moods = await (catalog ?? DaresRepository()).getCatalog();
    final byId = moods.moods.where((m) => m.id == prompt.moodId);
    // Older bundled moods may have a different ID. Prefer the exact ID when
    // present, so a stale display name cannot override its availability.
    final matches = byId.isNotEmpty
        ? byId
        : moods.moods.where(
            (m) => m.name.toLowerCase() == prompt.moodName?.toLowerCase(),
          );
    if (matches.isEmpty || !matches.first.isAvailable) {
      throw StateError('This mood is not available to try right now.');
    }
  }
  if (!context.mounted) return;
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) =>
          cameraBuilder?.call(prompt) ??
          CameraScreen(
            dareText: prompt.text,
            moodId: prompt.moodId,
            moodName: prompt.moodName,
          ),
    ),
  );
}

void dareMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class TryDareButton extends StatefulWidget {
  final DarePrompt prompt;
  final String label;
  final DaresRepository? catalog;
  final Widget Function(DarePrompt)? cameraBuilder;
  const TryDareButton({
    super.key,
    required this.prompt,
    this.label = 'Try this dare',
    this.catalog,
    this.cameraBuilder,
  });
  @override
  State<TryDareButton> createState() => _TryDareButtonState();
}

class _TryDareButtonState extends State<TryDareButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await openDareCamera(
                context,
                widget.prompt,
                catalog: widget.catalog,
                cameraBuilder: widget.cameraBuilder,
              );
            } catch (e) {
              if (context.mounted) {
                dareMessage(
                  context,
                  e is StateError
                      ? e.message.toString()
                      : 'Could not open this dare. Please try again.',
                );
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
    child: Text(_busy ? 'Opening…' : widget.label),
  );
}

class SaveDareButton extends StatefulWidget {
  final DarePrompt prompt;
  final DareLibraryRepository? repository;
  const SaveDareButton({super.key, required this.prompt, this.repository});
  @override
  State<SaveDareButton> createState() => _SaveDareButtonState();
}

class _SaveDareButtonState extends State<SaveDareButton> {
  late final _repo = widget.repository ?? DareLibraryRepository();
  late Stream<bool> _saved = _repo.isSaved(widget.prompt);
  bool _busy = false;
  @override
  void didUpdateWidget(covariant SaveDareButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prompt.key != widget.prompt.key) {
      _saved = _repo.isSaved(widget.prompt);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _saved,
    builder: (context, snapshot) {
      final saved = snapshot.data == true;
      return IconButton(
        tooltip: saved ? 'Unsave dare' : 'Save dare',
        icon: Icon(
          saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          size: 22,
        ),
        onPressed: _busy || snapshot.hasError || !snapshot.hasData
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  if (saved) {
                    await _repo.unsave(widget.prompt);
                  } else {
                    await _repo.save(widget.prompt);
                  }
                  if (context.mounted && !saved) {
                    dareMessage(context, 'Dare saved to your profile.');
                  }
                } catch (_) {
                  if (context.mounted) {
                    dareMessage(
                      context,
                      'Could not update saved dares. Please try again.',
                    );
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      );
    },
  );
}
