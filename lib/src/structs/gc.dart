// import {
//   AbstractStruct,
//   addStruct,
//   AbstractUpdateEncoder,
//   StructStore,
//   Transaction,
//   ID, // eslint-disable-line
// } from "../internals.js";

import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';

const structGCRefNumber = 0;

/**
 * @private
 */
class GC extends AbstractStruct {
  GC(ID id, int length) : super(id, length);

  @override
  bool get deleted {
    return true;
  }

  void delete() {}

  /**
   * @param {GC} right
   * @return {boolean}
   */
  @override
  bool mergeWith(AbstractStruct right) {
    this.length += right.length;
    return true;
  }

  /**
   * @param {Transaction} transaction
   * @param {number} offset
   */
  @override
  void integrate(Transaction transaction, int offset) {
    if (offset > 0) {
      this.id.clock += offset;
      this.length -= offset;
    }
    addStruct(transaction.doc.store, this);
  }

  /**
   * @param {AbstractUpdateEncoder} encoder
   * @param {number} offset
   */
  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    encoder.writeInfo(structGCRefNumber);
    encoder.writeLen(this.length - offset);
  }

  /**
   * @param {Transaction} transaction
   * @param {StructStore} store
   * @return {null | number}
   */
  int? getMissing(Transaction transaction, StructStore store) {
    return null;
  }
}
