import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/core/security/secure_key_store.dart';

/// Cost parameters of the Argon2id hash protecting the PIN.
class PinHashParameters {
  const PinHashParameters({
    this.memoryKib = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  /// OWASP's minimum recommendation for Argon2id (19 MiB, 2 passes).
  static const PinHashParameters standard = PinHashParameters();

  final int memoryKib;
  final int iterations;
  final int parallelism;
}

/// Sets and checks the vault PIN.
///
/// The PIN itself is never stored: only an Argon2id hash with a random salt,
/// inside the secure key store. Failed attempts are throttled, and the
/// throttle survives an app restart.
class PinService {
  PinService(
    this._store, {
    this.parameters = PinHashParameters.standard,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final SecureKeyStore _store;
  final PinHashParameters parameters;
  final DateTime Function() _clock;
  final Random _random;

  static const String _hashKey = 'security.pin.v1';
  static const String _throttleKey = 'security.pin.throttle';

  static const int freeAttempts = 5;
  static const Duration firstLockout = Duration(seconds: 30);
  static const Duration maxLockout = Duration(minutes: 15);

  static final RegExp _format = RegExp(r'^\d{4,8}$');

  static bool isValidFormat(String pin) => _format.hasMatch(pin);

  Future<bool> get isPinSet async => await _store.read(_hashKey) != null;

  Future<Result<void>> setPin(String pin) => guard(() async {
    if (!isValidFormat(pin)) {
      throw const FailureException(ValidationFailure('pin_format'));
    }
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final hash = await _hash(pin, salt, parameters);
    await _store.write(
      _hashKey,
      jsonEncode({
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
        'memory': parameters.memoryKib,
        'iterations': parameters.iterations,
        'parallelism': parameters.parallelism,
      }),
    );
    await _store.delete(_throttleKey);
  });

  /// Succeeds only with the right PIN. Fails with `wrongPin`, or with
  /// `lockedOut` (and the remaining delay) after too many attempts.
  Future<Result<void>> verifyPin(String pin) => guard(() async {
    final stored = await _store.read(_hashKey);
    if (stored == null) {
      throw const FailureException(
        SecurityFailure(SecurityFailureKind.pinNotSet),
      );
    }
    final throttle = await _readThrottle();
    final now = _clock();
    final lockedUntil = throttle.lockedUntil;
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      throw FailureException(
        SecurityFailure(
          SecurityFailureKind.lockedOut,
          retryAfter: lockedUntil.difference(now),
        ),
      );
    }

    final record = jsonDecode(stored) as Map<String, dynamic>;
    final expected = base64Decode(record['hash'] as String);
    final actual = await _hash(
      pin,
      base64Decode(record['salt'] as String),
      PinHashParameters(
        memoryKib: record['memory'] as int,
        iterations: record['iterations'] as int,
        parallelism: record['parallelism'] as int,
      ),
    );
    if (_constantTimeEquals(expected, actual)) {
      await _store.delete(_throttleKey);
      return;
    }

    final failures = throttle.failures + 1;
    DateTime? until;
    if (failures >= freeAttempts) {
      final doublings = min(failures - freeAttempts, 10);
      final seconds = min(
        firstLockout.inSeconds * (1 << doublings),
        maxLockout.inSeconds,
      );
      until = now.add(Duration(seconds: seconds));
    }
    await _store.write(
      _throttleKey,
      jsonEncode({
        'failures': failures,
        'until': until?.toUtc().millisecondsSinceEpoch,
      }),
    );
    throw FailureException(
      until == null
          ? const SecurityFailure(SecurityFailureKind.wrongPin)
          : SecurityFailure(
              SecurityFailureKind.lockedOut,
              retryAfter: until.difference(now),
            ),
    );
  });

  /// Removes the PIN after checking [currentPin].
  Future<Result<void>> removePin(String currentPin) async {
    final verified = await verifyPin(currentPin);
    if (verified.isFailure) return verified;
    return guard(() async {
      await _store.delete(_hashKey);
      await _store.delete(_throttleKey);
    });
  }

  Future<({int failures, DateTime? lockedUntil})> _readThrottle() async {
    final stored = await _store.read(_throttleKey);
    if (stored == null) return (failures: 0, lockedUntil: null);
    final record = jsonDecode(stored) as Map<String, dynamic>;
    final until = record['until'] as int?;
    return (
      failures: record['failures'] as int,
      lockedUntil: until == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(until, isUtc: true),
    );
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  /// Argon2id is memory-hard on purpose: it runs off the UI thread.
  static Future<List<int>> _hash(
    String pin,
    List<int> salt,
    PinHashParameters parameters,
  ) {
    final memory = parameters.memoryKib;
    final iterations = parameters.iterations;
    final parallelism = parameters.parallelism;
    return Isolate.run(() async {
      final algorithm = Argon2id(
        parallelism: parallelism,
        memory: memory,
        iterations: iterations,
        hashLength: 32,
      );
      final key = await algorithm.deriveKey(
        secretKey: SecretKey(utf8.encode(pin)),
        nonce: salt,
      );
      return key.extractBytes();
    });
  }
}

final pinServiceProvider = Provider<PinService>(
  (ref) => PinService(ref.watch(secureKeyStoreProvider)),
);
