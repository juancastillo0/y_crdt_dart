// import {
//   GC,
//   splitItem,
//   Transaction,
//   ID,
//   Item,
//   DSDecoderV2, // eslint-disable-line
// } from "../internals.js";

// import * as math from "lib0/math.js";
// import * as error from "lib0/error.js";

import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/structs/gc.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

class PendingStructRef {
  int i;
  List<AbstractStruct> refs;

  PendingStructRef({required this.i, required this.refs});
}

class StructStore {
  /**
     * @type {Map<number,List<GC|Item>>}
     */
  final clients = <int, List<AbstractStruct>>{};
  /**
     * Store incompleted struct reads here
     * `i` denotes to the next read operation
     * We could shift the array of refs instead, but shift is incredible
     * slow in Chrome for arrays with more than 100k elements
     * @see tryResumePendingStructRefs
     * @type {Map<number,{i:number,refs:List<GC|Item>}>}
     */
  final pendingClientsStructRefs = <int, PendingStructRef>{};
  /**
     * Stack of pending structs waiting for struct dependencies
     * Maximum length of stack is structReaders.size
     * @type {List<GC|Item>}
     */
  final pendingStack = <AbstractStruct>[];
  /**
     * @type {List<DSDecoderV2>}
     */
  List<DSDecoderV2> pendingDeleteReaders = [];
}

/**
 * Return the states as a Map<client,clock>.
 * Note that clock refers to the next expected clock id.
 *
 * @param {StructStore} store
 * @return {Map<number,number>}
 *
 * @public
 * @function
 */
Map<int, int> getStateVector(StructStore store) {
  final sm = <int, int>{};
  store.clients.forEach((client, structs) {
    final struct = structs[structs.length - 1];
    sm.set(client, struct.id.clock + struct.length);
  });
  return sm;
}

/**
 * @param {StructStore} store
 * @param {number} client
 * @return {number}
 *
 * @public
 * @function
 */
int getState(StructStore store, int client) {
  final structs = store.clients.get(client);
  if (structs == null) {
    return 0;
  }
  final lastStruct = structs[structs.length - 1];
  return lastStruct.id.clock + lastStruct.length;
}

/**
 * @param {StructStore} store
 *
 * @private
 * @function
 */
void integretyCheck(StructStore store) {
  store.clients.values.forEach((structs) {
    for (var i = 1; i < structs.length; i++) {
      final l = structs[i - 1];
      final r = structs[i];
      if (l.id.clock + l.length != r.id.clock) {
        throw Exception('StructStore failed integrety check');
      }
    }
  });
}

/**
 * @param {StructStore} store
 * @param {GC|Item} struct
 *
 * @private
 * @function
 */
void addStruct(StructStore store, AbstractStruct struct) {
  var structs = store.clients.get(struct.id.client);
  if (structs == null) {
    structs = [];
    store.clients.set(struct.id.client, structs);
  } else {
    final lastStruct = structs[structs.length - 1];
    if (lastStruct.id.clock + lastStruct.length != struct.id.clock) {
      throw Exception('Unexpected case');
    }
  }
  structs.add(struct);
}

/**
 * Perform a binary search on a sorted array
 * @param {List<Item|GC>} structs
 * @param {number} clock
 * @return {number}
 *
 * @private
 * @function
 */
int findIndexSS(List<AbstractStruct> structs, int clock) {
  var left = 0;
  var right = structs.length - 1;
  var mid = structs[right];
  var midclock = mid.id.clock;
  if (midclock == clock) {
    return right;
  }
  // @todo does it even make sense to pivot the search?
  // If a good split misses, it might actually increase the time to find the correct item.
  // Currently, the only advantage is that search with pivoting might find the item on the first try.
  var midindex = ((clock / (midclock + mid.length - 1)) * right)
      .floor(); // pivoting the search
  while (left <= right) {
    mid = structs[midindex];
    midclock = mid.id.clock;
    if (midclock <= clock) {
      if (clock < midclock + mid.length) {
        return midindex;
      }
      left = midindex + 1;
    } else {
      right = midindex - 1;
    }
    midindex = ((left + right) / 2).floor();
  }
  // Always check state before looking for a struct in StructStore
  // Therefore the case of not finding a struct is unexpected
  throw Exception('Unexpected case');
}

/**
 * Expects that id is actually in store. This function throws or is an infinite loop otherwise.
 *
 * @param {StructStore} store
 * @param {ID} id
 * @return {GC|Item}
 *
 * @private
 * @function
 */
AbstractStruct find(StructStore store, ID id) {
  /**
   * @type {List<GC|Item>}
   */
  // @ts-ignore
  final structs = store.clients.get(id.client)!;
  return structs[findIndexSS(structs, id.clock)];
}

/**
 * Expects that id is actually in store. This function throws or is an infinite loop otherwise.
 * @private
 * @function
 */
const getItem = /** @type {function(StructStore,ID):Item} */ find;

/**
 * @param {Transaction} transaction
 * @param {List<Item|GC>} structs
 * @param {number} clock
 */
int findIndexCleanStart(
    Transaction transaction, List<AbstractStruct> structs, int clock) {
  final index = findIndexSS(structs, clock);
  final struct = structs[index];
  if (struct.id.clock < clock && struct is Item) {
    structs.insert(
        index + 1, splitItem(transaction, struct, clock - struct.id.clock));
    return index + 1;
  }
  return index;
}

/**
 * Expects that id is actually in store. This function throws or is an infinite loop otherwise.
 *
 * @param {Transaction} transaction
 * @param {ID} id
 * @return {Item}
 *
 * @private
 * @function
 */
Item getItemCleanStart(Transaction transaction, ID id) {
  final structs =
      /** @type {List<Item>} */ (transaction.doc.store.clients.get(id.client))!;
  return structs[findIndexCleanStart(transaction, structs, id.clock)] as Item;
}

/**
 * Expects that id is actually in store. This function throws or is an infinite loop otherwise.
 *
 * @param {Transaction} transaction
 * @param {StructStore} store
 * @param {ID} id
 * @return {Item}
 *
 * @private
 * @function
 */
Item getItemCleanEnd(Transaction transaction, StructStore store, ID id) {
  /**
   * @type {List<Item>}
   */
  // @ts-ignore
  final structs = store.clients.get(id.client)!;
  final index = findIndexSS(structs, id.clock);
  final struct = structs[index] as Item;
  if (id.clock != struct.id.clock + struct.length - 1 && struct is! GC) {
    structs.insert(index + 1,
        splitItem(transaction, struct, id.clock - struct.id.clock + 1));
  }
  return struct;
}

/**
 * Replace `item` with `newitem` in store
 * @param {StructStore} store
 * @param {GC|Item} struct
 * @param {GC|Item} newStruct
 *
 * @private
 * @function
 */
void replaceStruct(
    StructStore store, AbstractStruct struct, AbstractStruct newStruct) {
  final structs =
      /** @type {List<GC|Item>} */ (store.clients.get(struct.id.client))!;
  structs[findIndexSS(structs, struct.id.clock)] = newStruct;
}

/**
 * Iterate over a range of structs
 *
 * @param {Transaction} transaction
 * @param {List<Item|GC>} structs
 * @param {number} clockStart Inclusive start
 * @param {number} len
 * @param {function(GC|Item):void} f
 *
 * @function
 */
void iterateStructs(
  Transaction transaction,
  List<AbstractStruct> structs,
  int clockStart,
  int len,
  void Function(AbstractStruct) f,
) {
  if (len == 0) {
    return;
  }
  final clockEnd = clockStart + len;
  var index = findIndexCleanStart(transaction, structs, clockStart);
  AbstractStruct struct;
  do {
    struct = structs[index++];
    if (clockEnd < struct.id.clock + struct.length) {
      findIndexCleanStart(transaction, structs, clockEnd);
    }
    f(struct);
  } while (index < structs.length && structs[index].id.clock < clockEnd);
}
