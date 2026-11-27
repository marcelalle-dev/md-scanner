import 'dart:async';
import 'dart:io';

import 'package:md_scanner/core/errors/failure.dart';

/// Outcome of an operation that can fail in an expected way.
///
/// Pattern-match on it:
/// ```dart
/// switch (result) {
///   case Success(:final value): ...
///   case Err(:final failure): ...
/// }
/// ```
sealed class Result<T> {
  const Result();

  const factory Result.success(T value) = Success<T>;
  const factory Result.failure(Failure failure) = Err<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Err<T>;

  T? get valueOrNull => switch (this) {
    Success<T>(:final value) => value,
    Err<T>() => null,
  };

  Failure? get failureOrNull => switch (this) {
    Success<T>() => null,
    Err<T>(:final failure) => failure,
  };

  R when<R>({
    required R Function(T value) success,
    required R Function(Failure failure) failure,
  }) => switch (this) {
    Success<T>(:final value) => success(value),
    Err<T>(failure: final f) => failure(f),
  };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Success<T>(:final value) => Success<R>(transform(value)),
    Err<T>(:final failure) => Err<R>(failure),
  };

  Future<Result<R>> andThen<R>(
    Future<Result<R>> Function(T value) next,
  ) async => switch (this) {
    Success<T>(:final value) => await next(value),
    Err<T>(:final failure) => Err<R>(failure),
  };
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Success<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Success, value);

  @override
  String toString() => 'Success($value)';
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) => other is Err<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}

/// Thrown inside a [guard] body to abort with a specific [Failure].
class FailureException implements Exception {
  const FailureException(this.failure);

  final Failure failure;

  @override
  String toString() => 'FailureException($failure)';
}

const int _errorNoSpaceLeftPosix = 28;
const int _errorDiskFullWindows = 112;

/// Translates low-level exceptions into a [Failure].
///
/// Only the exception *type* reaches [Failure.debugMessage]: exception messages
/// often embed file names or document content, which must stay out of logs.
Failure failureFromError(Object error) {
  if (error is FailureException) return error.failure;
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    if (code == _errorNoSpaceLeftPosix || code == _errorDiskFullWindows) {
      return const StorageFailure(StorageFailureKind.insufficientSpace);
    }
    if (error is PathNotFoundException) {
      return const StorageFailure(StorageFailureKind.notFound);
    }
    return StorageFailure(
      StorageFailureKind.writeError,
      debugMessage: 'FileSystemException(os=$code)',
    );
  }
  if (error is TimeoutException) {
    return const NetworkFailure(NetworkFailureKind.timeout);
  }
  if (error is SocketException) {
    return const NetworkFailure(NetworkFailureKind.offline);
  }
  return UnexpectedFailure(debugMessage: error.runtimeType.toString());
}

/// Runs [body] and converts any thrown error into an [Err].
///
/// [onError] lets a caller map domain-specific exceptions first; returning
/// `null` falls back to [failureFromError].
Future<Result<T>> guard<T>(
  Future<T> Function() body, {
  Failure? Function(Object error, StackTrace stackTrace)? onError,
}) async {
  try {
    return Success<T>(await body());
  } catch (error, stackTrace) {
    final mapped = onError?.call(error, stackTrace);
    return Err<T>(mapped ?? failureFromError(error));
  }
}
