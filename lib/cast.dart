import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

import 'l10n.dart';
import 'theme.dart';

/// Google Cast (Chromecast) helpers on top of flutter_chrome_cast.
class Cast {
  static bool ready = false;

  static Future<void> init() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    try {
      const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
      final GoogleCastOptions options = Platform.isIOS
          ? IOSGoogleCastOptions(GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId))
          : GoogleCastOptionsAndroid(appId: appId);
      await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      ready = true;
    } catch (_) {
      ready = false;
    }
  }

  static bool get connected => GoogleCastSessionManager.instance.connectionState == GoogleCastConnectState.connected;
  static String get deviceName => GoogleCastSessionManager.instance.currentSession?.device?.friendlyName ?? '';

  static String contentTypeFor(String url) {
    final e = url.split('?').first.split('.').last.toLowerCase();
    switch (e) {
      case 'm3u8':
        return 'application/x-mpegURL';
      case 'mkv':
        return 'video/x-matroska';
      case 'ts':
        return 'video/mp2t';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }

  /// Connects to [device] (waits up to 15 s) and plays [url] there.
  static Future<bool> play(
    GoogleCastDevice device, {
    required String url,
    required String title,
    String? subtitle,
    String? image,
    bool live = false,
    Duration start = Duration.zero,
  }) async {
    final sm = GoogleCastSessionManager.instance;
    if (!connected || sm.currentSession?.device?.deviceID != device.deviceID) {
      await sm.startSessionWithDevice(device);
      final ok = await sm.currentSessionStream
          .firstWhere((s) => s?.connectionState == GoogleCastConnectState.connected)
          .timeout(const Duration(seconds: 15), onTimeout: () => null);
      if (ok == null) return false;
    }
    final info = GoogleCastMediaInformation(
      contentId: url,
      contentUrl: Uri.parse(url),
      streamType: live ? CastMediaStreamType.live : CastMediaStreamType.buffered,
      contentType: contentTypeFor(url),
      metadata: GoogleCastMovieMediaMetadata(
        title: title,
        subtitle: subtitle,
        images: [if (image != null && image.startsWith('http')) GoogleCastImage(url: Uri.parse(image))],
      ),
    );
    await GoogleCastRemoteMediaClient.instance.loadMedia(info, autoPlay: true, playPosition: live ? Duration.zero : start);
    return true;
  }

  static Future<void> stop() async {
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    } catch (_) {}
  }

  static Future<void> togglePlay() async {
    final st = GoogleCastRemoteMediaClient.instance.mediaStatus;
    if (st?.playerState == CastMediaPlayerState.playing) {
      await GoogleCastRemoteMediaClient.instance.pause();
    } else {
      await GoogleCastRemoteMediaClient.instance.play();
    }
  }

  static Duration get position => GoogleCastRemoteMediaClient.instance.playerPosition;
}

/// Bottom sheet listing Chromecast devices on the Wi-Fi. Returns the chosen device.
Future<GoogleCastDevice?> pickCastDevice(BuildContext context) async {
  try {
    GoogleCastDiscoveryManager.instance.startDiscovery();
  } catch (_) {}
  final d = await showModalBottomSheet<GoogleCastDevice>(
    context: context,
    backgroundColor: C.surface,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: 320,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tr('cast_tv'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: StreamBuilder<List<GoogleCastDevice>>(
              stream: GoogleCastDiscoveryManager.instance.devicesStream,
              builder: (ctx, snap) {
                final list = snap.data ?? const <GoogleCastDevice>[];
                if (list.isEmpty) {
                  return _Searching();
                }
                return ListView(children: [
                  for (final dev in list)
                    ListTile(
                      leading: const Icon(Icons.cast, color: C.gold),
                      title: Text(dev.friendlyName),
                      subtitle: dev.modelName != null ? Text(dev.modelName!, style: const TextStyle(color: C.dimmer)) : null,
                      onTap: () => Navigator.pop(ctx, dev),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
    ),
  );
  try {
    GoogleCastDiscoveryManager.instance.stopDiscovery();
  } catch (_) {}
  return d;
}

class _Searching extends StatefulWidget {
  @override
  State<_Searching> createState() => _SearchingState();
}

class _SearchingState extends State<_Searching> {
  bool _long = false;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _long = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (!_long) const CircularProgressIndicator(color: C.gold) else const Icon(Icons.cast, size: 40, color: C.dimmer),
          const SizedBox(height: 16),
          Text(tr(_long ? 'cast_none' : 'cast_searching'), textAlign: TextAlign.center, style: const TextStyle(color: C.dim)),
        ]),
      );
}
