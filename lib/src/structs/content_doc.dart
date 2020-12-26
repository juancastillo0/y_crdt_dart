// import {
//   Doc,
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   StructStore,
//   Transaction,
//   Item, // eslint-disable-line
// } from "../internals.js";

// import * as error from "lib0/error.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

class _Opts {
  bool? gc;
  bool? autoLoad;
  dynamic meta;

  Map<String, dynamic> toMap() {
    return {
      "gc": gc,
      "autoLoad": autoLoad,
      "meta": meta,
    };
  }
}

/**
 * @private
 */
class ContentDoc implements AbstractContent {
  /**
   * @param {Doc} doc
   */
  ContentDoc(this.doc) {
    final doc = this.doc;
    if (doc != null) {
      if (doc.item != null) {
        logger.e("This document was already integrated as a sub-document. "
            "You should create a second instance instead with the same guid.");
      }
      if (!doc.gc) {
        opts.gc = false;
      }
      if (doc.autoLoad) {
        opts.autoLoad = true;
      }
      if (doc.meta != null) {
        opts.meta = doc.meta;
      }
    }
  }
  /**
     * @type {Doc}
     */
  Doc? doc;
  /**
     * @type {any}
     */

  final opts = _Opts();

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
    return [this.doc];
  }

  /**
   * @return {boolean}
   */
  isCountable() {
    return true;
  }

  /**
   * @return {ContentDoc}
   */
  copy() {
    return new ContentDoc(this.doc);
  }

  /**
   * @param {number} offset
   * @return {ContentDoc}
   */
  splice(offset) {
    throw UnimplementedError();
  }

  /**
   * @param {ContentDoc} right
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
    // this needs to be reflected in doc.destroy as well
    final doc = this.doc;
    if (doc != null) {
      doc.item = item;
      transaction.subdocsAdded.add(doc);
      if (doc.shouldLoad) {
        transaction.subdocsLoaded.add(doc);
      }
    }
  }

  /**
   * @param {Transaction} transaction
   */
  delete(transaction) {
    if (transaction.subdocsAdded.contains(this.doc)) {
      transaction.subdocsAdded.remove(this.doc);
    } else {
      transaction.subdocsRemoved.add(this.doc!);
    }
  }

  /**
   * @param {StructStore} store
   */
  gc(store) {}

  /**
   * @param {AbstractUpdateEncoder} encoder
   * @param {number} offset
   */
  write(encoder, offset) {
    encoder.writeString(this.doc!.guid);
    encoder.writeAny(this.opts.toMap());
  }

  /**
   * @return {number}
   */
  getRef() {
    return 9;
  }
}

/**
 * @private
 *
 * @param {AbstractUpdateDecoder} decoder
 * @return {ContentDoc}
 */
ContentDoc readContentDoc(AbstractUpdateDecoder decoder) {
  final guid = decoder.readString();
  final params = decoder.readAny();
  return ContentDoc(
    Doc(
      guid: guid,
      autoLoad: params["autoLoad"],
      gc: params["gc"],
      gcFilter: params["gcFilter"],
      meta: params["meta"],
    ),
  );
}
