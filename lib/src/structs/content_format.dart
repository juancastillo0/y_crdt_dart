// import {
//   AbstractType,
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   Item,
//   StructStore,
//   Transaction, // eslint-disable-line
// } from "../internals.js";

// import * as error from "lib0/error.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';

/**
 * @private
 */
class ContentFormat implements AbstractContent {
  /**
   * @param {string} key
   * @param {Object} value
   */
  ContentFormat(this.key, this.value);
  final String key;
  final Map<String, dynamic> value;

  /**
   * @return {number}
   */
  getLength() {
    return 1;
  }

  /**
   * @return {List<any>}
   */
  getContent() {
    return [];
  }

  /**
   * @return {boolean}
   */
  isCountable() {
    return false;
  }

  /**
   * @return {ContentFormat}
   */
  copy() {
    return new ContentFormat(this.key, this.value);
  }

  /**
   * @param {number} offset
   * @return {ContentFormat}
   */
  splice(offset) {
    throw UnimplementedError();
  }

  /**
   * @param {ContentFormat} right
   * @return {boolean}
   */
  mergeWith(right) {
    return false;
  }

  /**
   * @param {Transaction} transaction
   * @param {Item} item
   */
  integrate(transaction, item) {
    // @todo searchmarker are currently unsupported for rich text documents
    /** @type {AbstractType<any>} */ (item.parent as AbstractType).innerSearchMarker = null;
  }

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
    encoder.writeKey(this.key);
    encoder.writeJSON(this.value);
  }

  /**
   * @return {number}
   */
  getRef() {
    return 6;
  }
}

/**
 * @param {AbstractUpdateDecoder} decoder
 * @return {ContentFormat}
 */
ContentFormat readContentFormat(AbstractUpdateDecoder decoder) =>
    ContentFormat(decoder.readString(), decoder.readJSON() as Map<String, dynamic>);
