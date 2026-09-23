import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirozai/main.dart';

void main() {
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
}
