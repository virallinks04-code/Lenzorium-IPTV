import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/config.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../services/licence_service.dart';
import '../state/app_state.dart';
import '../widgets/brand.dart';
import '../widgets/focusable.dart';
import 'splash_screen.dart';

/// Device ID, device key, QR to the activation page and trial status.
/// Also reachable from Settings › Licence ([fromSettings]).
class ActivateScreen extends StatefulWidget {
  const ActivateScreen({super.key, this.fromSettings = false});
  final bool fromSettings;
  @override
  State<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends State<ActivateScreen> {
  Timer? _poll;
  bool _checking = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().settings.prefs.setBool('seen_activate', true);
    // Unlocks by itself within seconds of payment.
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _check(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    final app = context.read<AppState>();
    final before = app.licenceState.status;
    setState(() => _checking = true);
    await app.checkLicence();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (!silent) {
        _note = app.licenceState.status == LicenceStatus.active
            ? 'Activated. Thank you!'
            : app.licenceState.offline
                ? 'Could not reach the activation server. Check your internet connection.'
                : 'Not activated yet. It can take a few seconds after payment.';
      }
    });
    if (app.licenceState.status == LicenceStatus.active && before != LicenceStatus.active) {
      _continue();
    }
  }

  void _continue() {
    if (widget.fromSettings) {
      Navigator.of(context).maybePop();
    } else {
      routeAfterLicence(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lic = app.licenceState;
    final compact = isCompact(context);

    final status = switch (lic.status) {
      LicenceStatus.active => lic.plan == 'lifetime'
          ? 'Activated · Lifetime'
          : 'Activated${lic.expiresAt != null ? ' · until ${dateLong(lic.expiresAt!)}' : ''}',
      LicenceStatus.trial => 'Free trial · ${lic.trialDaysLeft} ${lic.trialDaysLeft == 1 ? 'day' : 'days'} left',
      LicenceStatus.expired => lic.plan == 'trial' ? 'Free trial ended' : 'Licence expired',
      LicenceStatus.unknown => 'Checking…',
    };
    final dot = switch (lic.status) {
      LicenceStatus.active => const Color(0xFF3CCB7F),
      LicenceStatus.trial => LzColors.amber,
      _ => const Color(0xFFFF6B6B),
    };

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(lic.status == LicenceStatus.active ? 'This device is activated' : 'Activate this device', style: headline(compact ? 30 : 44)),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Go to '),
            const TextSpan(text: AppConfig.activationHost, style: TextStyle(color: LzColors.text, fontWeight: FontWeight.w600)),
            const TextSpan(text: ' on your phone or computer, enter the device ID and key below, and this device unlocks within seconds. No account needed here.'),
          ]),
          style: const TextStyle(fontSize: 18, height: 1.5, color: LzColors.muted),
        ),
        if (lic.message.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(lic.message, style: const TextStyle(color: LzColors.amber, fontSize: 16)),
        ],
        const SizedBox(height: 26),
        Wrap(spacing: 16, runSpacing: 16, children: [
          _IdBox(label: 'Device ID', value: app.licence.deviceId),
          _IdBox(label: 'Device key', value: app.licence.deviceKeyDisplay),
        ]),
        const SizedBox(height: 16),
        const Wrap(spacing: 16, runSpacing: 12, children: [
          _PlanBox(name: 'Yearly · 1 device', price: '[PRICE]'),
          _PlanBox(name: 'Lifetime · 1 device', price: '[PRICE]'),
        ]),
        const SizedBox(height: 26),
        Wrap(spacing: 16, runSpacing: 12, children: [
          if (lic.canWatch)
            LzButton(
              label: lic.status == LicenceStatus.active ? 'Continue' : 'Continue trial',
              kind: LzButtonKind.primary,
              autofocus: true,
              onPressed: _continue,
            ),
          LzButton(
            label: _checking ? 'Checking…' : 'I’ve paid — check now',
            autofocus: !lic.canWatch,
            kind: lic.canWatch ? LzButtonKind.secondary : LzButtonKind.primary,
            onPressed: _checking ? null : () => _check(),
          ),
        ]),
        if (_note != null) ...[
          const SizedBox(height: 14),
          Text(_note!, style: const TextStyle(fontSize: 16, color: LzColors.textSoft)),
        ],
      ],
    );

    final qr = Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: QrImageView(data: app.licence.activationUrl, size: compact ? 180 : 260, backgroundColor: Colors.white),
      ),
      const SizedBox(height: 16),
      const Text('Scan to open the activation page\nwith this device already filled in',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.5, color: LzColors.muted)),
    ]);

    return BackHandler(
      onBack: widget.fromSettings ? null : () {},
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 72, vertical: compact ? 20 : 52),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              BrandBar(
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: LzColors.surface2, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Text(status, style: const TextStyle(fontSize: 15)),
                  ]),
                ),
              ),
              const SizedBox(height: 36),
              if (compact) ...[info, const SizedBox(height: 32), Center(child: qr)]
              else
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: info),
                  const SizedBox(width: 64),
                  qr,
                ]),
              const SizedBox(height: 36),
              const ContentNotice(),
            ]),
          ),
        ),
      ),
    );
  }
}

class _IdBox extends StatelessWidget {
  const _IdBox({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: LzColors.surface,
          border: Border.all(color: LzColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 14, letterSpacing: 1.1, color: LzColors.muted)),
          const SizedBox(height: 8),
          SelectableText(value,
              style: const TextStyle(fontSize: 30, fontFamily: 'monospace', letterSpacing: 1.5, fontWeight: FontWeight.w500)),
        ]),
      );
}

class _PlanBox extends StatelessWidget {
  const _PlanBox({required this.name, required this.price});
  final String name;
  final String price;
  @override
  Widget build(BuildContext context) => Container(
        width: 290,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(color: LzColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: Text(name, style: const TextStyle(fontSize: 16))),
          Text(price, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
      );
}
