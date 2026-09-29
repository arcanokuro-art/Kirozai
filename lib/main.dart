import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const KirozaiApp());

const canvasSize = Size(1024, 768);

Matrix4 centeredCanvasTransform(Size viewport, {bool actualSize = false}) {
  final scale = actualSize ? 1.0 :
      (math.min(viewport.width / canvasSize.width,
          viewport.height / canvasSize.height) * 0.95).clamp(0.1, 6.0).toDouble();
  return Matrix4.diagonal3Values(scale, scale, 1)
    ..setTranslationRaw((viewport.width - canvasSize.width * scale) / 2,
        (viewport.height - canvasSize.height * scale) / 2, 0);
}

class Stroke {
  const Stroke(this.points, this.color, this.width, this.erase,
      {this.shape = StrokeShape.freehand, this.filled = false});
  final List<Offset> points;
  final Color color;
  final double width;
  final bool erase;
  final StrokeShape shape;
  final bool filled;
}

enum StrokeShape { freehand, line, rectangle, ellipse }

class DrawingLayer {
  const DrawingLayer(this.name, this.strokes,
      {this.visible = true, this.locked = false, this.opacity = 1,
      this.imageBytes, this.image});
  final String name;
  final List<Stroke> strokes;
  final bool visible;
  final bool locked;
  final double opacity;
  final Uint8List? imageBytes;
  final ui.Image? image;

  DrawingLayer copyWith({String? name, List<Stroke>? strokes, bool? visible,
      bool? locked,
      double? opacity,
      Uint8List? imageBytes, ui.Image? image}) =>
      DrawingLayer(name ?? this.name, strokes ?? this.strokes,
          visible: visible ?? this.visible, locked: locked ?? this.locked,
          opacity: opacity ?? this.opacity,
          imageBytes: imageBytes ?? this.imageBytes,
          image: image ?? this.image);
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
              if (layer.locked) 'locked': true,
              if (layer.opacity != 1) 'opacity': layer.opacity,
              if (layer.imageBytes != null)
                'imageData': base64Encode(layer.imageBytes!),
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
                    if (stroke.filled) 'filled': true,
                  },
              ],
            },
        ],
      };

  factory DrawingDocument.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('Versión no compatible');
    final layers = (json['layers'] as List).map((entry) {
      final layer = entry as Map<String, dynamic>;
      final locked = layer['locked'] ?? false;
      if (locked is! bool) {
        throw const FormatException('Bloqueo de capa inválido');
      }
      final opacity = (layer['opacity'] as num?)?.toDouble() ?? 1;
      if (!opacity.isFinite || opacity < 0 || opacity > 1) {
        throw const FormatException('Opacidad de capa inválida');
      }
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
            stroke['erase'] as bool, shape: shape,
            filled: stroke['filled'] == true);
      }).toList();
      return DrawingLayer(layer['name'] as String, strokes,
          visible: layer['visible'] as bool, locked: locked, opacity: opacity,
          imageBytes: layer['imageData'] == null
              ? null : base64Decode(layer['imageData'] as String));
    }).toList();
    final selected = json['selected'] as int;
    if (layers.isEmpty || selected < 0 || selected >= layers.length) {
      throw const FormatException('Capas inválidas');
    }
    return DrawingDocument(layers, selected);
  }
}

Future<void> writeProjectAtomically(File destination, DrawingDocument document) async {
  final temporary = File('${destination.path}.tmp');
  try {
    await temporary.writeAsString(jsonEncode(document.toJson()), flush: true);
    await temporary.rename(destination.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
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

Color? parseHexColor(String value) {
  final hex = value.trim().replaceFirst(RegExp(r'^#'), '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(0xff000000 | int.parse(hex, radix: 16));
}

String colorHex(Color color) =>
    '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({super.key, required this.initialColor});
  final Color initialColor;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hex;
  bool _valid = true;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor.withValues(alpha: 1));
    _hex = TextEditingController(text: colorHex(_hsv.toColor()));
  }

  void _updateSliders(HSVColor color) {
    setState(() {
      _hsv = color;
      _valid = true;
      _hex.text = colorHex(color.toColor());
    });
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Elegir color'),
    content: SizedBox(
      width: 320,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(key: const Key('color-preview'), height: 40,
              decoration: BoxDecoration(color: _hsv.toColor(),
                  borderRadius: BorderRadius.circular(8))),
          const SizedBox(height: 12),
          TextField(
            key: const Key('hex-color'),
            controller: _hex,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            maxLength: 7,
            decoration: InputDecoration(
              labelText: 'Código de color', hintText: '#59A7ED',
              errorText: _valid ? null : 'Usa seis caracteres: 0–9 o A–F',
            ),
            onChanged: (value) {
              final color = parseHexColor(value);
              setState(() {
                _valid = color != null;
                if (color != null) _hsv = HSVColor.fromColor(color);
              });
            },
          ),
          const Text('Tono'),
          Slider(key: const Key('color-hue'), value: _hsv.hue,
              min: 0, max: 360,
              onChanged: (value) => _updateSliders(_hsv.withHue(value))),
          const Text('Saturación'),
          Slider(value: _hsv.saturation,
              onChanged: (value) => _updateSliders(_hsv.withSaturation(value))),
          const Text('Brillo'),
          Slider(value: _hsv.value,
              onChanged: (value) => _updateSliders(_hsv.withValue(value))),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar')),
      FilledButton(onPressed: _valid
          ? () => Navigator.pop(context, parseHexColor(_hex.text)) : null,
          child: const Text('Aplicar')),
    ],
  );
}

enum CanvasTool { brush, eraser, line, rectangle, ellipse, eyedropper, navigate }

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
  Size _viewport = Size.zero;
  bool _viewInitialized = false;

  void _centerCanvas({bool actualSize = false}) {
    if (_viewport.isEmpty) return;
    setState(() {
      _currentPoints.clear();
      _activePointer = null;
    });
    _transform.value = centeredCanvasTransform(_viewport, actualSize: actualSize);
  }
  CanvasTool _tool = CanvasTool.brush;
  Color _color = const Color(0xff222634);
  double _width = 8;
  double _opacity = 1;
  bool _fillShapes = false;
  bool _exporting = false;
  bool _saving = false;
  bool _sharingProject = false;
  bool _exitPromptOpen = false;
  bool _dirty = false;
  int? _activePointer;
  final Set<int> _pointersOnCanvas = {};

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
      _transform.value = centeredCanvasTransform(_viewport);
    });
  }

  Future<void> _chooseColor() async {
    final chosen = await showDialog<Color>(
      context: context,
      builder: (context) => ColorPickerDialog(initialColor: _color),
    );
    if (mounted && chosen != null) setState(() => _color = chosen);
  }

  Future<File> _projectFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/kirozai-project.json');
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: 2048, allowUpscaling: false);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<void> _importImage() async {
    try {
      const images = XTypeGroup(label: 'Imágenes',
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
          mimeTypes: ['image/png', 'image/jpeg', 'image/webp']);
      final file = await openFile(acceptedTypeGroups: [images]);
      if (file == null) return;
      if (await file.length() > 20 * 1024 * 1024) {
        throw const FormatException('La imagen supera 20 MB');
      }
      final bytes = await file.readAsBytes();
      final image = await _decodeImage(bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      final layers = [..._document.layers,
        DrawingLayer(file.name, const [], imageBytes: bytes, image: image)];
      _commit(DrawingDocument(layers, layers.length - 1));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo importar la imagen: $error')),
        );
      }
    }
  }

  Future<bool> _saveProject() async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      final snapshot = _document;
      final file = await _projectFile();
      await writeProjectAtomically(file, snapshot);
      if (mounted && identical(_document, snapshot)) {
        setState(() => _dirty = false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Proyecto guardado en ${file.path}')),
        );
      }
      return mounted && !_dirty;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $error')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmExit() async {
    if (_exitPromptOpen) return;
    _exitPromptOpen = true;
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cambios sin guardar'),
          content: const Text('¿Deseas guardar el dibujo antes de salir?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'),
                child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'discard'),
                child: const Text('Salir sin guardar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, 'save'),
                child: const Text('Guardar y salir')),
          ],
        ),
      );
      if (!mounted || choice == null || choice == 'cancel') return;
      if (choice == 'save' && !await _saveProject()) return;
      await SystemNavigator.pop();
    } finally {
      _exitPromptOpen = false;
    }
  }

  Future<void> _shareProject() async {
    if (_sharingProject) return;
    setState(() => _sharingProject = true);
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/kirozai-${DateTime.now().microsecondsSinceEpoch}.json');
      await writeProjectAtomically(file, _document);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo compartir el proyecto: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingProject = false);
    }
  }

  Future<void> _openProject({bool external = false}) async {
    XFile? selectedFile;
    if (external) {
      try {
        selectedFile = await openFile(acceptedTypeGroups: [
          const XTypeGroup(label: 'Proyecto Kirozai',
              extensions: ['json'], mimeTypes: ['application/json']),
        ]);
        if (selectedFile == null || !mounted) return;
        if (await selectedFile.length() > 50 * 1024 * 1024) {
          throw const FormatException('El proyecto supera 50 MB');
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo seleccionar el proyecto: $error')),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    if (_dirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(external ? 'Importar proyecto' : 'Abrir proyecto guardado'),
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
      final contents = selectedFile == null
          ? await (await _projectFile()).readAsString()
          : await selectedFile.readAsString();
      final decoded = jsonDecode(contents) as Map<String, dynamic>;
      final stored = DrawingDocument.fromJson(decoded);
      final layers = <DrawingLayer>[];
      for (final layer in stored.layers) {
        final bytes = layer.imageBytes;
        layers.add(bytes == null ? layer : layer.copyWith(
            image: await _decodeImage(bytes)));
      }
      final document = DrawingDocument(layers, stored.selected);
      if (!mounted) return;
      setState(() {
        _document = document;
        _dirty = external;
        _undo.clear();
        _redo.clear();
        _currentPoints.clear();
      });
      if (external) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Proyecto importado. Guarda para conservarlo en la aplicación.'),
        ));
      }
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
        List.of(original.strokes), visible: original.visible,
        locked: original.locked,
        opacity: original.opacity,
        imageBytes: original.imageBytes, image: original.image));
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

  Future<void> _clearLayer(int index) async {
    final layer = _document.layers[index];
    if (layer.locked || (layer.strokes.isEmpty && layer.imageBytes == null)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vaciar capa'),
        content: Text('Se quitarán los trazos y la imagen de «${layer.name}». Puedes deshacer este cambio.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Vaciar')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final currentIndex = _document.layers.indexOf(layer);
    if (currentIndex < 0 || layer.locked) return;
    _replaceLayer(currentIndex, DrawingLayer(layer.name, const [],
        visible: layer.visible, opacity: layer.opacity));
  }

  Future<void> _deleteLayer(int index) async {
    if (_document.layers.length <= 1) return;
    final layer = _document.layers[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar capa'),
        content: Text('¿Eliminar «${layer.name}»? Puedes deshacer este cambio.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (!mounted || confirmed != true || _document.layers.length <= 1) return;
    final currentIndex = _document.layers.indexOf(layer);
    if (currentIndex < 0) return;
    final layers = [..._document.layers]..removeAt(currentIndex);
    final selected = _document.selected == currentIndex
        ? (currentIndex == layers.length ? currentIndex - 1 : currentIndex)
        : _document.selected > currentIndex
            ? _document.selected - 1 : _document.selected;
    _commit(DrawingDocument(layers, selected));
  }

  void _startStroke(PointerDownEvent event) {
    _pointersOnCanvas.add(event.pointer);
    if (_pointersOnCanvas.length > 1) {
      _activePointer = null;
      setState(() => _currentPoints.clear());
      return;
    }
    if (_tool == CanvasTool.navigate) return;
    if (_tool == CanvasTool.eyedropper) {
      _pickColor(event.localPosition);
      return;
    }
    if (!_document.layers[_document.selected].visible ||
        _document.layers[_document.selected].locked) {
      return;
    }
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

  Future<void> _pickColor(Offset position) async {
    try {
      final sampled = await sampleArtworkColor(_document.layers, position);
      if (mounted && _tool == CanvasTool.eyedropper && sampled != null) {
        setState(() {
          _color = sampled;
          _opacity = sampled.a;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo tomar el color: $error')),
        );
      }
    }
  }

  void _extendStroke(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _currentPoints.isEmpty) return;
    setState(() {
      if (_tool == CanvasTool.line || _tool == CanvasTool.rectangle ||
          _tool == CanvasTool.ellipse) {
        if (_currentPoints.length == 2) _currentPoints.removeLast();
      }
      _currentPoints.add(event.localPosition);
    });
  }

  void _endStroke(PointerEvent event) {
    _pointersOnCanvas.remove(event.pointer);
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    if (event is PointerCancelEvent) {
      setState(() => _currentPoints.clear());
      return;
    }
    if (_currentPoints.isEmpty) return;
    final layer = _document.layers[_document.selected];
    if (layer.locked || !layer.visible) {
      setState(() => _currentPoints.clear());
      return;
    }
    final points = List<Offset>.of(_currentPoints);
    if (_tool == CanvasTool.line || _tool == CanvasTool.rectangle ||
        _tool == CanvasTool.ellipse) {
      if (points.length == 1) points.add(event.localPosition);
      points[1] = event.localPosition;
    }
    final shape = _tool == CanvasTool.line ? StrokeShape.line
        : _tool == CanvasTool.rectangle ? StrokeShape.rectangle
        : _tool == CanvasTool.ellipse ? StrokeShape.ellipse
        : StrokeShape.freehand;
    final stroke = Stroke(points, _color.withValues(alpha: _opacity), _width,
        _tool == CanvasTool.eraser, shape: shape,
        filled: _fillShapes &&
            (shape == StrokeShape.rectangle || shape == StrokeShape.ellipse));
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
          _toolButton('Elipse', Icons.circle_outlined, CanvasTool.ellipse),
          _toolButton('Cuentagotas', Icons.colorize, CanvasTool.eyedropper),
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
        Text('Opacidad: ${(_opacity * 100).round()} %'),
        Slider(key: const Key('stroke-opacity'), value: _opacity,
          min: 0.05, max: 1, divisions: 19,
          onChanged: (value) => setState(() => _opacity = value)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Rellenar figuras'),
          value: _fillShapes,
          onChanged: (value) => setState(() => _fillShapes = value),
        ),
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
        PopupMenuButton<double>(
          tooltip: 'Opacidad de capa',
          onSelected: (value) {
            final index = _document.selected;
            _replaceLayer(index, _document.layers[index].copyWith(opacity: value));
          },
          itemBuilder: (context) => [
            for (final value in [1.0, 0.75, 0.5, 0.25])
              PopupMenuItem(value: value,
                  child: Text('${(value * 100).round()} %')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(child: Text(
                'Opacidad capa: ${(_document.layers[_document.selected].opacity * 100).round()} %',
                overflow: TextOverflow.ellipsis,
              )),
              const Icon(Icons.arrow_drop_down),
            ]),
          ),
        ),
        for (var i = _document.layers.length - 1; i >= 0; i--)
          ListTile(
            dense: true,
            selected: i == _document.selected,
            title: Text(_document.layers[i].name),
            subtitle: Wrap(spacing: 0, runSpacing: 0, children: [
              IconButton(
                tooltip: 'Vaciar ${_document.layers[i].name}',
                icon: const Icon(Icons.layers_clear_outlined, size: 18),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                padding: EdgeInsets.zero,
                onPressed: _document.layers[i].locked ||
                        (_document.layers[i].strokes.isEmpty &&
                            _document.layers[i].imageBytes == null)
                    ? null : () => _clearLayer(i),
              ),
              IconButton(
                tooltip: _document.layers[i].locked
                    ? 'Desbloquear ${_document.layers[i].name}'
                    : 'Bloquear ${_document.layers[i].name}',
                icon: Icon(_document.layers[i].locked
                    ? Icons.lock : Icons.lock_open, size: 18),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                padding: EdgeInsets.zero,
                onPressed: () => _replaceLayer(i, _document.layers[i].copyWith(
                    locked: !_document.layers[i].locked)),
              ),
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
              onPressed: _document.layers.length == 1 ? null : () => _deleteLayer(i),
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

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _dirty) _confirmExit();
      },
      child: CallbackShortcuts(
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
            if (action == 'import') _importImage();
            if (action == 'open') _openProject();
            if (action == 'openExternal') _openProject(external: true);
            if (action == 'save') _saveProject();
            if (action == 'shareProject') _shareProject();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'new', child: Text('Nuevo dibujo')),
            const PopupMenuItem(value: 'import', child: Text('Importar imagen')),
            const PopupMenuItem(value: 'open', child: Text('Abrir proyecto guardado')),
            const PopupMenuItem(value: 'openExternal', child: Text('Importar proyecto editable')),
            PopupMenuItem(value: 'save', enabled: !_saving,
                child: const Text('Guardar proyecto')),
            PopupMenuItem(value: 'shareProject', enabled: !_sharingProject,
                child: const Text('Compartir proyecto editable')),
          ],
        ),
      ]),
      drawer: compact ? Drawer(child: SafeArea(child: panel)) : null,
      body: Row(children: [
        if (!compact) panel,
        Expanded(child: Container(
          color: const Color(0xff303441),
          child: LayoutBuilder(builder: (context, constraints) {
            _viewport = constraints.biggest;
            if (!_viewInitialized && !_viewport.isEmpty) {
              _viewInitialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _centerCanvas();
              });
            }
            return Stack(children: [
              Positioned.fill(child: InteractiveViewer(
            transformationController: _transform,
            panEnabled: _tool == CanvasTool.navigate,
            scaleEnabled: true,
            minScale: 0.1, maxScale: 6,
            alignment: Alignment.topLeft,
            boundaryMargin: const EdgeInsets.all(1024),
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
                      previewColor: _color.withValues(alpha: _opacity),
                      previewWidth: _width,
                      previewErase: _tool == CanvasTool.eraser,
                      previewShape: _tool == CanvasTool.line ? StrokeShape.line
                          : _tool == CanvasTool.rectangle ? StrokeShape.rectangle
                          : _tool == CanvasTool.ellipse ? StrokeShape.ellipse
                          : StrokeShape.freehand,
                      previewFilled: _fillShapes,
                      selected: _document.selected),
                ),
              ),
            ),
              )),
              Positioned(right: 12, bottom: 12,
                child: Material(
                  color: const Color(0xdd151821),
                  borderRadius: BorderRadius.circular(12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Ajustar lienzo',
                        onPressed: _centerCanvas,
                        icon: const Icon(Icons.fit_screen)),
                    ValueListenableBuilder<Matrix4>(
                      valueListenable: _transform,
                      builder: (context, matrix, child) => Text(
                        '${(matrix.getMaxScaleOnAxis() * 100).round()} %',
                        key: const Key('canvas-zoom'),
                      ),
                    ),
                    IconButton(tooltip: 'Tamaño real (100 %)',
                        onPressed: () => _centerCanvas(actualSize: true),
                        icon: const Icon(Icons.center_focus_strong)),
                  ]),
                ),
              ),
            ]);
          }),
        )),
      ]),
        ),
      ),
    ));
  }

  Widget _toolButton(String title, IconData icon, CanvasTool tool) =>
      Builder(builder: (chipContext) => ChoiceChip(
        label: Text(title), avatar: Icon(icon, size: 18),
        selected: _tool == tool,
        onSelected: (_) {
          setState(() {
            _currentPoints.clear();
            _activePointer = null;
            _tool = tool;
          });
          if (Scaffold.of(chipContext).isDrawerOpen) {
            Navigator.of(chipContext).pop();
          }
        },
      ));
}

class CanvasArtwork extends CustomPainter {
  CanvasArtwork(this.layers, {this.preview = const [], this.previewColor = Colors.black,
    this.previewWidth = 1, this.previewErase = false,
    this.previewShape = StrokeShape.freehand, this.previewFilled = false,
    this.selected = -1});

  final List<DrawingLayer> layers;
  final List<Offset> preview;
  final Color previewColor;
  final double previewWidth;
  final bool previewErase;
  final StrokeShape previewShape;
  final bool previewFilled;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (var i = 0; i < layers.length; i++) {
      if (!layers[i].visible) continue;
      canvas.saveLayer(Offset.zero & size,
          Paint()..color = Colors.white.withValues(alpha: layers[i].opacity));
      if (layers[i].image != null) {
        paintImage(canvas: canvas, rect: Offset.zero & size,
            image: layers[i].image!, fit: BoxFit.contain);
      }
      for (final stroke in layers[i].strokes) {
        _paintStroke(canvas, stroke);
      }
      if (i == selected && preview.isNotEmpty) {
        _paintStroke(canvas, Stroke(preview, previewColor, previewWidth,
            previewErase, shape: previewShape,
            filled: previewFilled && (previewShape == StrokeShape.rectangle ||
                previewShape == StrokeShape.ellipse)));
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
      ..style = stroke.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..blendMode = stroke.erase ? BlendMode.clear : BlendMode.srcOver;
    if (stroke.shape == StrokeShape.rectangle && stroke.points.length > 1) {
      canvas.drawRect(Rect.fromPoints(stroke.points.first, stroke.points.last), paint);
      return;
    }
    if (stroke.shape == StrokeShape.ellipse && stroke.points.length > 1) {
      canvas.drawOval(Rect.fromPoints(stroke.points.first, stroke.points.last), paint);
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

Future<Color?> sampleArtworkColor(List<DrawingLayer> layers, Offset position) async {
  final width = canvasSize.width.toInt();
  final height = canvasSize.height.toInt();
  if (position.dx < 0 || position.dy < 0 ||
      position.dx >= width || position.dy >= height) {
    return null;
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  CanvasArtwork(layers).paint(canvas, canvasSize);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('No se pudo leer el color');
      final offset = (position.dy.floor() * width + position.dx.floor()) * 4;
      return Color.fromARGB(data.getUint8(offset + 3), data.getUint8(offset),
          data.getUint8(offset + 1), data.getUint8(offset + 2));
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
