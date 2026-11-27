import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/app/theme/app_tokens.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/l10n/failure_messages.dart';
import 'package:md_scanner/core/security/pin_service.dart';
import 'package:md_scanner/core/security/vault_service.dart';
import 'package:md_scanner/core/storage/settings_store.dart';
import 'package:md_scanner/features/security/l10n/generated/security_localizations.dart';

/// Whether the whole app asks for the PIN at launch and when it comes back
/// from the background. Off by default; only meaningful once a PIN exists.
class AppLockSetting extends AsyncNotifier<bool> {
  static const String _key = 'security.lock_whole_app';

  @override
  Future<bool> build() => ref.read(settingsStoreProvider).readBool(_key);

  Future<void> set({required bool enabled}) async {
    await ref.read(settingsStoreProvider).writeBool(_key, value: enabled);
    state = AsyncData(enabled);
  }
}

final appLockSettingProvider = AsyncNotifierProvider<AppLockSetting, bool>(
  AppLockSetting.new,
);

/// Covers the app with a PIN screen when whole-app locking is enabled.
///
/// Placed above the navigator (`MaterialApp.builder`), so no screen can be
/// reached or seen until the PIN or biometrics unlock it.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  final TextEditingController _pin = TextEditingController();

  /// Null until the setting is known: the app stays hidden meanwhile.
  bool? _locked;
  bool _busy = false;
  bool _biometrics = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _evaluate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pin.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _locked == false) _evaluate();
  }

  /// Locks when the setting is on and a PIN exists.
  Future<void> _evaluate() async {
    var locked = false;
    var biometrics = false;
    try {
      final enabled = await ref.read(appLockSettingProvider.future);
      if (enabled && await ref.read(pinServiceProvider).isPinSet) {
        locked = true;
        biometrics = await ref.read(biometricAuthenticatorProvider).isAvailable;
      }
    } on Exception {
      // Without a readable setting or key store there is nothing to guard.
      locked = false;
    }
    if (mounted) {
      setState(() {
        _locked = locked;
        _biometrics = biometrics;
      });
    }
  }

  Future<void> _attempt(Future<Result<void>> Function() unlock) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await unlock();
    if (!mounted) return;
    _pin.clear();
    setState(() {
      _busy = false;
      switch (result) {
        case Success():
          _locked = false;
        case Err(:final failure):
          _error = failureMessage(context, failure);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;
    if (locked == false) return widget.child;
    if (locked == null) {
      return ColoredBox(color: Theme.of(context).colorScheme.surface);
    }

    final l10n = SecurityLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.appLockTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _pin,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  onSubmitted: (_) => _attempt(
                    () => ref.read(pinServiceProvider).verifyPin(_pin.text),
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.vaultPin,
                    errorText: _error,
                    errorMaxLines: 3,
                    prefixIcon: const Icon(Icons.pin_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _attempt(
                          () =>
                              ref.read(pinServiceProvider).verifyPin(_pin.text),
                        ),
                  child: Text(l10n.vaultUnlock),
                ),
                if (_biometrics) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _attempt(
                            () => ref
                                .read(biometricAuthenticatorProvider)
                                .authenticate(l10n.vaultBiometricReason),
                          ),
                    icon: const Icon(Icons.fingerprint),
                    label: Text(l10n.vaultUseBiometrics),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
