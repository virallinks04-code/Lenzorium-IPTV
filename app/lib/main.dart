import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/app_state.dart';
import 'state/playback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final app = await AppState.create();
  final playback = PlaybackController(app.settings);
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider.value(value: app.settings),
      ChangeNotifierProvider.value(value: playback),
    ],
    child: const LenzoriumApp(),
  ));
}
