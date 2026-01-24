// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mikrotap/app/app.dart';

void main() {
  testWidgets('Shows login screen when signed out', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MikroTapApp()));
    // Avoid pumpAndSettle here since the splash screen has an indeterminate
    // progress indicator (continuous animation).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('MikroTap'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byIcon(Icons.login), findsOneWidget);
  });
}
