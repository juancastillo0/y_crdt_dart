// import {
//   readYArray,
//   readYMap,
//   readYText,
//   readYXmlElement,
//   readYXmlFragment,
//   readYXmlHook,
//   readYXmlText,
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   StructStore,
//   Transaction,
//   Item,
//   YEvent,
//   AbstractType, // eslint-disable-line
// } from "../internals.js";

// import * as error from "lib0/error.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/types/y_array.dart' show readYArray;
import 'package:y_crdt/src/types/y_map.dart';
import 'package:y_crdt/src/types/y_text.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';

/**
 * @type {List<function(AbstractUpdateDecoder):AbstractType<any>>}
 * @private
 */
const List<AbstractType Function(AbstractUpdateDecoder)> typeRefs = [
  readYArray,
  readYMap,
  readYText,
  // readYXmlElement,
  // readYXmlFragment,
  // readYXmlHook,
  // readYXmlText,
];

const YArrayRefID = 0;
const YMapRefID = 1;
const YTextRefID = 2;
const YXmlElementRefID = 3;
const YXmlFragmentRefID = 4;
const YXmlHookRefID = 5;
const YXmlTextRefID = 6;

/**
 * @private
 */
class ContentType implements AbstractContent {
  /**
   * @param {AbstractType<YEvent>} type
   */
  ContentType(this.type);
  /**
     * @type {AbstractType<any>}
     */
  final AbstractType type;

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
    return [this.type];
  }

  /**
   * @return {boolean}
   */
  isCountable() {
    return true;
  }

  /**
   * @return {ContentType}
   */
  copy() {
    return ContentType(this.type.innerCopy());
  }

  /**
   * @param {number} offset
   * @return {ContentType}
   */
  splice(offset) {
    throw UnimplementedError();
  }

  /**
   * @param {ContentType} right
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
    this.type.innerIntegrate(transaction.doc, item);
  }

  /**
   * @param {Transaction} transaction
   */
  delete(transaction) {
    var item = this.type.innerStart;
    while (item != null) {
      if (!item.deleted) {
        item.delete(transaction);
      } else {
        // Whis will be gc'd later and we want to merge it if possible
        // We try to merge all deleted items after each transaction,
        // but we have no knowledge about that this needs to be merged
        // since it is not in transaction.ds. Hence we add it to transaction._mergeStructs
        transaction.mergeStructs.add(item);
      }
      item = item.right;
    }
    this.type.innerMap.values.forEach((item) {
      if (!item.deleted) {
        item.delete(transaction);
      } else {
        // same as above
        transaction.mergeStructs.add(item);
      }
    });
    transaction.changed.remove(this.type);
  }

  /**
   * @param {StructStore} store
   */
  gc(store) {
    var item = this.type.innerStart;
    while (item != null) {
      item.gc(store, true);
      item = item.right;
    }
    this.type.innerStart = null;
    this.type.innerMap.values.forEach(
        /** @param {Item | null} item */ (item) {
      Item? _item = item;
      while (_item != null) {
        _item.gc(store, true);
        _item = _item.left;
      }
    });
    this.type.innerMap = {};
  }

  /**
   * @param {AbstractUpdateEncoder} encoder
   * @param {number} offset
   */
  write(encoder, offset) {
    this.type.innerWrite(encoder);
  }

  /**
   * @return {number}
   */
  getRef() {
    return 7;
  }
}

/**
 * @private
 *
 * @param {AbstractUpdateDecoder} decoder
 * @return {ContentType}
 */
ContentType readContentType(AbstractUpdateDecoder decoder) =>
    ContentType(typeRefs[decoder.readTypeRef()](decoder));
