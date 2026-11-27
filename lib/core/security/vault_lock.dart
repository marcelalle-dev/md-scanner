import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/security/pin_service.dart';
import 'package:md_scanner/core/security/vault_service.dart';
import 'package:md_scanner/core/services/app_logger.dart';
import 'package:md_scanner/core/storage/settings_store.dart';

class VaultLockState extends Equatable {
  const VaultLockState({
    required this.hasPin,
    required this.unlocked,
    required this.biometricEnabled,
    required this.biometricAvailable,
  });

  final bool hasPin;
  final bool unlocked;

  /// The user allowed biometrics as a shortcut to the PIN.
  final bool biometricEnabled;
  final bool biometricAvailable;

  bool get canUseBiometrics => biometricEnabled && biometricAvailable;

  VaultLockState copyWith({
    bool? hasPin,
    bool? unlocked,
    bool? biometricEnabled,
  }) => VaultLockState(
    hasPin: hasPin ?? this.hasPin,
    unlocked: unlocked ?? this.unlocked,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    biometricAvailable: biometricAvailable,
  );

  @override
  List<Object?> get props => [
    hasPin,
    unlocked,
    biometricEnabled,
    biometricAvailable,
  ];
}

/// Lock state of the vault. It always starts locked; unlocking lasts until
/// [lock] is called (leaving the vault, app sent to the background).
class VaultLockController extends AsyncNotifier<VaultLockState> {
  static const String _biometricKey = 'security.biometric_enabled';

  PinService get _pins => ref.read(pinServiceProvider);

  @override
  Future<VaultLockState> build() async => VaultLockState(
    hasPin: await _pins.isPinSet,
    unlocked: false,
    biometricEnabled: await ref
        .read(settingsStoreProvider)
        .readBool(_biometricKey),
    biometricAvailable: await ref
        .read(biometricAuthenticatorProvider)
        .isAvailable,
  );

  void _set(VaultLockState Function(VaultLockState current) change) {
    final current = state.value;
    if (current != null) state = AsyncData(change(current));
  }

  /// Creates the PIN and opens the vault.
  Future<Result<void>> createPin(String pin) async {
    final result = await _pins.setPin(pin);
    if (result.isSuccess) {
      _set((s) => s.copyWith(hasPin: true, unlocked: true));
      ref.read(appLoggerProvider).info('security.pin_set');
    }
    return result;
  }

  Future<Result<void>> unlockWithPin(String pin) async {
    final result = await _pins.verifyPin(pin);
    if (result.isSuccess) {
      _set((s) => s.copyWith(unlocked: true));
    } else {
      ref.read(appLoggerProvider).warning('security.unlock_failed');
    }
    return result;
  }

  Future<Result<void>> unlockWithBiometrics(String reason) async {
    final result = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(reason);
    if (result.isSuccess) _set((s) => s.copyWith(unlocked: true));
    return result;
  }

  /// Locks the vault and deletes the temporary clear copies.
  Future<void> lock() async {
    if (state.value?.unlocked ?? false) {
      _set((s) => s.copyWith(unlocked: false));
    }
    await ref.read(vaultServiceProvider).purgeDecrypted();
  }

  Future<void> setBiometricEnabled({required bool enabled}) async {
    await ref
        .read(settingsStoreProvider)
        .writeBool(_biometricKey, value: enabled);
    _set((s) => s.copyWith(biometricEnabled: enabled));
  }

  Future<Result<void>> removePin(String currentPin) async {
    final result = await _pins.removePin(currentPin);
    if (result.isSuccess) {
      await ref.read(vaultServiceProvider).purgeDecrypted();
      _set((s) => s.copyWith(hasPin: false, unlocked: false));
    }
    return result;
  }
}

final vaultLockProvider =
    AsyncNotifierProvider<VaultLockController, VaultLockState>(
      VaultLockController.new,
    );
