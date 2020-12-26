// TODO: Put public facing types in this file.

import 'package:logger/logger.dart';

/// Checks if you are awesome. Spoiler: you are.
class Awesome {
  bool get isAwesome => true;
}

extension SetterMap<K, V> on Map<K, V> {
  void set(K key, V value) {
    this[key] = value;
  }

  V? get(K key) {
    return this[key];
  }
}

extension MapIndex<V> on Iterable<V> {
  Iterable<O> mapIndex<O>(O Function(V value, int index) f) {
    var _i = 0;
    return this.map((e) => f(e, _i++));
  }
}

final logger = Logger();

class Pair<L, R> {
  final L left;
  final R right;

  Pair(this.left, this.right);
}

abstract class Either<L, R> {
  const Either._();

  const factory Either.left(
    L value,
  ) = _Left;
  const factory Either.right(
    R value,
  ) = _Right;

  T when<T>({
    required T Function(L value) left,
    required T Function(R value) right,
  }) {
    final v = this;
    if (v is _Left<L, R>) return left(v.value);
    if (v is _Right<L, R>) return right(v.value);
    throw "";
  }

  T? maybeWhen<T>({
    T Function()? orElse,
    T Function(L value)? left,
    T Function(R value)? right,
  }) {
    final v = this;
    if (v is _Left<L, R>) return left != null ? left(v.value) : orElse?.call();
    if (v is _Right<L, R>)
      return right != null ? right(v.value) : orElse?.call();
    throw "";
  }

  T map<T>({
    required T Function(_Left value) left,
    required T Function(_Right value) right,
  }) {
    final v = this;
    if (v is _Left<L, R>) return left(v);
    if (v is _Right<L, R>) return right(v);
    throw "";
  }

  T? maybeMap<T>({
    T Function()? orElse,
    T Function(_Left value)? left,
    T Function(_Right value)? right,
  }) {
    final v = this;
    if (v is _Left<L, R>) return left != null ? left(v) : orElse?.call();
    if (v is _Right<L, R>) return right != null ? right(v) : orElse?.call();
    throw "";
  }
}

class _Left<L, R> extends Either<L, R> {
  final L value;

  const _Left(
    this.value,
  ) : super._();
}

class _Right<L, R> extends Either<L, R> {
  final R value;

  const _Right(
    this.value,
  ) : super._();
}
