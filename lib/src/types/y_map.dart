import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
/**
 * @module YMap
 */

// import {
//   YEvent,
//   AbstractType,
//   typeMapDelete,
//   typeMapSet,
//   typeMapGet,
//   typeMapHas,
//   createMapIterator,
//   YMapRefID,
//   callTypeObservers,
//   transact,
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   Doc,
//   Transaction,
//   Item, // eslint-disable-line
// } from "../internals.js";

// import * as iterator from "lib0/iterator.js";

import 'package:y_crdt/src/utils/y_event.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

/**
 * @template T
 * Event that describes the changes on a YMap.
 */
class YMapEvent<T> extends YEvent {
  /**
   * @param {YMap<T>} ymap The YArray that changed.
   * @param {Transaction} transaction
   * @param {Set<any>} subs The keys that changed.
   */
  YMapEvent(YMap<T> ymap, Transaction transaction, this.keysChanged)
      : super(ymap, transaction);
  final Set<String?> keysChanged;
}

/**
 * @template T number|string|Object|Array|Uint8Array
 * A shared Map implementation.
 *
 * @extends AbstractType<YMapEvent<T>>
 * @implements {Iterable<T>}
 */
class YMap<T> extends AbstractType<YMapEvent<T>> {
  static YMap<T> create<T>() => YMap<T>();
  /**
   *
   * @param {Iterable<readonly [string, any]>=} entries - an optional iterable to initialize the YMap
   */
  YMap([Iterable<MapEntry<String, T>>? _prelimContent]) {
    if (_prelimContent == null) {
      this._prelimContent = {};
    } else {
      this._prelimContent = Map.fromEntries(_prelimContent);
    }
  }

  /**
     * @type {Map<string,any>?}
     * @private
     */
  Map<String, T>? _prelimContent;

  /**
   * Integrate this type into the Yjs instance.
   *
   * * Save this struct in the os
   * * This type is sent to other client
   * * Observer functions are fired
   *
   * @param {Doc} y The Yjs instance
   * @param {Item} item
   */
  void innerIntegrate(Doc y, Item? item) {
    super.innerIntegrate(y, item);
    /** @type {Map<string, any>} */ (this._prelimContent!)
        .forEach((key, value) {
      this.set(key, value);
    });
    this._prelimContent = null;
  }

  YMap<T> innerCopy() {
    return YMap<T>();
  }

  /**
   * @return {YMap<T>}
   */
  YMap<T> clone() {
    final map = YMap<T>();
    this.forEach((value, key, _) {
      map.set(key, value is AbstractType ? value.clone() as T : value);
    });
    return map;
  }

  /**
   * Creates YMapEvent and calls observers.
   *
   * @param {Transaction} transaction
   * @param {Set<null|string>} parentSubs Keys changed on this type. `null` if list was modified.
   */
  void innerCallObserver(Transaction transaction, Set<String?> parentSubs) {
    callTypeObservers<YMapEvent<T>>(
      this,
      transaction,
      YMapEvent<T>(this, transaction, parentSubs),
    );
  }

  /**
   * Transforms this Shared Type to a JSON object.
   *
   * @return {Object<string,T>}
   */
  Map<String, Object?> toJSON() {
    /**
     * @type {Object<string,T>}
     */
    final map = <String, Object?>{};
    this.innerMap.forEach((key, item) {
      if (!item.deleted) {
        final v = item.content.getContent()[item.length - 1] as T;
        map[key] = v is AbstractType ? v.toJSON() : v;
      }
    });
    return map;
  }

  /**
   * Returns the size of the YMap (count of key/value pairs)
   *
   * @return {number}
   */
  int get size {
    return [...createMapIterator(this.innerMap)].length;
  }

  /**
   * Returns the keys for each element in the YMap Type.
   *
   * @return {IterableIterator<string>}
   */
  Iterable<String> keys() {
    return createMapIterator(this.innerMap).map((e) => e.key);
  }

  /**
   * Returns the values for each element in the YMap Type.
   *
   * @return {IterableIterator<any>}
   */
  Iterable<T> values() {
    return createMapIterator(this.innerMap).map(
      (v) => v.value.content.getContent()[v.value.length - 1] as T,
    );
  }

  /**
   * Returns an Iterator of [key, value] pairs
   *
   * @return {IterableIterator<any>}
   */
  Iterable<MapEntry<String, T>> entries() {
    return createMapIterator(this.innerMap).map(
      /** @param {any} v */ (v) => MapEntry(
        v.key,
        v.value.content.getContent()[v.value.length - 1] as T,
      ),
    );
  }

  /**
   * Executes a provided function on once on every key-value pair.
   *
   * @param {function(T,string,YMap<T>):void} f A function to execute on every element of this YArray.
   */
  void forEach(void Function(T, String, YMap<T>) f) {
    this.innerMap.forEach((key, item) {
      if (!item.deleted) {
        f(item.content.getContent()[item.length - 1] as T, key, this);
      }
    });
  }

  /**
   * @return {IterableIterator<T>}
   */
  // [Symbol.iterator]() {
  //   return this.entries();
  // }

  /**
   * Remove a specified element from this YMap.
   *
   * @param {string} key The key of the element to remove.
   */
  void delete(String key) {
    final doc = this.doc;
    if (doc != null) {
      transact(doc, (transaction) {
        typeMapDelete(transaction, this, key);
      });
    } else {
      /** @type {Map<string, any>} */ (this._prelimContent!).remove(key);
    }
  }

  /**
   * Adds or updates an element with a specified key and value.
   *
   * @param {string} key The key of the element to add to this YMap
   * @param {T} value The value of the element to add
   */
  T set(String key, T value) {
    final doc = this.doc;
    if (doc != null) {
      transact(doc, (transaction) {
        typeMapSet(transaction, this, key, value);
      });
    } else {
      /** @type {Map<string, any>} */ (this._prelimContent!).set(key, value);
    }
    return value;
  }

  /**
   * Returns a specified element from this YMap.
   *
   * @param {string} key
   * @return {T|undefined}
   */
  T? get(String key) {
    return /** @type {any} */ (typeMapGet(this, key) as T?);
  }

  /**
   * Returns a boolean indicating whether the specified key exists or not.
   *
   * @param {string} key The key to test.
   * @return {boolean}
   */
  bool has(String key) {
    return typeMapHas(this, key);
  }

  /**
   * @param {AbstractUpdateEncoder} encoder
   */
  void innerWrite(AbstractUpdateEncoder encoder) {
    encoder.writeTypeRef(YMapRefID);
  }
}

/**
 * @param {AbstractUpdateDecoder} decoder
 *
 * @private
 * @function
 */
YMap<T> readYMap<T>(AbstractUpdateDecoder decoder) => YMap<T>();
