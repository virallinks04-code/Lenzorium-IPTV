import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';
import '../models/models.dart';

enum LicenceStatus { trial, active, expired, unknown }

class LicenceState {
  LicenceState({
    required this.status,
    this.plan = '',
    this.expiresAt,
    this.trialEndsAt,
    this.offline = false,
    this.message = '',
  });

  final LicenceStatus status;
  /// 'trial', 'yearly' or 'lifetime'.
  final String plan;
  final DateTime? expiresAt;
  final DateTime? trialEndsAt;
  final bool offline;
  final String message;

  bool get canWatch => status == LicenceStatus.trial || status == LicenceStatus.active;

  int get trialDaysLeft {
    if (trialEndsAt == null) return 0;
    final h = trialEndsAt!.difference(DateTime.now()).inHours;
    return h <= 0 ? 0 : (h / 24).ceil();
  }

  Map<String, Object?> toJson() => {
        'status': status.name,
        'plan': plan,
        'expiresAt': expiresAt?.toIso8601String(),
        'trialEndsAt': trialEndsAt?.toIso8601String(),
      };

  static LicenceState fromJson(Map<String, dynamic> j, {bool offline = false}) => LicenceState(
        status: LicenceStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => LicenceStatus.unknown),
        plan: '${j['plan'] ?? ''}',
        expiresAt: j['expiresAt'] == null ? null : DateTime.tryParse('${j['expiresAt']}'),
        trialEndsAt: j['trialEndsAt'] == null ? null : DateTime.tryParse('${j['trialEndsAt']}'),
        offline: offline,
      );
}

class LicenceCheck {
  LicenceCheck(this.state, this.pushedPlaylists);
  final LicenceState state;
  /// Playlists the customer entered on the website against this device.
  final List<(String id, PlaylistSource source)> pushedPlaylists;
}

/// Talks to the Lenzorium licence server (see /server). Each install gets
/// a device ID and a short device key; the customer pays on the website
/// and enters them, and the next check unlocks the app.
class LicenceService {
  LicenceService(this._prefs, {http.Client? client}) : _client = client ?? http.Client() {
    _ensureIdentity();
  }

  final SharedPreferences _prefs;
  final http.Client _client;

  late final String deviceId;
  late final String deviceKey;

  String get activationUrl =>
      'https://${AppConfig.activationHost}/?device=${Uri.encodeQueryComponent(deviceId)}';
  String get setupUrl =>
      'https://${AppConfig.activationHost}/setup?device=${Uri.encodeQueryComponent(deviceId)}';

  void _ensureIdentity() {
    var id = _prefs.getString('lic_device_id');
    var key = _prefs.getString('lic_device_key');
    if (id == null || key == null) {
      final r = Random.secure();
      id = List.generate(6, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
      key = (100000 + r.nextInt(900000)).toString();
      _prefs.setString('lic_device_id', id);
      _prefs.setString('lic_device_key', key);
      _prefs.setInt('lic_first_run', DateTime.now().millisecondsSinceEpoch);
    }
    deviceId = id;
    deviceKey = key;
  }

  String get platform {
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    return Platform.operatingSystem;
  }

  /// Formats the 6-digit key as "482 917".
  String get deviceKeyDisplay => '${deviceKey.substring(0, 3)} ${deviceKey.substring(3)}';

  LicenceState? get cached {
    final s = _prefs.getString('lic_state');
    if (s == null) return null;
    try {
      return LicenceState.fromJson(jsonDecode(s) as Map<String, dynamic>, offline: true);
    } catch (_) {
      return null;
    }
  }

  Future<LicenceCheck> check() async {
    try {
      final res = await _client
          .post(
            Uri.parse('${AppConfig.licenceApi}/api/device/check'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'deviceId': deviceId,
              'deviceKey': deviceKey,
              'platform': platform,
              'appVersion': AppConfig.version,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw HttpException('status ${res.statusCode}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final state = LicenceState.fromJson(j);
      // Keep the server's view for use during the offline grace period.
      _prefs.setString('lic_state', jsonEncode(state.toJson()));
      _prefs.setInt('lic_last_ok', DateTime.now().millisecondsSinceEpoch);
      final pushed = <(String, PlaylistSource)>[];
      final pl = j['playlists'];
      if (pl is List) {
        for (final p in pl) {
          if (p is Map) {
            pushed.add(('${p['id']}', PlaylistSource.fromJson(p.cast<String, dynamic>())));
          }
        }
      }
      return LicenceCheck(_recompute(state), pushed);
    } catch (_) {
      return LicenceCheck(_offlineState(), const []);
    }
  }

  /// Applies expiry locally (e.g. a yearly plan that ran out while offline).
  LicenceState _recompute(LicenceState s, {bool offline = false}) {
    final now = DateTime.now();
    if (s.status == LicenceStatus.trial && s.trialEndsAt != null && now.isAfter(s.trialEndsAt!)) {
      return LicenceState(status: LicenceStatus.expired, plan: 'trial', trialEndsAt: s.trialEndsAt, offline: offline);
    }
    if (s.status == LicenceStatus.active && s.expiresAt != null && now.isAfter(s.expiresAt!)) {
      return LicenceState(status: LicenceStatus.expired, plan: s.plan, expiresAt: s.expiresAt, offline: offline);
    }
    return LicenceState(
        status: s.status, plan: s.plan, expiresAt: s.expiresAt, trialEndsAt: s.trialEndsAt, offline: offline);
  }

  LicenceState _offlineState() {
    final lastOk = _prefs.getInt('lic_last_ok');
    final c = cached;
    if (c != null && lastOk != null) {
      final since = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastOk));
      if (since <= AppConfig.offlineGrace) return _recompute(c, offline: true);
      return LicenceState(
        status: LicenceStatus.expired,
        plan: c.plan,
        offline: true,
        message: 'Connect to the internet to confirm your licence.',
      );
    }
    // Never reached the server: allow a local trial from first launch.
    final first = DateTime.fromMillisecondsSinceEpoch(
        _prefs.getInt('lic_first_run') ?? DateTime.now().millisecondsSinceEpoch);
    final ends = first.add(const Duration(days: AppConfig.trialDays));
    return _recompute(LicenceState(status: LicenceStatus.trial, plan: 'trial', trialEndsAt: ends), offline: true);
  }

  Future<void> ackPlaylists(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _client
          .post(
            Uri.parse('${AppConfig.licenceApi}/api/device/playlists/ack'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'deviceId': deviceId, 'deviceKey': deviceKey, 'ids': ids}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {/* retried on next check */}
  }
}
