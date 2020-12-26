// import {
//   addToDeleteSet,
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   StructStore,
//   Item,
//   Transaction, // eslint-disable-line
// } from "../internals.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';

class ContentDeleted implements AbstractContent {
  /**
   * @param {number} len
   */
  ContentDeleted(this.len);
  int len;

  /**
   * @return {number}
   */
  getLength() {
    return this.len;
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
   * @return {ContentDeleted}
   */
  copy() {
    return new ContentDeleted(this.len);
  }

  /**
   * @param {number} offset
   * @return {ContentDeleted}
   */
  splice(offset) {
    final right = ContentDeleted(this.len - offset);
    this.len = offset;
    return right;
  }

  /**
   * @param {ContentDeleted} right
   * @return {boolean}
   */
  mergeWith(right) {
    if (right is ContentDeleted) {
      this.len += right.len;
      return true;
    } else {
      return false;
    }
  }

  /**
   * @param {Transaction} transaction
   * @param {Item} item
   */
  integrate(transaction, item) {
    addToDeleteSet(
        transaction.deleteSet, item.id.client, item.id.clock, this.len);
    item.markDeleted();
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
    encoder.writeLen(this.len - offset);
  }

  /**
   * @return {number}
   */
  getRef() {
    return 1;
  }
}

/**
 * @private
 *
 * @param {AbstractUpdateDecoder} decoder
 * @return {ContentDeleted}
 */
ContentDeleted readContentDeleted(AbstractUpdateDecoder decoder) =>
    ContentDeleted(decoder.readLen());
