// import {
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   Transaction,
//   Item,
//   StructStore, // eslint-disable-line
// } from "../internals.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';

/**
 * @private
 */
class ContentString implements AbstractContent {
  /**
   * @param {string} str
   */
  ContentString(this.str);
  /**
     * @type {string}
     */
  String str;

  /**
   * @return {number}
   */
  @override
  getLength() {
    return this.str.length;
  }

  /**
   * @return {List<any>}
   */
  @override
  getContent() {
    return this.str.split("");
  }

  /**
   * @return {boolean}
   */
  @override
  isCountable() {
    return true;
  }

  /**
   * @return {ContentString}
   */
  @override
  copy() {
    return ContentString(this.str);
  }

  /**
   * @param {number} offset
   * @return {ContentString}
   */
  @override
  splice(offset) {
    final right = ContentString(this.str.substring(offset));
    this.str = this.str.substring(0, offset);

    // Prevent encoding invalid documents because of splitting of surrogate pairs: https://github.com/yjs/yjs/issues/248
    final firstCharCode = this.str.codeUnitAt(offset - 1);
    if (firstCharCode >= 0xd800 && firstCharCode <= 0xdbff) {
      // Last character of the left split is the start of a surrogate utf16/ucs2 pair.
      // We don't support splitting of surrogate pairs because this may lead to invalid documents.
      // Replace the invalid character with a unicode replacement character (� / U+FFFD)
      this.str = this.str.substring(0, offset - 1) + "�";
      // replace right as well
      right.str = "�" + right.str.substring(1);
    }
    return right;
  }

  /**
   * @param {ContentString} right
   * @return {boolean}
   */
  @override
  mergeWith(right) {
    if (right is ContentString) {
      this.str += right.str;
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
  integrate(transaction, item) {}
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
    encoder.writeString(offset == 0 ? this.str : this.str.substring(offset));
  }

  /**
   * @return {number}
   */
  @override
  getRef() {
    return 4;
  }
}

/**
 * @private
 *
 * @param {AbstractUpdateDecoder} decoder
 * @return {ContentString}
 */
ContentString readContentString(AbstractUpdateDecoder decoder) =>
    ContentString(decoder.readString());
