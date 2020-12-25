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
