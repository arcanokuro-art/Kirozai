import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirozai/main.dart';

Future<void> tapVisible(WidgetTester tester, String tooltip) async {
  final target = find.byTooltip(tooltip);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
}

void main() {
  testWidgets('layer opacity changes can be undone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    final control = find.text('Opacidad capa: 100 %');
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
    await tester.tap(find.text('50 %'));
    await tester.pumpAndSettle();
    expect(find.text('Opacidad capa: 50 %'), findsOneWidget);
    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pump();
    expect(find.text('Opacidad capa: 100 %'), findsOneWidget);
  });

  testWidgets('eyedropper reads the visible canvas color', (tester) async {
    final layers = [
      DrawingLayer('Rojo', [
        Stroke([const Offset(10, 10), const Offset(50, 50)],
            Colors.red, 2, false, shape: StrokeShape.rectangle, filled: true),
      ]),
      DrawingLayer('Azul oculto', [
        Stroke([const Offset(10, 10), const Offset(50, 50)],
            Colors.blue, 2, false, shape: StrokeShape.rectangle, filled: true),
      ], visible: false),
    ];
    await tester.runAsync(() async {
      expect((await sampleArtworkColor(layers, const Offset(30, 30)))?.toARGB32(),
          Colors.red.toARGB32());
      expect((await sampleArtworkColor(layers, const Offset(80, 80)))?.toARGB32(),
          Colors.white.toARGB32());
      final translucent = await sampleArtworkColor(
          [layers.first.copyWith(opacity: 0.5)], const Offset(30, 30));
      expect(translucent!.g, inExclusiveRange(0, 1));
      expect(await sampleArtworkColor(layers, const Offset(-1, 0)), isNull);
    });
  });

  testWidgets('stroke opacity can be changed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    final slider = find.byKey(const Key('stroke-opacity'));
    expect(tester.widget<Slider>(slider).value, 1);
    await tester.drag(slider, const Offset(-100, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, lessThan(1));
  });

  testWidgets('ellipse tool draws an undoable shape', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    await tester.tap(find.text('Elipse'));
    await tester.pump();
    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.dragFrom(center - const Offset(45, 30), const Offset(90, 60));
    await tester.pump();
    expect(tester.widget<IconButton>(find.ancestor(
      of: find.byTooltip('Deshacer'), matching: find.byType(IconButton),
    )).onPressed, isNotNull);
    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pump();
    expect(tester.widget<IconButton>(find.ancestor(
      of: find.byTooltip('Deshacer'), matching: find.byType(IconButton),
    )).onPressed, isNull);
  });

  testWidgets('shape fill can be toggled in the tools panel', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    final fill = find.widgetWithText(SwitchListTile, 'Rellenar figuras');
    expect(tester.widget<SwitchListTile>(fill).value, isFalse);
    await tester.tap(fill);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(fill).value, isTrue);
  });

  testWidgets('Android back asks before losing unsaved changes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    await tapVisible(tester, 'Agregar capa');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Cambios sin guardar'), findsOneWidget);
    expect(find.text('Guardar y salir'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Capa 2'), findsOneWidget);
  });

  testWidgets('choosing a tool closes the drawer on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const KirozaiApp());
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).drawer, isNotNull);
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    expect(tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen, isTrue);
    await tester.tap(find.text('Borrador'));
    await tester.pumpAndSettle();
    expect(tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen, isFalse);
  });

  testWidgets('file menu exposes editable project transfer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    await tester.tap(find.byTooltip('Archivo'));
    await tester.pumpAndSettle();
    expect(find.text('Importar proyecto editable'), findsOneWidget);
    expect(find.text('Compartir proyecto editable'), findsOneWidget);
  });

  test('saving replaces the prior project and leaves no temporary file', () async {
    final directory = await Directory.systemTemp.createTemp('kirozai-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/project.json');
    await file.writeAsString('old project');
    final document = DrawingDocument([
      DrawingLayer('Nueva capa', [
        Stroke([const Offset(1, 2)], Colors.blue, 4, false),
      ]),
    ], 0);
    await writeProjectAtomically(file, document);
    final restored = DrawingDocument.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    expect(restored.layers.single.name, 'Nueva capa');
    expect(restored.layers.single.strokes.single.points.single,
        const Offset(1, 2));
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  testWidgets('two fingers zoom while brush is selected without drawing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    final viewer = find.byType(InteractiveViewer);
    expect(tester.widget<InteractiveViewer>(viewer).scaleEnabled, isTrue);
    final center = tester.getCenter(viewer);
    final first = await tester.startGesture(center + const Offset(-60, 0), pointer: 1);
    final second = await tester.startGesture(center + const Offset(60, 0), pointer: 2);
    await tester.pump();
    await first.moveBy(const Offset(-70, 0));
    await second.moveBy(const Offset(70, 0));
    await tester.pump();
    expect(tester.widget<InteractiveViewer>(viewer)
        .transformationController!.value.getMaxScaleOnAxis(), greaterThan(1));
    await first.up();
    await second.up();
    await tester.pump();
    expect(tester.widget<IconButton>(find.ancestor(
      of: find.byTooltip('Deshacer'), matching: find.byType(IconButton),
    )).onPressed, isNull);
  });

  testWidgets('editor opens and supports layer creation and undo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());

    expect(find.text('Kirozai'), findsOneWidget);
    expect(find.text('Capa 1'), findsOneWidget);
    await tapVisible(tester, 'Agregar capa');
    await tester.pump();
    expect(find.text('Capa 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pump();
    expect(find.text('Capa 2'), findsNothing);
  });

  testWidgets('layers can be renamed and reordered with undo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    await tapVisible(tester, 'Agregar capa');
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('Renombrar Capa 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Renombrar Capa 2'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Boceto');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Boceto'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Bajar Boceto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bajar Boceto'));
    await tester.pump();
    final boceto = tester.getTopLeft(find.text('Boceto'));
    final base = tester.getTopLeft(find.text('Capa 1'));
    expect(boceto.dy, greaterThan(base.dy));
    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Boceto')).dy,
        lessThan(tester.getTopLeft(find.text('Capa 1')).dy));
  });

  test('editable project preserves layers, points and eraser', () {
    final original = DrawingDocument([
      DrawingLayer('Base', [
        Stroke([Offset(2, 3), Offset(5, 8)],
            const Color.fromARGB(128, 255, 0, 0), 7, false),
        Stroke([Offset(4, 6)], Colors.black, 9, true),
        Stroke([Offset(10, 12), Offset(50, 80)], Colors.blue, 2, false,
            shape: StrokeShape.rectangle),
        Stroke([Offset(6, 9), Offset(45, 60)], Colors.green, 3, false,
            shape: StrokeShape.ellipse, filled: true),
      ]),
      DrawingLayer('Oculta', [], visible: false),
      DrawingLayer('Foto', [], opacity: 0.5,
          imageBytes: Uint8List.fromList([1, 2, 3])),
    ], 0);
    final restored = DrawingDocument.fromJson(original.toJson());
    expect(restored.layers.length, 3);
    expect(restored.layers[0].strokes[0].points.last, const Offset(5, 8));
    expect(restored.layers[0].strokes[0].color.toARGB32(),
        const Color.fromARGB(128, 255, 0, 0).toARGB32());
    expect(restored.layers[0].strokes[1].erase, isTrue);
    expect(restored.layers[0].strokes[2].shape, StrokeShape.rectangle);
    expect(restored.layers[0].strokes[3].shape, StrokeShape.ellipse);
    expect(restored.layers[0].strokes[3].filled, isTrue);
    expect(restored.layers[0].strokes[2].filled, isFalse);
    expect(restored.layers[1].visible, isFalse);
    expect(restored.layers[2].imageBytes, orderedEquals([1, 2, 3]));
    expect(restored.layers[2].opacity, 0.5);
    expect(restored.layers[0].opacity, 1);
    expect(restored.selected, 0);
    expect(() => DrawingDocument.fromJson({'version': 1, 'selected': 0,
      'layers': []}), throwsFormatException);
    expect(() => DrawingDocument.fromJson({'version': 1, 'selected': 0,
      'layers': [{'name': 'Mal', 'visible': true, 'opacity': 2,
        'strokes': []}]}), throwsFormatException);
  });

  testWidgets('new drawing requires confirmation and resets layers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    await tapVisible(tester, 'Agregar capa');
    await tester.pump();
    await tester.tap(find.byTooltip('Archivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo dibujo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Capa 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Archivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo dibujo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(find.text('Capa 2'), findsNothing);
    expect(find.text('Capa 1'), findsOneWidget);
  });

  testWidgets('selected layer can be duplicated and undone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    await tapVisible(tester, 'Duplicar capa seleccionada');
    await tester.pump();
    expect(find.text('Capa 1 copia'), findsOneWidget);
    await tester.tap(find.byTooltip('Deshacer'));
    await tester.pump();
    expect(find.text('Capa 1 copia'), findsNothing);
  });

  testWidgets('desktop shortcut undoes a layer change', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    await tester.pump();
    await tapVisible(tester, 'Agregar capa');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Capa 2'), findsNothing);
  });

  testWidgets('opening a saved project warns about unsaved changes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    await tapVisible(tester, 'Agregar capa');
    await tester.pump();
    expect(find.text('Kirozai •'), findsOneWidget);
    await tester.tap(find.byTooltip('Archivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir proyecto guardado'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cambios sin guardar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Capa 2'), findsOneWidget);
  });
}
