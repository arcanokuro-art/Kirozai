import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const KirozaiApp());

const canvasSize = Size(1024, 768);

class Stroke {
  const Stroke(this.points, this.color, this.width, this.erase);
  final List<Offset> points;
  final Color color;
  final double width;
  final bool erase;
}

class DrawingLayer {
  const DrawingLayer(this.name, this.strokes, {this.visible = true});
  final String name;
  final List<Stroke> strokes;
  final bool visible;

  DrawingLayer copyWith({String? name, List<Stroke>? strokes, bool? visible}) =>
      DrawingLayer(name ?? this.name, strokes ?? this.strokes,
          visible: visible ?? this.visible);
}

class DrawingDocument {
  const DrawingDocument(this.layers, this.selected);
  final List<DrawingLayer> layers;
  final int selected;
}

class KirozaiApp extends StatelessWidget {
  const KirozaiApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kirozai',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xff151821),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff8e70f8),
            brightness: Brightness.dark,
          ),
        ),
        home: const Editor(),
      );
}

enum CanvasTool { brush, eraser, navigate }

class Editor extends StatefulWidget {
  const Editor({super.key});

  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  DrawingDocument _document =
      const DrawingDocument([DrawingLayer('Capa 1', [])], 0);
  final List<DrawingDocument> _undo = [];
  final List<DrawingDocument> _redo = [];
  final TransformationController _transform = TransformationController();
  final List<Offset> _currentPoints = [];
  CanvasTool _tool = CanvasTool.brush;
  Color _color = const Color(0xff222634);
  double _width = 8;
  bool _exporting = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _commit(DrawingDocument next) {
    setState(() {
      _undo.add(_document);
      _redo.clear();
      _document = next;
    });
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_document);
      _document = _undo.removeLast();
    });
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_document);
      _document = _redo.removeLast();
    });
  }

  void _replaceLayer(int index, DrawingLayer replacement) {
    final layers = [..._document.layers];
    layers[index] = replacement;
    _commit(DrawingDocument(layers, _document.selected));
  }

  void _startStroke(PointerDownEvent event) {
    if (_tool == CanvasTool.navigate) return;
    if (!_document.layers[_document.selected].visible) return;
    setState(() {
      _currentPoints
        ..clear()
        ..add(event.localPosition);
    });
  }

  void _extendStroke(PointerMoveEvent event) {
    if (_currentPoints.isEmpty) return;
    setState(() => _currentPoints.add(event.localPosition));
  }

  void _endStroke(PointerEvent event) {
    if (_currentPoints.isEmpty) return;
    final layer = _document.layers[_document.selected];
    final stroke = Stroke(List.of(_currentPoints), _color, _width,
        _tool == CanvasTool.eraser);
    _currentPoints.clear();
    _replaceLayer(_document.selected,
        layer.copyWith(strokes: [...layer.strokes, stroke]));
  }

  Future<void> _exportPng() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      CanvasArtwork(_document.layers).paint(canvas, canvasSize);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        canvasSize.width.toInt(),
        canvasSize.height.toInt(),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (bytes == null) throw StateError('No se pudo generar el PNG');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kirozai-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const palette = [
      Color(0xff222634), Color(0xffffffff), Color(0xffe8566d),
      Color(0xffffb44d), Color(0xff58b887), Color(0xff59a7ed),
      Color(0xffa884f7),
    ];
    final compact = MediaQuery.sizeOf(context).width < 750;
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('HERRAMIENTAS', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 5, runSpacing: 5, children: [
          _toolButton('Pincel', Icons.brush, CanvasTool.brush),
          _toolButton('Borrador', Icons.auto_fix_off, CanvasTool.eraser),
          _toolButton('Mover / zoom', Icons.pan_tool_alt, CanvasTool.navigate),
        ]),
        const SizedBox(height: 18),
        const Text('COLOR', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 7, runSpacing: 7, children: [
          for (final color in palette)
            InkWell(
              onTap: () => setState(() => _color = color),
              child: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle,
                  border: Border.all(
                    color: _color == color ? Colors.deepPurpleAccent : Colors.grey,
                    width: _color == color ? 3 : 1,
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        Text('Grosor: ${_width.round()} px'),
        Slider(value: _width, min: 1, max: 60,
          onChanged: (value) => setState(() => _width = value)),
        const Divider(height: 28),
        Row(children: [
          const Expanded(child: Text('CAPAS', style: TextStyle(fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'Agregar capa', icon: const Icon(Icons.add), onPressed: () {
            _commit(DrawingDocument([
              ..._document.layers,
              DrawingLayer('Capa ${_document.layers.length + 1}', const []),
            ], _document.layers.length));
          }),
        ]),
        for (var i = _document.layers.length - 1; i >= 0; i--)
          ListTile(
            dense: true,
            selected: i == _document.selected,
            title: Text(_document.layers[i].name),
            leading: IconButton(
              tooltip: _document.layers[i].visible ? 'Ocultar capa' : 'Mostrar capa',
              icon: Icon(_document.layers[i].visible
                  ? Icons.visibility : Icons.visibility_off),
              onPressed: () => _replaceLayer(i, _document.layers[i].copyWith(
                  visible: !_document.layers[i].visible)),
            ),
            trailing: IconButton(
              tooltip: 'Eliminar capa', icon: const Icon(Icons.delete_outline),
              onPressed: _document.layers.length == 1 ? null : () {
                final layers = [..._document.layers]..removeAt(i);
                final selected = _document.selected == i
                    ? (i == layers.length ? i - 1 : i)
                    : _document.selected > i ? _document.selected - 1 : _document.selected;
                _commit(DrawingDocument(layers, selected));
              },
            ),
            onTap: () => setState(() => _document =
                DrawingDocument(_document.layers, i)),
          ),
      ],
    );

    final panel = SizedBox(
      width: compact ? null : 280,
      child: ListView(padding: const EdgeInsets.all(16), children: [controls]),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Kirozai'), actions: [
        IconButton(tooltip: 'Deshacer', onPressed: _undo.isEmpty ? null : _undoAction,
            icon: const Icon(Icons.undo)),
        IconButton(tooltip: 'Rehacer', onPressed: _redo.isEmpty ? null : _redoAction,
            icon: const Icon(Icons.redo)),
        IconButton(tooltip: 'Exportar PNG',
            onPressed: _exporting ? null : _exportPng,
            icon: const Icon(Icons.ios_share)),
      ]),
      drawer: compact ? Drawer(child: SafeArea(child: panel)) : null,
      body: Row(children: [
        if (!compact) panel,
        Expanded(child: Container(
          color: const Color(0xff303441),
          child: Center(child: InteractiveViewer(
            transformationController: _transform,
            panEnabled: _tool == CanvasTool.navigate,
            scaleEnabled: _tool == CanvasTool.navigate,
            minScale: 0.2, maxScale: 6,
            constrained: false,
            child: Listener(
              onPointerDown: _startStroke,
              onPointerMove: _extendStroke,
              onPointerUp: _endStroke,
              onPointerCancel: _endStroke,
              child: SizedBox(
                width: canvasSize.width, height: canvasSize.height,
                child: CustomPaint(
                  painter: CanvasArtwork(_document.layers, preview: _currentPoints,
                      previewColor: _color, previewWidth: _width,
                      previewErase: _tool == CanvasTool.eraser,
                      selected: _document.selected),
                ),
              ),
            ),
          )),
        )),
      ]),
    );
  }

  Widget _toolButton(String title, IconData icon, CanvasTool tool) =>
      ChoiceChip(label: Text(title), avatar: Icon(icon, size: 18),
        selected: _tool == tool,
        onSelected: (_) => setState(() {
          _currentPoints.clear();
          _tool = tool;
        }));
}

class CanvasArtwork extends CustomPainter {
  CanvasArtwork(this.layers, {this.preview = const [], this.previewColor = Colors.black,
    this.previewWidth = 1, this.previewErase = false, this.selected = -1});

  final List<DrawingLayer> layers;
  final List<Offset> preview;
  final Color previewColor;
  final double previewWidth;
  final bool previewErase;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (var i = 0; i < layers.length; i++) {
      if (!layers[i].visible) continue;
      canvas.saveLayer(Offset.zero & size, Paint());
      for (final stroke in layers[i].strokes) {
        _paintStroke(canvas, stroke);
      }
      if (i == selected && preview.isNotEmpty) {
        _paintStroke(canvas, Stroke(preview, previewColor, previewWidth, previewErase));
      }
      canvas.restore();
    }
  }

  void _paintStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = stroke.erase ? BlendMode.clear : BlendMode.srcOver;
    if (stroke.points.length == 1) {
      canvas.drawCircle(stroke.points.first, stroke.width / 2,
          paint..style = PaintingStyle.fill);
      return;
    }
    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CanvasArtwork oldDelegate) => true;
}
