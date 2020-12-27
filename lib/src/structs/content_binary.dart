// import {
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   StructStore,
//   Item,
//   Transaction, // eslint-disable-line
// } from "../internals.js";

// import * as error from "lib0/error.js";

import 'dart:typed_data';

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';

class ContentBinary implements AbstractContent {
  /**
   * @param {Uint8Array} content
   */
  ContentBinary(this.content);
  final Uint8List content;

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
    return [this.content];
  }

  /**
   * @return {boolean}
   */
  isCountable() {
    return true;
  }

  /**
   * @return {ContentBinary}
   */
  copy() {
    return ContentBinary(this.content);
  }

  /**
   * @param {number} offset
   * @return {ContentBinary}
   */
  splice(offset) {
    throw UnimplementedError();
  }

  /**
   * @param {ContentBinary} right
   * @return {boolean}
   */
  mergeWith(right) {
    return false;
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
    encoder.writeBuf(this.content);
  }

  /**
   * @return {number}
   */
  getRef() {
    return 3;
  }
}

/**
 * @param {AbstractUpdateDecoder} decoder
 * @return {ContentBinary}
 */
ContentBinary readContentBinary(AbstractUpdateDecoder decoder) =>
    ContentBinary(decoder.readBuf());
