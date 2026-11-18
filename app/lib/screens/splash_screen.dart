import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../services/licence_service.dart';
import '../state/app_state.dart';
import '../widgets/brand.dart';
import 'activate_screen.dart';
import 'add_playlist_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final app = context.read<AppState>();
    await Future.wait([app.checkLicence(), Future.delayed(const Duration(milliseconds: 1200))]);
    if (!mounted) return;
    routeAfterLicence(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const LzLogo(size: 112),
            const SizedBox(height: 28),
            Text(AppConfig.appName, style: headline(52)),
            const SizedBox(height: 8),
            const Text('by ${AppConfig.company}', style: TextStyle(fontSize: 18, color: LzColors.muted)),
            const SizedBox(height: 44),
            const SizedBox(
              width: 220,
              child: LinearProgressIndicator(minHeight: 4, color: LzColors.accent, backgroundColor: LzColors.surface2),
            ),
            const SizedBox(height: 12),
            const Text('Checking licence…', style: TextStyle(fontSize: 15, color: LzColors.muted)),
          ]),
        ),
        const Positioned(
          left: 48,
          right: 48,
          bottom: 32,
          child: Row(children: [
            Text('Version ${AppConfig.version}', style: TextStyle(fontSize: 14, color: LzColors.faint)),
            Spacer(),
            Flexible(child: ContentNotice()),
          ]),
        ),
      ]),
    );
  }
}

/// Decides where a customer goes after the licence check:
/// Activate → Add playlist → Home.
void routeAfterLicence(BuildContext context) {
  final app = context.read<AppState>();
  final lic = app.licenceState;
  if (!lic.canWatch || (lic.status == LicenceStatus.trial && !app.hasPlaylist && _firstRun(app))) {
    replaceAll(context, const ActivateScreen());
  } else if (!app.hasPlaylist) {
    replaceAll(context, const AddPlaylistScreen(firstRun: true));
  } else {
    unawaited(app.refreshEpgIfStale());
    replaceAll(context, const HomeScreen());
  }
}

/// Show the Activate screen once on first launch even during the trial,
/// so customers see their device ID and how to buy.
bool _firstRun(AppState app) {
  final seen = app.settings.prefs.getBool('seen_activate') ?? false;
  return !seen;
}
