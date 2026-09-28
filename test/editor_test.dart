import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirozai/main.dart';

void main() {
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
    await tester.tap(find.byTooltip('Agregar capa'));
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
    await tester.tap(find.byTooltip('Agregar capa'));
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
        Stroke([Offset(2, 3), Offset(5, 8)], Colors.red, 7, false),
        Stroke([Offset(4, 6)], Colors.black, 9, true),
        Stroke([Offset(10, 12), Offset(50, 80)], Colors.blue, 2, false,
            shape: StrokeShape.rectangle),
      ]),
      DrawingLayer('Oculta', [], visible: false),
      DrawingLayer('Foto', [], imageBytes: Uint8List.fromList([1, 2, 3])),
    ], 0);
    final restored = DrawingDocument.fromJson(original.toJson());
    expect(restored.layers.length, 3);
    expect(restored.layers[0].strokes[0].points.last, const Offset(5, 8));
    expect(restored.layers[0].strokes[0].color.toARGB32(),
        Colors.red.toARGB32());
    expect(restored.layers[0].strokes[1].erase, isTrue);
    expect(restored.layers[0].strokes[2].shape, StrokeShape.rectangle);
    expect(restored.layers[1].visible, isFalse);
    expect(restored.layers[2].imageBytes, orderedEquals([1, 2, 3]));
    expect(restored.selected, 0);
    expect(() => DrawingDocument.fromJson({'version': 1, 'selected': 0,
      'layers': []}), throwsFormatException);
  });

  testWidgets('new drawing requires confirmation and resets layers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KirozaiApp());
    await tester.tap(find.byTooltip('Agregar capa'));
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
    await tester.tap(find.byTooltip('Duplicar capa seleccionada'));
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
    await tester.tap(find.byTooltip('Agregar capa'));
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
    await tester.tap(find.byTooltip('Agregar capa'));
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
