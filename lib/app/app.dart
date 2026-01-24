import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class MikroTapApp extends ConsumerWidget {
  const MikroTapApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'MikroTap',
      theme: MikroTapTheme.light,
      darkTheme: MikroTapTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}

