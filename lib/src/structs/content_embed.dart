// import {
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   StructStore,
//   Item,
//   Transaction, // eslint-disable-line
// } from "../internals.js";

// import * as error from "lib0/error.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';

/**
 * @private
 */
class ContentEmbed implements AbstractContent {
  /**
   * @param {Object} embed
   */
  ContentEmbed(this.embed);
  final Map<String, dynamic> embed;

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
    return [this.embed];
  }

  /**
   * @return {boolean}
   */
  isCountable() {
    return true;
  }

  /**
   * @return {ContentEmbed}
   */
  copy() {
    return new ContentEmbed(this.embed);
  }

  /**
   * @param {number} offset
   * @return {ContentEmbed}
   */
  splice(offset) {
    throw UnimplementedError();
  }

  /**
   * @param {ContentEmbed} right
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
    encoder.writeJSON(this.embed);
  }

  /**
   * @return {number}
   */
  getRef() {
    return 5;
  }
}

/**
 * @private
 *
 * @param {AbstractUpdateDecoder} decoder
 * @return {ContentEmbed}
 */
ContentEmbed readContentEmbed(AbstractUpdateDecoder decoder) =>
    ContentEmbed(decoder.readJSON() as Map<String, dynamic>);
