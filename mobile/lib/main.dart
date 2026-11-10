import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/secure_store.dart';
import 'state/providers.dart';
import 'ui/app_shell.dart';
import 'ui/screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Palette.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  final store = await SecureStore.open();
  final container = ProviderContainer(
    overrides: [storeProvider.overrideWithValue(store)],
  );
  await container.read(authProvider).init();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const JeevanApp(),
    ),
  );
}

class JeevanApp extends ConsumerWidget {
  const JeevanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionProvider);
    final session = sessionAsync.valueOrNull ?? ref.read(authProvider).session;

    return MaterialApp(
      title: 'JeevanCare',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: session == null ? const LoginScreen() : const AppShell(),
    );
  }
}
