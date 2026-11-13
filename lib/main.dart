import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'push.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'state.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await Push.init(state, navigatorKey);
  await state.boot();
  runApp(AppScope(state: state, child: const SribeesAiApp()));
}

class SribeesAiApp extends StatelessWidget {
  const SribeesAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    const seed = Color(0xFFD99A00);
    return MaterialApp(
      title: 'SriBees AI',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: s.locale,
      supportedLocales: const [Locale('en'), Locale('si')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: s.loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : s.me == null
              ? const LoginScreen()
              : const HomeScreen(),
    );
  }
}
