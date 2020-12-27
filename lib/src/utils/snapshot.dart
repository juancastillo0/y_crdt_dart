// import {
//   isDeleted,
//   createDeleteSetFromStructStore,
//   getStateVector,
//   getItemCleanStart,
//   iterateDeletedStructs,
//   writeDeleteSet,
//   writeStateVector,
//   readDeleteSet,
//   readStateVector,
//   createDeleteSet,
//   createID,
//   getState,
//   findIndexSS,
//   UpdateEncoderV2,
//   DefaultDSEncoder,
//   applyUpdateV2,
//   AbstractDSDecoder,
//   AbstractDSEncoder,
//   DSEncoderV2,
//   DSDecoderV1,
//   DSDecoderV2,
//   Transaction,
//   Doc,
//   DeleteSet,
//   Item, // eslint-disable-line
// } from "../internals.js";

// import * as map from "lib0/map.js";
// import * as set from "lib0/set.js";
// import * as decoding from "lib0/decoding.js";
// import * as encoding from "lib0/encoding.js";

import 'dart:typed_data';

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/utils/encoding.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

import '../lib0/decoding.dart' as decoding;
import '../lib0/encoding.dart' as encoding;

class Snapshot {
  /**
   * @param {DeleteSet} ds
   * @param {Map<number,number>} sv state map
   */
  Snapshot(this.ds, this.sv);
  /**
     * @type {DeleteSet}
     */
  final DeleteSet ds;
  /**
     * State Map
     * @type {Map<number,number>}
     */
  final Map<int, int> sv;
}

/**
 * @param {Snapshot} snap1
 * @param {Snapshot} snap2
 * @return {boolean}
 */
bool equalSnapshots(Snapshot snap1, Snapshot snap2) {
  final ds1 = snap1.ds.clients;
  final ds2 = snap2.ds.clients;
  final sv1 = snap1.sv;
  final sv2 = snap2.sv;
  if (sv1.length != sv2.length || ds1.length != ds2.length) {
    return false;
  }
  for (final entry in sv1.entries) {
    if (sv2.get(entry.key) != entry.value) {
      return false;
    }
  }
  for (final entry in ds1.entries) {
    final dsitems2 = ds2.get(entry.key) ?? [];
    final dsitems1 = entry.value;
    if (dsitems1.length != dsitems2.length) {
      return false;
    }
    for (var i = 0; i < dsitems1.length; i++) {
      final dsitem1 = dsitems1[i];
      final dsitem2 = dsitems2[i];
      if (dsitem1.clock != dsitem2.clock || dsitem1.len != dsitem2.len) {
        return false;
      }
    }
  }
  return true;
}

/**
 * @param {Snapshot} snapshot
 * @param {AbstractDSEncoder} [encoder]
 * @return {Uint8Array}
 */
Uint8List encodeSnapshotV2(Snapshot snapshot, AbstractDSEncoder? encoder) {
  final _encoder = encoder ?? DSEncoderV2();
  writeDeleteSet(_encoder, snapshot.ds);
  writeStateVector(_encoder, snapshot.sv);
  return _encoder.toUint8Array();
}

/**
 * @param {Snapshot} snapshot
 * @return {Uint8Array}
 */
Uint8List encodeSnapshot(Snapshot snapshot) =>
    encodeSnapshotV2(snapshot, DefaultDSEncoder());

/**
 * @param {Uint8Array} buf
 * @param {AbstractDSDecoder} [decoder]
 * @return {Snapshot}
 */
Snapshot decodeSnapshotV2(Uint8List buf, [AbstractDSDecoder? decoder]) {
  final _decoder = decoder ?? DSDecoderV2(decoding.createDecoder(buf));
  return Snapshot(readDeleteSet(_decoder), readStateVector(_decoder));
}

/**
 * @param {Uint8Array} buf
 * @return {Snapshot}
 */
Snapshot decodeSnapshot(Uint8List buf) =>
    decodeSnapshotV2(buf, DSDecoderV1(decoding.createDecoder(buf)));

/**
 * @param {DeleteSet} ds
 * @param {Map<number,number>} sm
 * @return {Snapshot}
 */
Snapshot createSnapshot(DeleteSet ds, Map<int, int> sm) => Snapshot(ds, sm);

final emptySnapshot = createSnapshot(createDeleteSet(), Map());

/**
 * @param {Doc} doc
 * @return {Snapshot}
 */
Snapshot snapshot(Doc doc) => createSnapshot(
    createDeleteSetFromStructStore(doc.store), getStateVector(doc.store));

/**
 * @param {Item} item
 * @param {Snapshot|undefined} snapshot
 *
 * @protected
 * @function
 */
bool isVisible(Item item, Snapshot? snapshot) => snapshot == null
    ? !item.deleted
    : snapshot.sv.containsKey(item.id.client) &&
        (snapshot.sv.get(item.id.client) ?? 0) > item.id.clock &&
        !isDeleted(snapshot.ds, item.id);

/**
 * @param {Transaction} transaction
 * @param {Snapshot} snapshot
 */
void splitSnapshotAffectedStructs(Transaction transaction, Snapshot snapshot) {
  final meta =
      transaction.meta.putIfAbsent(splitSnapshotAffectedStructs, () => <dynamic>{}) as Set;
  final store = transaction.doc.store;
  // check if we already split for this snapshot
  if (!meta.contains(snapshot)) {
    snapshot.sv.forEach((client, clock) {
      if (clock < getState(store, client)) {
        getItemCleanStart(transaction, createID(client, clock));
      }
    });
    iterateDeletedStructs(transaction, snapshot.ds, (item) {});
    meta.add(snapshot);
  }
}

/**
 * @param {Doc} originDoc
 * @param {Snapshot} snapshot
 * @param {Doc} [newDoc] Optionally, you may define the Yjs document that receives the data from originDoc
 * @return {Doc}
 */
Doc createDocFromSnapshot(Doc originDoc, Snapshot snapshot, [Doc? newDoc]) {
  if (originDoc.gc) {
    // we should not try to restore a GC-ed document, because some of the restored items might have their content deleted
    throw Exception("originDoc must not be garbage collected");
  }
  final ds = snapshot.ds;
  final sv = snapshot.sv;

  final encoder = UpdateEncoderV2();
  originDoc.transact((transaction) {
    var size = 0;
    sv.forEach((_, clock) {
      if (clock > 0) {
        size++;
      }
    });
    encoding.writeVarUint(encoder.restEncoder, size);
    // splitting the structs before writing them to the encoder
    for (final v in sv.entries) {
      final client = v.key;
      final clock = v.value;

      if (clock == 0) {
        continue;
      }
      if (clock < getState(originDoc.store, client)) {
        getItemCleanStart(transaction, createID(client, clock));
      }
      final structs = originDoc.store.clients.get(client) ?? [];
      final lastStructIndex = findIndexSS(structs, clock - 1);
      // write # encoded structs
      encoding.writeVarUint(encoder.restEncoder, lastStructIndex + 1);
      encoder.writeClient(client);
      // first clock written is 0
      encoding.writeVarUint(encoder.restEncoder, 0);
      for (var i = 0; i <= lastStructIndex; i++) {
        structs[i].write(encoder, 0);
      }
    }
    writeDeleteSet(encoder, ds);
  });
  final _newDoc = newDoc ?? Doc();
  applyUpdateV2(_newDoc, encoder.toUint8Array(), "snapshot");
  return _newDoc;
}
