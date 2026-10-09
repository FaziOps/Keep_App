import 'failures.dart';

/// Outcome of a use case or repository call: either [Success] or [Failure].
sealed class Result<T> {
  const Result();

  R fold<R>(R Function(AppFailure failure) onFailure, R Function(T value) onSuccess) => switch (this) {
    Success<T>(:final value) => onSuccess(value),
    Failure<T>(:final failure) => onFailure(failure),
  };

  T? get valueOrNull => switch (this) {
    Success<T>(:final value) => value,
    Failure<T>() => null,
  };

  AppFailure? get failureOrNull => switch (this) {
    Success<T>() => null,
    Failure<T>(:final failure) => failure,
  };

  bool get isSuccess => this is Success<T>;
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class Failure<T> extends Result<T> {
  const Failure(this.failure);
  final AppFailure failure;
}
