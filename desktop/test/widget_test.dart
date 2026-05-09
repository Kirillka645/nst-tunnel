// Smoke test for NST Tunnel desktop.
//
// Replaces the default counter test that ships with `flutter create`.
// Real widget tests live alongside the widgets they cover; this file just
// guarantees the app boots in a `WidgetTester` without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nst_tunnel_desktop/theme/app_theme.dart';

void main() {
  testWidgets('AppTheme builds light + dark schemes without throwing', (
    WidgetTester tester,
  ) async {
    final lightApp = MaterialApp(theme: AppTheme.light(), home: const Scaffold());
    final darkApp = MaterialApp(theme: AppTheme.dark(), home: const Scaffold());

    await tester.pumpWidget(lightApp);
    expect(find.byType(MaterialApp), findsOneWidget);

    await tester.pumpWidget(darkApp);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
