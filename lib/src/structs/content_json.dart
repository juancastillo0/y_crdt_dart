// import {
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   Transaction,
//   Item,
//   StructStore, // eslint-disable-line
// } from "../internals.js";

import 'dart:convert';

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';

/**
 * @private
 */
class ContentJSON implements AbstractContent {
  /**
   * @param {List<any>} arr
   */
  ContentJSON(this.arr);
  /**
     * @type {List<any>}
     */
  List<dynamic> arr;

  /**
   * @return {number}
   */
  getLength() {
    return this.arr.length;
  }

  /**
   * @return {List<any>}
   */
  getContent() {
    return this.arr;
  }

  /**
   * @return {boolean}
   */
  isCountable() {
    return true;
  }

  /**
   * @return {ContentJSON}
   */
  copy() {
    return new ContentJSON(this.arr);
  }

  /**
   * @param {number} offset
   * @return {ContentJSON}
   */
  splice(offset) {
    final right = ContentJSON(this.arr.sublist(offset));
    this.arr = this.arr.sublist(0, offset);
    return right;
  }

  /**
   * @param {ContentJSON} right
   * @return {boolean}
   */
  mergeWith(right) {
    if (right is ContentJSON) {
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
  integrate(transaction, item) {}
  /**
   * @param {Transaction} transaction
   */
  delete(transaction) {}
  /**
   * @param {StructStore} store
   */
  gc(store) {}
  /**
   * @param {AbstractUpdateEncoder} encoder
   * @param {number} offset
   */
  write(encoder, offset) {
    final len = this.arr.length;
    encoder.writeLen(len - offset);
    for (var i = offset; i < len; i++) {
      final c = this.arr[i];
      encoder.writeString(c == null ? "undefined" : jsonEncode(c));
    }
  }

  /**
   * @return {number}
   */
  getRef() {
    return 2;
  }
}

/**
 * @private
 *
 * @param {AbstractUpdateDecoder} decoder
 * @return {ContentJSON}
 */
ContentJSON readContentJSON(AbstractUpdateDecoder decoder) {
  final len = decoder.readLen();
  final cs = [];
  for (var i = 0; i < len; i++) {
    final c = decoder.readString();
    if (c == "undefined") {
      cs.add(null);
    } else {
      cs.add(jsonDecode(c));
    }
  }
  return ContentJSON(cs);
}
