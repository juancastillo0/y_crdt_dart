// import {
//   findIndexSS,
//   getState,
//   splitItem,
//   iterateStructs,
//   AbstractUpdateDecoder,
//   AbstractDSDecoder,
//   AbstractDSEncoder,
//   DSDecoderV2,
//   DSEncoderV2,
//   Item,
//   GC,
//   StructStore,
//   Transaction,
//   ID, // eslint-disable-line
// } from "../internals.js";

import 'package:y_crdt/src/lib0/decoding.dart' as decoding;
import 'package:y_crdt/src/lib0/encoding.dart' as encoding;
// import * as array from "lib0/array.js";
// import * as math from "lib0/math.js";
// import * as map from "lib0/map.js";
// import * as encoding from "lib0/encoding.js";
// import * as decoding from "lib0/decoding.js";

import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

class DeleteItem {
  /**
   * @param {number} clock
   * @param {number} len
   */
  DeleteItem(this.clock, this.len);
  /**
     * @type {number}
     */
  final int clock;
  /**
     * @type {number}
     */
  int len;
}

/**
 * We no longer maintain a DeleteStore. DeleteSet is a temporary object that is created when needed.
 * - When created in a transaction, it must only be accessed after sorting, and merging
 *   - This DeleteSet is send to other clients
 * - We do not create a DeleteSet when we send a sync message. The DeleteSet message is created directly from StructStore
 * - We read a DeleteSet as part of a sync/update message. In this case the DeleteSet is already sorted and merged.
 */
class DeleteSet {
  DeleteSet();
  /**
     * @type {Map<number,List<DeleteItem>>}
     */
  final clients = <int, List<DeleteItem>>{};
}

/**
 * Iterate over all structs that the DeleteSet gc's.
 *
 * @param {Transaction} transaction
 * @param {DeleteSet} ds
 * @param {function(GC|Item):void} f
 *
 * @function
 */
void iterateDeletedStructs(Transaction transaction, DeleteSet ds,
        void Function(AbstractStruct) f) =>
    ds.clients.forEach((clientid, deletes) {
      final structs = /** @type {List<GC|Item>} */ transaction.doc.store.clients
          .get(clientid);
      for (var i = 0; i < deletes.length; i++) {
        final del = deletes[i];
        iterateStructs(transaction, structs!, del.clock, del.len, f);
      }
    });

/**
 * @param {List<DeleteItem>} dis
 * @param {number} clock
 * @return {number|null}
 *
 * @private
 * @function
 */
int? findIndexDS(List<DeleteItem> dis, int clock) {
  var left = 0;
  var right = dis.length - 1;
  while (left <= right) {
    final midindex = ((left + right) / 2).floor();
    final mid = dis[midindex];
    final midclock = mid.clock;
    if (midclock <= clock) {
      if (clock < midclock + mid.len) {
        return midindex;
      }
      left = midindex + 1;
    } else {
      right = midindex - 1;
    }
  }
  return null;
}

/**
 * @param {DeleteSet} ds
 * @param {ID} id
 * @return {boolean}
 *
 * @private
 * @function
 */
bool isDeleted(DeleteSet ds, ID id) {
  final dis = ds.clients.get(id.client);
  return dis != null && findIndexDS(dis, id.clock) != null;
}

/**
 * @param {DeleteSet} ds
 *
 * @private
 * @function
 */
void sortAndMergeDeleteSet(DeleteSet ds) {
  ds.clients.forEach((_, dels) {
    dels.sort((a, b) => a.clock - b.clock);
    // merge items without filtering or splicing the array
    // i is the current pointer
    // j refers to the current insert position for the pointed item
    // try to merge dels[i] into dels[j-1] or set dels[j]=dels[i]
    var i = 1, j = 1;
    for (; i < dels.length; i++) {
      final left = dels[j - 1];
      final right = dels[i];
      if (left.clock + left.len == right.clock) {
        left.len += right.len;
      } else {
        if (j < i) {
          dels[j] = right;
        }
        j++;
      }
    }
    dels.length = j;
  });
}

/**
 * @param {List<DeleteSet>} dss
 * @return {DeleteSet} A fresh DeleteSet
 */
DeleteSet mergeDeleteSets(List<DeleteSet> dss) {
  final merged = DeleteSet();
  for (var dssI = 0; dssI < dss.length; dssI++) {
    dss[dssI].clients.forEach((client, delsLeft) {
      if (!merged.clients.containsKey(client)) {
        // Write all missing keys from current ds and all following.
        // If merged already contains `client` current ds has already been added.
        /**
         * @type {List<DeleteItem>}
         */
        final dels = [...delsLeft];
        for (var i = dssI + 1; i < dss.length; i++) {
          dels.addAll(dss[i].clients.get(client) ?? []);
        }
        merged.clients.set(client, dels);
      }
    });
  }
  sortAndMergeDeleteSet(merged);
  return merged;
}

/**
 * @param {DeleteSet} ds
 * @param {number} client
 * @param {number} clock
 * @param {number} length
 *
 * @private
 * @function
 */
void addToDeleteSet(DeleteSet ds, int client, int clock, int length) {
  ds.clients.putIfAbsent(client, () => []).add(
        DeleteItem(clock, length),
      );
}

DeleteSet createDeleteSet() => DeleteSet();

/**
 * @param {StructStore} ss
 * @return {DeleteSet} Merged and sorted DeleteSet
 *
 * @private
 * @function
 */
DeleteSet createDeleteSetFromStructStore(StructStore ss) {
  final ds = createDeleteSet();
  ss.clients.forEach((client, structs) {
    /**
     * @type {List<DeleteItem>}
     */
    final dsitems = <DeleteItem>[];
    for (var i = 0; i < structs.length; i++) {
      final struct = structs[i];
      if (struct.deleted) {
        final clock = struct.id.clock;
        var len = struct.length;
        for (; i + 1 < structs.length; i++) {
          final next = structs[i + 1];
          if (next.id.clock == clock + len && next.deleted) {
            len += next.length;
          } else {
            break;
          }
        }
        dsitems.add(DeleteItem(clock, len));
      }
    }
    if (dsitems.length > 0) {
      ds.clients.set(client, dsitems);
    }
  });
  return ds;
}

/**
 * @param {AbstractDSEncoder} encoder
 * @param {DeleteSet} ds
 *
 * @private
 * @function
 */
void writeDeleteSet(AbstractDSEncoder encoder, DeleteSet ds) {
  encoding.writeVarUint(encoder.restEncoder, ds.clients.length);
  ds.clients.forEach((client, dsitems) {
    encoder.resetDsCurVal();
    encoding.writeVarUint(encoder.restEncoder, client);
    final len = dsitems.length;
    encoding.writeVarUint(encoder.restEncoder, len);
    for (var i = 0; i < len; i++) {
      final item = dsitems[i];
      encoder.writeDsClock(item.clock);
      encoder.writeDsLen(item.len);
    }
  });
}

/**
 * @param {AbstractDSDecoder} decoder
 * @return {DeleteSet}
 *
 * @private
 * @function
 */
DeleteSet readDeleteSet(AbstractDSDecoder decoder) {
  final ds = DeleteSet();
  final numClients = decoding.readVarUint(decoder.restDecoder);
  for (var i = 0; i < numClients; i++) {
    decoder.resetDsCurVal();
    final client = decoding.readVarUint(decoder.restDecoder);
    final numberOfDeletes = decoding.readVarUint(decoder.restDecoder);
    if (numberOfDeletes > 0) {
      final dsField = ds.clients.putIfAbsent(client, () => []);
      for (var i = 0; i < numberOfDeletes; i++) {
        dsField.add(DeleteItem(decoder.readDsClock(), decoder.readDsLen()));
      }
    }
  }
  return ds;
}

/**
 * @todo YDecoder also contains references to String and other Decoders. Would make sense to exchange YDecoder.toUint8Array for YDecoder.DsToUint8Array()..
 */

/**
 * @param {AbstractDSDecoder} decoder
 * @param {Transaction} transaction
 * @param {StructStore} store
 *
 * @private
 * @function
 */
void readAndApplyDeleteSet(
    AbstractDSDecoder decoder, Transaction transaction, StructStore store) {
  final unappliedDS = DeleteSet();
  final numClients = decoding.readVarUint(decoder.restDecoder);
  for (var i = 0; i < numClients; i++) {
    decoder.resetDsCurVal();
    final client = decoding.readVarUint(decoder.restDecoder);
    final numberOfDeletes = decoding.readVarUint(decoder.restDecoder);
    final structs = store.clients.get(client) ?? [];
    final state = getState(store, client);
    for (var i = 0; i < numberOfDeletes; i++) {
      final clock = decoder.readDsClock();
      final clockEnd = clock + decoder.readDsLen();
      if (clock < state) {
        if (state < clockEnd) {
          addToDeleteSet(unappliedDS, client, state, clockEnd - state);
        }
        var index = findIndexSS(structs, clock);
        /**
         * We can ignore the case of GC and Delete structs, because we are going to skip them
         * @type {Item}
         */
        // @ts-ignore
        var struct = structs[index];
        // split the first item if necessary
        if (!struct.deleted && struct.id.clock < clock) {
          structs.insert(
            index + 1,
            splitItem(transaction, struct as Item, clock - struct.id.clock),
          );
          index++; // increase we now want to use the next struct
        }
        while (index < structs.length) {
          // @ts-ignore
          struct = structs[index++];
          if (struct.id.clock < clockEnd) {
            if (!struct.deleted && struct is Item) {
              if (clockEnd < struct.id.clock + struct.length) {
                structs.insert(
                  index,
                  splitItem(transaction, struct, clockEnd - struct.id.clock),
                );
              }
              struct.delete(transaction);
            }
          } else {
            break;
          }
        }
      } else {
        addToDeleteSet(unappliedDS, client, clock, clockEnd - clock);
      }
    }
  }
  if (unappliedDS.clients.length > 0) {
    // TODO: no need for encoding+decoding ds anymore
    final unappliedDSEncoder = DSEncoderV2();
    writeDeleteSet(unappliedDSEncoder, unappliedDS);
    store.pendingDeleteReaders.add(
        DSDecoderV2(decoding.createDecoder(unappliedDSEncoder.toUint8Array())));
  }
}
