// import {
//   AbstractUpdateEncoder,
//   ID,
//   Transaction, // eslint-disable-line
// } from "../internals.js";

// import * as error from "lib0/error.js";

import 'package:y_crdt/src/utils/id.dart' show ID;
import 'package:y_crdt/src/utils/transaction.dart' show Transaction;
import 'package:y_crdt/src/utils/update_encoder.dart'
    show AbstractUpdateEncoder;

abstract class AbstractStruct {
  /**
   * @param {ID} id
   * @param {number} length
   */
  AbstractStruct(this.id, this.length);
  ID id;
  int length;

  /**
   * @type {boolean}
   */
  bool get deleted;

  /**
   * Merge this struct with the item to the right.
   * This method is already assuming that `this.id.clock + this.length == this.id.clock`.
   * Also this method does *not* remove right from StructStore!
   * @param {AbstractStruct} right
   * @return {boolean} wether this merged with right
   */
  bool mergeWith(AbstractStruct right) {
    return false;
  }

  /**
   * @param {AbstractUpdateEncoder} encoder The encoder to write data to.
   * @param {number} offset
   * @param {number} encodingRef
   */
  void write(AbstractUpdateEncoder encoder, int offset);

  /**
   * @param {Transaction} transaction
   * @param {number} offset
   */
  void integrate(Transaction transaction, int offset);
}
