import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';
import '../presentation/providers/theme_provider.dart';

class MikroTapApp extends ConsumerWidget {
  const MikroTapApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Watch the provider to trigger rebuilds on state change
    ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    return MaterialApp.router(
      title: 'MikroTap',
      debugShowCheckedModeBanner: false,
      theme: MikroTapTheme.light,
      darkTheme: MikroTapTheme.dark,
      themeMode: themeNotifier.themeMode,
      routerConfig: router,
    );
  }
}
