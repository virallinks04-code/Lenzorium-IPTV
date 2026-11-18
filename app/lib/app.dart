import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'screens/splash_screen.dart';
import 'services/settings_store.dart';
import 'widgets/mini_player.dart';

final navKey = GlobalKey<NavigatorState>();

class LenzoriumApp extends StatelessWidget {
  const LenzoriumApp({super.key});

  @override
  Widget build(BuildContext context) {
    final black = context.select<SettingsStore, bool>((s) => s.theme == 'black');
    final theme = buildTheme();
    return MaterialApp(
      title: AppConfig.appName,
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      theme: black ? theme.copyWith(scaffoldBackgroundColor: Colors.black) : theme,
      // D-pad centre / remote OK activates focused widgets everywhere.
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
      },
      builder: (context, child) => Stack(children: [
        if (child != null) child,
        const MiniPlayerOverlay(),
      ]),
      home: const SplashScreen(),
    );
  }
}
