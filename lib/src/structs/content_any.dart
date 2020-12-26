// import {
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   Transaction,
//   Item,
//   StructStore, // eslint-disable-line
// } from "../internals.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';

class ContentAny implements AbstractContent {
  /**
   * @param {List<any>} arr
   */
  ContentAny(this.arr);
  List<dynamic> arr;

  /**
   * @return {number}
   */
  int getLength() {
    return this.arr.length;
  }

  /**
   * @return {List<any>}
   */
  List<dynamic> getContent() {
    return this.arr;
  }

  /**
   * @return {boolean}
   */
  bool isCountable() {
    return true;
  }

  /**
   * @return {ContentAny}
   */
  ContentAny copy() {
    return ContentAny(this.arr);
  }

  /**
   * @param {number} offset
   * @return {ContentAny}
   */
  ContentAny splice(int offset) {
    final right = ContentAny(this.arr.sublist(offset));
    this.arr = this.arr.sublist(0, offset);
    return right;
  }

  /**
   * @param {ContentAny} right
   * @return {boolean}
   */
  bool mergeWith(AbstractContent right) {
    if (right is ContentAny) {
      this.arr = [...this.arr, ...right.arr];
      return true;
    } else {
      return false;
    }
  }

  /**
   * @param {Transaction} transaction
   * @param {Item} item
   */
  void integrate(transaction, item) {}
  /**
   * @param {Transaction} transaction
   */
  void delete(Transaction transaction) {
    print("delete ContentAny");
  }
  /**
   * @param {StructStore} store
   */
  void gc(StructStore store) {}
  /**
   * @param {AbstractUpdateEncoder} encoder
   * @param {number} offset
   */
  void write(AbstractUpdateEncoder encoder,int offset) {
    final len = this.arr.length;
    encoder.writeLen(len - offset);
    for (var i = offset; i < len; i++) {
      final c = this.arr[i];
      encoder.writeAny(c);
    }
  }

  /**
   * @return {number}
   */
  int getRef() {
    return 8;
  }
}

/**
 * @param {AbstractUpdateDecoder} decoder
 * @return {ContentAny}
 */
ContentAny readContentAny(AbstractUpdateDecoder decoder) {
  final len = decoder.readLen();
  final cs = [];
  for (var i = 0; i < len; i++) {
    cs.add(decoder.readAny());
  }
  return ContentAny(cs);
}
