import 'dart:collection';

import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
/**
 * @module YArray
 */

// import {
//   YEvent,
//   AbstractType,
//   typeListGet,
//   typeListToArray,
//   typeListForEach,
//   typeListCreateIterator,
//   typeListInsertGenerics,
//   typeListDelete,
//   typeListMap,
//   YArrayRefID,
//   callTypeObservers,
//   transact,
//   ArraySearchMarker,
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   Doc,
//   Transaction,
//   Item, // eslint-disable-line
// } from "../internals.js";
// import { typeListSlice } from "./AbstractType.js";

import 'package:y_crdt/src/utils/y_event.dart';

/**
 * Event that describes the changes on a YArray
 * @template T
 */
class YArrayEvent<T> extends YEvent {
  /**
   * @param {YList<T>} yarray The changed type
   * @param {Transaction} transaction The transaction object
   */
  YArrayEvent(YArray<T> target, Transaction transaction)
      : _transaction = transaction,
        super(target, transaction);

  Transaction _transaction;
}

/**
 * A shared Array implementation.
 * @template T
 * @extends AbstractType<YArrayEvent<T>>
 * @implements {Iterable<T>}
 */
class YArray<T> extends AbstractType<YArrayEvent<T>> with IterableMixin<T> {
  YArray();
  static YArray<T> create<T>() => YArray<T>();

  /**
     * @type {List<any>?}
     * @private
     */
  List<T>? _prelimContent = [];
  /**
     * @type {List<ArraySearchMarker>}
     */
  List<ArraySearchMarker>? innerSearchMarker = [];

  /**
   * Construct a new YArray containing the specified items.
   * @template T
   * @param {List<T>} items
   * @return {YList<T>}
   */
  static YArray<T> from<T>(List<T> items) {
    final a = YArray<T>();
    a.push(items);
    return a;
  }

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
    this.insert(0, /** @type {List<any>} */ (this._prelimContent!));
    this._prelimContent = null;
  }

  YArray<T> innerCopy() {
    return YArray();
  }

  /**
   * @return {YList<T>}
   */
  YArray<T> clone() {
    final arr = YArray<T>();
    arr.insert(
        0,
        this
            .toArray()
            .map((el) => (el is AbstractType ? el.clone() : el))
            .toList()
            .cast());
    return arr;
  }

  int get length {
    return this._prelimContent == null
        ? this.innerLength
        : this._prelimContent!.length;
  }

  /**
   * Creates YArrayEvent and calls observers.
   *
   * @param {Transaction} transaction
   * @param {Set<null|string>} parentSubs Keys changed on this type. `null` if list was modified.
   */
  void innerCallObserver(Transaction transaction, Set<String?> parentSubs) {
    super.innerCallObserver(transaction, parentSubs);
    callTypeObservers(this, transaction, YArrayEvent(this, transaction));
  }

  /**
   * Inserts new content at an index.
   *
   * Important: This function expects an array of content. Not just a content
   * object. The reason for this "weirdness" is that inserting several elements
   * is very efficient when it is done as a single operation.
   *
   * @example
   *  // Insert character 'a' at position 0
   *  yarray.insert(0, ['a'])
   *  // Insert numbers 1, 2 at position 1
   *  yarray.insert(1, [1, 2])
   *
   * @param {number} index The index to insert content at.
   * @param {List<T>} content The array of content
   */
  void insert(int index, List<T> content) {
    if (this.doc != null) {
      transact(this.doc!, (transaction) {
        typeListInsertGenerics(transaction, this, index, content);
      });
    } else {
      /** @type {List<any>} */ (this._prelimContent!).insertAll(index, content);
    }
  }

  /**
   * Appends content to this YArray.
   *
   * @param {List<T>} content Array of content to append.
   */
  void push(List<T> content) {
    this.insert(this.innerLength, content);
  }

  /**
   * Preppends content to this YArray.
   *
   * @param {List<T>} content Array of content to preppend.
   */
  void unshift(List<T> content) {
    this.insert(0, content);
  }

  /**
   * Deletes elements starting from an index.
   *
   * @param {number} index Index at which to start deleting elements
   * @param {number} length The number of elements to remove. Defaults to 1.
   */
  void delete(int index, [int length = 1]) {
    if (this.doc != null) {
      transact(this.doc!, (transaction) {
        typeListDelete(transaction, this, index, length);
      });
    } else {
      /** @type {List<any>} */ (this._prelimContent!)
          .removeRange(index, index + length);
    }
  }

  /**
   * Returns the i-th element from a YArray.
   *
   * @param {number} index The index of the element to return from the YArray
   * @return {T}
   */
  T get(int index) {
    return typeListGet(this, index) as T;
  }

  /**
   * Transforms this YArray to a JavaScript Array.
   *
   * @return {List<T>}
   */
  List<T> toArray() {
    return typeListToArray(this).cast();
  }

  /**
   * Transforms this YArray to a JavaScript Array.
   *
   * @param {number} [start]
   * @param {number} [end]
   * @return {List<T>}
   */
  List<T> slice([int start = 0, int? end]) {
    return typeListSlice(this, start, end ?? this.innerLength).cast();
  }

  /**
   * Transforms this Shared Type to a JSON object.
   *
   * @return {List<any>}
   */
  List<dynamic> toJSON() {
    return this.map((c) => (c is AbstractType ? c.toJSON() : c)).toList();
  }

  // /**
  //  * Returns an Array with the result of calling a provided function on every
  //  * element of this YArray.
  //  *
  //  * @template T,M
  //  * @param {function(T,number,YList<T>):M} f Function that produces an element of the new Array
  //  * @return {List<M>} A new array with each element being the result of the
  //  *                 callback function
  //  */
  // List<M> map<M>(M Function(T, int, YArray<T>) f) {
  //   return typeListMap<T, M, YArray<T>>(this, /** @type {any} */ (f));
  // }

  // /**
  //  * Executes a provided function on once on overy element of this YArray.
  //  *
  //  * @param {function(T,number,YList<T>):void} f A function to execute on every element of this YArray.
  //  */
  // void forEach(void Function(T, int, YArray<T>) f) {
  //   typeListForEach(this, f);
  // }

  /**
   * @return {IterableIterator<T>}
   */
  Iterator<T> get iterator {
    return typeListCreateIterator<T>(this);
  }

  /**
   * @param {AbstractUpdateEncoder} encoder
   */
  void innerWrite(AbstractUpdateEncoder encoder) {
    encoder.writeTypeRef(YArrayRefID);
  }
}

/**
 * @param {AbstractUpdateDecoder} decoder
 *
 * @private
 * @function
 */
YArray<T> readYArray<T>(AbstractUpdateDecoder decoder) => YArray<T>();
