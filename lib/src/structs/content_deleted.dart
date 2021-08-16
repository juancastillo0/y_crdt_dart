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
  @override
  getLength() {
    return this.len;
  }

  /**
   * @return {List<any>}
   */
  @override
  getContent() {
    return [];
  }

  /**
   * @return {boolean}
   */
  @override
  isCountable() {
    return false;
  }

  /**
   * @return {ContentDeleted}
   */
  @override
  copy() {
    return ContentDeleted(this.len);
  }

  /**
   * @param {number} offset
   * @return {ContentDeleted}
   */
  @override
  splice(offset) {
    final right = ContentDeleted(this.len - offset);
    this.len = offset;
    return right;
  }

  /**
   * @param {ContentDeleted} right
   * @return {boolean}
   */
  @override
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
  @override
  integrate(transaction, item) {
    addToDeleteSet(
        transaction.deleteSet, item.id.client, item.id.clock, this.len);
    item.markDeleted();
  }

  /**
   * @param {Transaction} transaction
   */
  @override
  delete(transaction) {}
  /**
   * @param {StructStore} store
   */
  @override
  gc(store) {}
  /**
   * @param {AbstractUpdateEncoder} encoder
   * @param {number} offset
   */
  @override
  write(encoder, offset) {
    encoder.writeLen(this.len - offset);
  }

  /**
   * @return {number}
   */
  @override
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
ContentDeleted readContentDeleted(AbstractUpdateDecoder decoder) {
  return ContentDeleted(decoder.readLen());
}
