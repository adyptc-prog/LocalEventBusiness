import 'package:flutter/material.dart';

import '../core/license_service.dart';
import '../l10n/tr.dart';
import '../network/event_server_runner.dart';
import '../screens/license_screen.dart';

/// Pune aplicația în spatele licenței: cât timp există o licență activă sau
/// proba de 30 de zile e în curs, arată aplicația; altfel, doar ecranul de
/// licență (cu restaurarea din backup), iar serverul localului se oprește.
///
/// Licența e reverificată de fiecare dată când aplicația revine în prim-plan,
/// ca proba sau licența expirată în timp ce aplicația stătea deschisă să fie
/// observată. Pe web (clientul din QR) nu face nimic.
class LicenseGate extends StatefulWidget {
  final Widget child;

  const LicenseGate({super.key, required this.child});

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> with WidgetsBindingObserver {
  final _license = LicenseService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _license.addListener(_onLicenseChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onLicenseChanged());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _license.removeListener(_onLicenseChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _license.refresh();
  }

  void _onLicenseChanged() {
    if (!mounted) return;
    setState(() {});
    if (!_license.canUse) {
      _stopServer();
    } else {
      _warnExpiry();
    }
  }

  Future<void> _stopServer() async {
    if (await EventServerRunner.isRunning) await EventServerRunner.stop();
  }

  Future<void> _warnExpiry() async {
    if (!await _license.shouldWarnExpiryToday() || !mounted) return;
    final days = _license.daysUntilExpiry ?? 0;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(tr('license.expiryWarning', {'days': days})),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_license.canUse) return widget.child;
    // Navigator propriu: ecranul de licență poate deschide restaurarea
    // backup-ului, fără acces la restul aplicației.
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const LicenseScreen(locked: true)),
    );
  }
}
