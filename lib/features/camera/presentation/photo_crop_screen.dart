import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../domain/photo_crop.dart';

class PhotoCropScreen extends StatefulWidget {
  final Uint8List photo;
  final Rect initialCrop;
  const PhotoCropScreen({
    super.key,
    required this.photo,
    this.initialCrop = fullPhotoCrop,
  });

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  late Rect _crop = widget.initialCrop;
  double? _imageRatio, _ratio;
  String _preset = 'Free';
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _readSize();
  }

  Future<void> _readSize() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.photo);
      try {
        final frame = await codec.getNextFrame();
        final ratio = frame.image.width / frame.image.height;
        frame.image.dispose();
        if (mounted) setState(() => _imageRatio = ratio);
      } finally {
        codec.dispose();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _select(String name) {
    final ratio = switch (name) {
      'Original' => _imageRatio,
      'Square' => 1.0,
      '3:4' => 3 / 4,
      '9:16' => 9 / 16,
      _ => null,
    };
    setState(() {
      _preset = name;
      _ratio = ratio;
      _crop = cropForRatio(_crop, _imageRatio!, ratio);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('Crop photo'),
      actions: [
        TextButton(
          onPressed: _imageRatio == null
              ? null
              : () => Navigator.pop(context, _crop),
          child: const Text('Done'),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _failed
                  ? const Center(
                      child: Text(
                        'Could not open this photo. Go back and try again.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _imageRatio == null
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                      child: AspectRatio(
                        aspectRatio: _imageRatio!,
                        child: LayoutBuilder(
                          builder: (context, bounds) {
                            final size = bounds.biggest;
                            final rect = Rect.fromLTWH(
                              _crop.left * size.width,
                              _crop.top * size.height,
                              _crop.width * size.width,
                              _crop.height * size.height,
                            );
                            Offset normalized(Offset delta) => Offset(
                              delta.dx / size.width,
                              delta.dy / size.height,
                            );
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: Image.memory(
                                    widget.photo,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: _CropOverlay(rect),
                                    ),
                                  ),
                                ),
                                Positioned.fromRect(
                                  rect: rect,
                                  child: GestureDetector(
                                    key: const ValueKey('crop_selection'),
                                    behavior: HitTestBehavior.opaque,
                                    onPanUpdate: (details) => setState(
                                      () => _crop = movePhotoCrop(
                                        _crop,
                                        normalized(details.delta),
                                      ),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                for (var i = 0; i < 4; i++)
                                  Positioned(
                                    left:
                                        [
                                          rect.topLeft,
                                          rect.topRight,
                                          rect.bottomRight,
                                          rect.bottomLeft,
                                        ][i].dx -
                                        (i == 0 || i == 3 ? 0 : 44),
                                    top:
                                        [
                                          rect.topLeft,
                                          rect.topRight,
                                          rect.bottomRight,
                                          rect.bottomLeft,
                                        ][i].dy -
                                        (i < 2 ? 0 : 44),
                                    child: GestureDetector(
                                      key: ValueKey('crop_handle_$i'),
                                      behavior: HitTestBehavior.opaque,
                                      onPanUpdate: (details) => setState(
                                        () => _crop = resizePhotoCrop(
                                          _crop,
                                          normalized(details.delta),
                                          i,
                                          _ratio == null
                                              ? null
                                              : _ratio! / _imageRatio!,
                                        ),
                                      ),
                                      child: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Align(
                                          alignment: [
                                            Alignment.topLeft,
                                            Alignment.topRight,
                                            Alignment.bottomRight,
                                            Alignment.bottomLeft,
                                          ][i],
                                          child: Container(
                                            width: 14,
                                            height: 14,
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Drag the corners to crop. Drag inside to reposition.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                for (final name in [
                  'Free',
                  'Original',
                  'Square',
                  '3:4',
                  '9:16',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(name),
                      selected: _preset == name,
                      onSelected: _imageRatio == null
                          ? null
                          : (_) => _select(name),
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _imageRatio == null
                ? null
                : () => setState(() {
                    _crop = fullPhotoCrop;
                    _ratio = null;
                    _preset = 'Free';
                  }),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset crop'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _CropOverlay extends CustomPainter {
  final Rect crop;
  _CropOverlay(this.crop);

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(crop);
    canvas.drawPath(shade, Paint()..color = Colors.black54);
    canvas.drawRect(
      crop,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final grid = Paint()
      ..color = Colors.white38
      ..strokeWidth = .75;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(crop.left + crop.width * i / 3, crop.top),
        Offset(crop.left + crop.width * i / 3, crop.bottom),
        grid,
      );
      canvas.drawLine(
        Offset(crop.left, crop.top + crop.height * i / 3),
        Offset(crop.right, crop.top + crop.height * i / 3),
        grid,
      );
    }
  }

  @override
  bool shouldRepaint(_CropOverlay oldDelegate) => oldDelegate.crop != crop;
}
