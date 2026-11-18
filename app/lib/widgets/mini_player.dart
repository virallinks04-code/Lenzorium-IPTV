import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../screens/player_screen.dart';
import '../state/playback.dart';

/// Windows mini-player: keeps the stream playing in a corner while the
/// customer browses. Click to return full screen.
class MiniPlayerOverlay extends StatelessWidget {
  const MiniPlayerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final pb = context.watch<PlaybackController>();
    if (!pb.mini || !pb.isActive) return const SizedBox.shrink();
    final item = pb.current!;
    return Positioned(
      right: 24,
      bottom: 24,
      width: 384,
      child: Material(
        color: LzColors.surface2,
        elevation: 12,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: GestureDetector(
              onTap: () => _expand(),
              child: Video(controller: pb.video, controls: NoVideoControls),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(children: [
              Expanded(
                child: Text(item.isLive ? '${item.subtitle} · ${item.title}' : item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              IconButton(onPressed: _expand, icon: const Icon(Icons.open_in_full, size: 20)),
              IconButton(onPressed: () => pb.stop(), icon: const Icon(Icons.close, size: 20)),
            ]),
          ),
        ]),
      ),
    );
  }

  void _expand() {
    final ctx = navKey.currentContext;
    if (ctx != null) push(ctx, const PlayerScreen());
  }
}
