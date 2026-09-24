import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const KirozaiApp());

const canvasSize = Size(1024, 768);

class Stroke {
  const Stroke(this.points, this.color, this.width, this.erase,
      {this.shape = StrokeShape.freehand});
  final List<Offset> points;
  final Color color;
  final double width;
  final bool erase;
  final StrokeShape shape;
}

enum StrokeShape { freehand, line, rectangle }

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

  Map<String, Object> toJson() => {
        'version': 1,
        'selected': selected,
        'layers': [
          for (final layer in layers)
            {
              'name': layer.name,
              'visible': layer.visible,
              'strokes': [
                for (final stroke in layer.strokes)
                  {
                    'points': [
                      for (final point in stroke.points) [point.dx, point.dy],
                    ],
                    'color': stroke.color.toARGB32(),
                    'width': stroke.width,
                    'erase': stroke.erase,
                    'shape': stroke.shape.name,
                  },
              ],
            },
        ],
      };

  factory DrawingDocument.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('Versión no compatible');
    final layers = (json['layers'] as List).map((entry) {
      final layer = entry as Map<String, dynamic>;
      final strokes = (layer['strokes'] as List).map((entry) {
        final stroke = entry as Map<String, dynamic>;
        final points = (stroke['points'] as List).map((entry) {
          final pair = entry as List;
          if (pair.length != 2) throw const FormatException('Punto inválido');
          return Offset((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
        }).toList();
        final width = (stroke['width'] as num).toDouble();
        if (width <= 0 || !width.isFinite ||
            points.any((p) => !p.dx.isFinite || !p.dy.isFinite)) {
          throw const FormatException('Trazo inválido');
        }
        final shape = StrokeShape.values.firstWhere(
          (value) => value.name == (stroke['shape'] ?? 'freehand'),
          orElse: () => throw const FormatException('Forma inválida'),
        );
        return Stroke(points, Color(stroke['color'] as int), width,
            stroke['erase'] as bool, shape: shape);
      }).toList();
      return DrawingLayer(layer['name'] as String, strokes,
          visible: layer['visible'] as bool);
    }).toList();
    final selected = json['selected'] as int;
    if (layers.isEmpty || selected < 0 || selected >= layers.length) {
      throw const FormatException('Capas inválidas');
    }
    return DrawingDocument(layers, selected);
  }
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

enum CanvasTool { brush, eraser, line, rectangle, navigate }

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
  bool _saving = false;
  bool _dirty = false;
  int? _activePointer;

  Future<void> _newProject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo dibujo'),
        content: const Text('Se borrará el dibujo actual. Guarda el proyecto antes si deseas conservarlo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Crear')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _document = const DrawingDocument([DrawingLayer('Capa 1', [])], 0);
      _dirty = false;
      _undo.clear();
      _redo.clear();
      _currentPoints.clear();
      _activePointer = null;
      _transform.value = Matrix4.identity();
    });
  }

  Future<void> _chooseColor() async {
    var hsv = HSVColor.fromColor(_color);
    final chosen = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Elegir color'),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(height: 40, decoration: BoxDecoration(
                color: hsv.toColor(), borderRadius: BorderRadius.circular(8))),
              const Text('Tono'),
              Slider(value: hsv.hue, min: 0, max: 360,
                  onChanged: (value) => update(() => hsv = hsv.withHue(value))),
              const Text('Saturación'),
              Slider(value: hsv.saturation,
                  onChanged: (value) => update(() => hsv = hsv.withSaturation(value))),
              const Text('Brillo'),
              Slider(value: hsv.value,
                  onChanged: (value) => update(() => hsv = hsv.withValue(value))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(context, hsv.toColor()),
                child: const Text('Aplicar')),
          ],
        ),
      ),
    );
    if (mounted && chosen != null) setState(() => _color = chosen);
  }

  Future<File> _projectFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/kirozai-project.json');
  }

  Future<void> _saveProject() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final snapshot = _document;
      final file = await _projectFile();
      await file.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      if (mounted && identical(_document, snapshot)) {
        setState(() => _dirty = false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Proyecto guardado en ${file.path}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openProject() async {
    if (_dirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Abrir proyecto guardado'),
          content: const Text('El dibujo actual tiene cambios sin guardar. ¿Descartarlos?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Descartar cambios')),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    try {
      final file = await _projectFile();
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final document = DrawingDocument.fromJson(decoded);
      if (!mounted) return;
      setState(() {
        _document = document;
        _dirty = false;
        _undo.clear();
        _redo.clear();
        _currentPoints.clear();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el proyecto: $error')),
        );
      }
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _commit(DrawingDocument next) {
    setState(() {
      _undo.add(_document);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
      _document = next;
      _dirty = true;
    });
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_document);
      _document = _undo.removeLast();
      _dirty = true;
    });
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_document);
      _document = _redo.removeLast();
      _dirty = true;
    });
  }

  void _replaceLayer(int index, DrawingLayer replacement) {
    final layers = [..._document.layers];
    layers[index] = replacement;
    _commit(DrawingDocument(layers, _document.selected));
  }

  void _duplicateSelectedLayer() {
    final layers = [..._document.layers];
    final original = layers[_document.selected];
    final index = _document.selected + 1;
    layers.insert(index, DrawingLayer('${original.name} copia',
        List.of(original.strokes), visible: original.visible));
    _commit(DrawingDocument(layers, index));
  }

  void _moveLayer(int index, int direction) {
    final target = index + direction;
    if (target < 0 || target >= _document.layers.length) return;
    final layers = [..._document.layers];
    final layer = layers.removeAt(index);
    layers.insert(target, layer);
    final selected = _document.selected == index
        ? target
        : _document.selected == target
            ? index
            : _document.selected;
    _commit(DrawingDocument(layers, selected));
  }

  Future<void> _renameLayer(int index) async {
    var editedName = _document.layers[index].name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renombrar capa'),
        content: TextFormField(
          initialValue: editedName,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onChanged: (value) => editedName = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, editedName),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    _replaceLayer(index, _document.layers[index].copyWith(name: name.trim()));
  }

  void _startStroke(PointerDownEvent event) {
    if (_tool == CanvasTool.navigate) return;
    if (!_document.layers[_document.selected].visible) return;
    if (_activePointer != null) {
      setState(() => _currentPoints.clear());
      return;
    }
    _activePointer = event.pointer;
    setState(() {
      _currentPoints
        ..clear()
        ..add(event.localPosition);
    });
  }

  void _extendStroke(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _currentPoints.isEmpty) return;
    setState(() {
      if (_tool == CanvasTool.line || _tool == CanvasTool.rectangle) {
        if (_currentPoints.length == 2) _currentPoints.removeLast();
      }
      _currentPoints.add(event.localPosition);
    });
  }

  void _endStroke(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    if (event is PointerCancelEvent) {
      setState(() => _currentPoints.clear());
      return;
    }
    if (_currentPoints.isEmpty) return;
    final layer = _document.layers[_document.selected];
    final points = List<Offset>.of(_currentPoints);
    if (_tool == CanvasTool.line || _tool == CanvasTool.rectangle) {
      if (points.length == 1) points.add(event.localPosition);
      points[1] = event.localPosition;
    }
    final shape = _tool == CanvasTool.line ? StrokeShape.line
        : _tool == CanvasTool.rectangle ? StrokeShape.rectangle
        : StrokeShape.freehand;
    final stroke = Stroke(points, _color, _width,
        _tool == CanvasTool.eraser, shape: shape);
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
          _toolButton('Línea', Icons.show_chart, CanvasTool.line),
          _toolButton('Rectángulo', Icons.crop_square, CanvasTool.rectangle),
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
        TextButton.icon(onPressed: _chooseColor,
            icon: const Icon(Icons.color_lens_outlined),
            label: const Text('Elegir otro color')),
        const SizedBox(height: 14),
        Text('Grosor: ${_width.round()} px'),
        Slider(value: _width, min: 1, max: 60,
          onChanged: (value) => setState(() => _width = value)),
        const Divider(height: 28),
        Row(children: [
          const Expanded(child: Text('CAPAS', style: TextStyle(fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'Duplicar capa seleccionada',
              icon: const Icon(Icons.copy_outlined),
              onPressed: _duplicateSelectedLayer),
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
            subtitle: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Subir ${_document.layers[i].name}',
                icon: const Icon(Icons.arrow_upward, size: 18),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                padding: EdgeInsets.zero,
                onPressed: i == _document.layers.length - 1
                    ? null : () => _moveLayer(i, 1),
              ),
              IconButton(
                tooltip: 'Bajar ${_document.layers[i].name}',
                icon: const Icon(Icons.arrow_downward, size: 18),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                padding: EdgeInsets.zero,
                onPressed: i == 0 ? null : () => _moveLayer(i, -1),
              ),
              IconButton(
                tooltip: 'Renombrar ${_document.layers[i].name}',
                icon: const Icon(Icons.edit_outlined, size: 18),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                padding: EdgeInsets.zero,
                onPressed: () => _renameLayer(i),
              ),
            ]),
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

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undoAction,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undoAction,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redoAction,
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): _redoAction,
        const SingleActivator(LogicalKeyboardKey.keyZ,
            meta: true, shift: true): _redoAction,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveProject,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveProject,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      appBar: AppBar(title: Text(_dirty ? 'Kirozai •' : 'Kirozai'), actions: [
        IconButton(tooltip: 'Deshacer', onPressed: _undo.isEmpty ? null : _undoAction,
            icon: const Icon(Icons.undo)),
        IconButton(tooltip: 'Rehacer', onPressed: _redo.isEmpty ? null : _redoAction,
            icon: const Icon(Icons.redo)),
        IconButton(tooltip: 'Exportar PNG',
            onPressed: _exporting ? null : _exportPng,
            icon: const Icon(Icons.ios_share)),
        PopupMenuButton<String>(
          tooltip: 'Archivo',
          onSelected: (action) {
            if (action == 'new') _newProject();
            if (action == 'open') _openProject();
            if (action == 'save') _saveProject();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'new', child: Text('Nuevo dibujo')),
            const PopupMenuItem(value: 'open', child: Text('Abrir proyecto guardado')),
            PopupMenuItem(value: 'save', enabled: !_saving,
                child: const Text('Guardar proyecto')),
          ],
        ),
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
                      previewShape: _tool == CanvasTool.line ? StrokeShape.line
                          : _tool == CanvasTool.rectangle ? StrokeShape.rectangle
                          : StrokeShape.freehand,
                      selected: _document.selected),
                ),
              ),
            ),
          )),
        )),
      ]),
        ),
      ),
    );
  }

  Widget _toolButton(String title, IconData icon, CanvasTool tool) =>
      ChoiceChip(label: Text(title), avatar: Icon(icon, size: 18),
        selected: _tool == tool,
        onSelected: (_) => setState(() {
          _currentPoints.clear();
          _activePointer = null;
          _tool = tool;
        }));
}

class CanvasArtwork extends CustomPainter {
  CanvasArtwork(this.layers, {this.preview = const [], this.previewColor = Colors.black,
    this.previewWidth = 1, this.previewErase = false,
    this.previewShape = StrokeShape.freehand, this.selected = -1});

  final List<DrawingLayer> layers;
  final List<Offset> preview;
  final Color previewColor;
  final double previewWidth;
  final bool previewErase;
  final StrokeShape previewShape;
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
        _paintStroke(canvas, Stroke(preview, previewColor, previewWidth,
            previewErase, shape: previewShape));
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
    if (stroke.shape == StrokeShape.rectangle && stroke.points.length > 1) {
      canvas.drawRect(Rect.fromPoints(stroke.points.first, stroke.points.last), paint);
      return;
    }
    if (stroke.shape == StrokeShape.line && stroke.points.length > 1) {
      canvas.drawLine(stroke.points.first, stroke.points.last, paint);
      return;
    }
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
