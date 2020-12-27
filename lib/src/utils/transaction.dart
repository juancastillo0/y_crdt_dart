// import {
//   getState,
//   writeStructsFromTransaction,
//   writeDeleteSet,
//   DeleteSet,
//   sortAndMergeDeleteSet,
//   getStateVector,
//   findIndexSS,
//   callEventHandlerListeners,
//   Item,
//   generateNewClientId,
//   createID,
//   AbstractUpdateEncoder, GC, StructStore, UpdateEncoderV2, DefaultUpdateEncoder, AbstractType, AbstractStruct, YEvent, Doc // eslint-disable-line
// } from '../internals.js'

// import * as map from 'lib0/map.js'
// import * as math from 'lib0/math.js'
// import * as set from 'lib0/set.js'
// import * as logging from 'lib0/logging.js'
// import { callAll } from 'lib0/function.js'

import 'dart:math' as math;
import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/event_handler.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/utils/y_event.dart';
import 'package:y_crdt/src/utils/encoding.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

/**
 * A transaction is created for every change on the Yjs model. It is possible
 * to bundle changes on the Yjs model in a single transaction to
 * minimize the number on messages sent and the number of observer calls.
 * If possible the user of this library should bundle as many changes as
 * possible. Here is an example to illustrate the advantages of bundling:
 *
 * @example
 * const map = y.define('map', YMap)
 * // Log content when change is triggered
 * map.observe(() => {
 *   console.log('change triggered')
 * })
 * // Each change on the map type triggers a log message:
 * map.set('a', 0) // => "change triggered"
 * map.set('b', 0) // => "change triggered"
 * // When put in a transaction, it will trigger the log after the transaction:
 * y.transact(() => {
 *   map.set('a', 1)
 *   map.set('b', 1)
 * }) // => "change triggered"
 *
 * @public
 */
class Transaction {
  /**
   * @param {Doc} doc
   * @param {any} origin
   * @param {boolean} local
   */
  Transaction(this.doc, this.origin, this.local)
      : beforeState = getStateVector(doc.store);
  /**
     * The Yjs instance.
     * @type {Doc}
     */
  final Doc doc;
  /**
     * Describes the set of deleted items by ids
     * @type {DeleteSet}
     */
  final deleteSet = DeleteSet();
  /**
     * Holds the state before the transaction started.
     * @type {Map<Number,Number>}
     */
  late Map<int, int> beforeState;
  /**
     * Holds the state after the transaction.
     * @type {Map<Number,Number>}
     */
  var afterState = <int, int>{};
  /**
     * All types that were directly modified (property added or child
     * inserted/deleted). New types are not included in this Set.
     * Maps from type to parentSubs (`item.parentSub = null` for YArray)
     * @type {Map<AbstractType<YEvent>,Set<String|null>>}
     */
  final changed = <AbstractType<YEvent>, Set<String?>>{};
  /**
     * Stores the events for the types that observe also child elements.
     * It is mainly used by `observeDeep`.
     * @type {Map<AbstractType<YEvent>,List<YEvent>>}
     */
  final changedParentTypes = <AbstractType<YEvent>, List<YEvent>>{};
  /**
     * @type {List<AbstractStruct>}
     */
  final mergeStructs = <AbstractStruct>[];
  /**
     * @type {any}
     */
  final Object? origin;
  /**
     * Stores meta information on the transaction
     * @type {Map<any,any>}
     */
  final meta = <Object, dynamic>{};
  /**
     * Whether this change originates from this doc.
     * @type {boolean}
     */
  final bool local;
  /**
     * @type {Set<Doc>}
     */
  final subdocsAdded = <Doc>{};
  /**
     * @type {Set<Doc>}
     */
  final subdocsRemoved = <Doc>{};
  /**
     * @type {Set<Doc>}
     */
  final subdocsLoaded = <Doc>{};
}

/**
 * @param {AbstractUpdateEncoder} encoder
 * @param {Transaction} transaction
 * @return {boolean} Whether data was written.
 */
bool writeUpdateMessageFromTransaction(
    AbstractUpdateEncoder encoder, Transaction transaction) {
  if (transaction.deleteSet.clients.length == 0 &&
      !transaction.afterState.entries.any(
          (entry) => transaction.beforeState.get(entry.key) != entry.value)) {
    return false;
  }
  sortAndMergeDeleteSet(transaction.deleteSet);
  writeStructsFromTransaction(encoder, transaction);
  writeDeleteSet(encoder, transaction.deleteSet);
  return true;
}

/**
 * @param {Transaction} transaction
 *
 * @private
 * @function
 */
ID nextID(Transaction transaction) {
  final y = transaction.doc;
  return createID(y.clientID, getState(y.store, y.clientID));
}

/**
 * If `type.parent` was added in current transaction, `type` technically
 * did not change, it was just added and we should not fire events for `type`.
 *
 * @param {Transaction} transaction
 * @param {AbstractType<YEvent>} type
 * @param {string|null} parentSub
 */
void addChangedTypeToTransaction(
    Transaction transaction, AbstractType<YEvent> type, String? parentSub) {
  final item = type.innerItem;
  if (item == null ||
      (item.id.clock < (transaction.beforeState.get(item.id.client) ?? 0) &&
          !item.deleted)) {
    transaction.changed.putIfAbsent(type, () => {}).add(parentSub);
  }
}

/**
 * @param {List<AbstractStruct>} structs
 * @param {number} pos
 */
void tryToMergeWithLeft(List<AbstractStruct> structs, int pos) {
  final left = structs[pos - 1];
  final right = structs[pos];
  if (left.deleted == right.deleted && left.runtimeType == right.runtimeType) {
    if (left.mergeWith(right)) {
      structs.removeAt(pos);
      if (right is Item &&
          right.parentSub != null &&
          (right.parent as AbstractType).innerMap.get(right.parentSub!) ==
              right) {
        (right.parent as AbstractType)
            .innerMap
            .set(right.parentSub!, /** @type {Item} */ (left as Item));
      }
    }
  }
}

/**
 * @param {DeleteSet} ds
 * @param {StructStore} store
 * @param {function(Item):boolean} gcFilter
 */
void tryGcDeleteSet(
    DeleteSet ds, StructStore store, bool Function(Item) gcFilter) {
  for (final entry in ds.clients.entries) {
    final client = entry.key;
    final deleteItems = entry.value;
    final structs = store.clients.get(client)!;
    for (var di = deleteItems.length - 1; di >= 0; di--) {
      final deleteItem = deleteItems[di];
      final endDeleteItemClock = deleteItem.clock + deleteItem.len;

      for (var si = findIndexSS(structs, deleteItem.clock);
          si < structs.length && structs[si].id.clock < endDeleteItemClock;
          si++) {
        final struct = structs[si];
        if (deleteItem.clock + deleteItem.len <= struct.id.clock) {
          break;
        }
        if (struct is Item &&
            struct.deleted &&
            !struct.keep &&
            gcFilter(struct)) {
          struct.gc(store, false);
        }
      }
    }
  }
}

/**
 * @param {DeleteSet} ds
 * @param {StructStore} store
 */
void tryMergeDeleteSet(DeleteSet ds, StructStore store) {
  // try to merge deleted / gc'd items
  // merge from right to left for better efficiecy and so we don't miss any merge targets
  ds.clients.forEach((client, deleteItems) {
    final structs = /** @type {List<GC|Item>} */ (store.clients.get(client));
    if (structs != null) {
      for (var di = deleteItems.length - 1; di >= 0; di--) {
        final deleteItem = deleteItems[di];
        // start with merging the item next to the last deleted item
        final mostRightIndexToCheck = math.min(structs.length - 1,
            1 + findIndexSS(structs, deleteItem.clock + deleteItem.len - 1));
        for (var si = mostRightIndexToCheck, struct = structs[si];
            si > 0 && struct.id.clock >= deleteItem.clock;
            struct = structs[--si]) {
          tryToMergeWithLeft(structs, si);
        }
      }
    }
  });
}

/**
 * @param {DeleteSet} ds
 * @param {StructStore} store
 * @param {function(Item):boolean} gcFilter
 */
void tryGc(DeleteSet ds, StructStore store, bool Function(Item) gcFilter) {
  tryGcDeleteSet(ds, store, gcFilter);
  tryMergeDeleteSet(ds, store);
}

/**
 * @param {List<Transaction>} transactionCleanups
 * @param {number} i
 */
void cleanupTransactions(List<Transaction> transactionCleanups, int i) {
  if (i < transactionCleanups.length) {
    final transaction = transactionCleanups[i];
    final doc = transaction.doc;
    final store = doc.store;
    final ds = transaction.deleteSet;
    final mergeStructs = transaction.mergeStructs;
    try {
      sortAndMergeDeleteSet(ds);
      transaction.afterState = getStateVector(transaction.doc.store);
      doc.transaction = null;
      doc.emit('beforeObserverCalls', [transaction, doc]);
      /**
       * An array of event callbacks.
       *
       * Each callback is called even if the other ones throw errors.
       *
       * @type {List<function():void>}
       */
      final fs = <void Function()>[];
      // observe events on changed types
      transaction.changed.forEach((itemtype, subs) => fs.add(() {
            if (itemtype.innerItem == null || !itemtype.innerItem!.deleted) {
              itemtype.innerCallObserver(transaction, subs);
            }
          }));
      fs.add(() {
        // deep observe events
        transaction.changedParentTypes.forEach((type, events) => fs.add(() {
              // We need to think about the possibility that the user transforms the
              // Y.Doc in the event.
              if (type.innerItem == null || !type.innerItem!.deleted) {
                events = events
                    .where((event) =>
                        event.target.innerItem == null ||
                        !event.target.innerItem!.deleted)
                    .toList();
                events.forEach((event) {
                  event.currentTarget = type;
                });
                // sort events by path length so that top-level events are fired first.
                events.sort((event1, event2) =>
                    event1.path.length - event2.path.length);
                // We don't need to check for events.length
                // because we know it has at least one element
                callEventHandlerListeners(type.innerdEH, events, transaction);
              }
            }));
        fs.add(() => doc.emit('afterTransaction', [transaction, doc]));
      });
      Object? _err;
      // https://github.com/dart-lang/sdk/issues/30741
      // StackTrace? _stack;
      for (var i = 0; i < fs.length; i++) {
        try {
          fs[i]();
        } catch (e, _) {
          _err = e;
          // _stack = s;
        }
      }
      if (_err != null) {
        throw _err;
      }
    } finally {
      // Replace deleted items with ItemDeleted / GC.
      // This is where content is actually remove from the Yjs Doc.
      if (doc.gc) {
        tryGcDeleteSet(ds, store, doc.gcFilter);
      }
      tryMergeDeleteSet(ds, store);

      // on all affected store.clients props, try to merge
      transaction.afterState.forEach((client, clock) {
        final beforeClock = transaction.beforeState.get(client) ?? 0;
        if (beforeClock != clock) {
          final structs = /** @type {List<GC|Item>} */ (store.clients
              .get(client));
          // we iterate from right to left so we can safely remove entries
          if (structs != null) {
            final firstChangePos =
                math.max(findIndexSS(structs, beforeClock), 1);
            for (var i = structs.length - 1; i >= firstChangePos; i--) {
              tryToMergeWithLeft(structs, i);
            }
          }
        }
      });
      // try to merge mergeStructs
      // @todo: it makes more sense to transform mergeStructs to a DS, sort it, and merge from right to left
      //        but at the moment DS does not handle duplicates
      for (var i = 0; i < mergeStructs.length; i++) {
        final client = mergeStructs[i].id.client;
        final clock = mergeStructs[i].id.clock;
        final structs = /** @type {List<GC|Item>} */ (store.clients
            .get(client));
        if (structs != null) {
          final replacedStructPos = findIndexSS(structs, clock);
          if (replacedStructPos + 1 < structs.length) {
            tryToMergeWithLeft(structs, replacedStructPos + 1);
          }
          if (replacedStructPos > 0) {
            tryToMergeWithLeft(structs, replacedStructPos);
          }
        }
      }
      if (!transaction.local &&
          transaction.afterState.get(doc.clientID) !=
              transaction.beforeState.get(doc.clientID)) {
        doc.clientID = generateNewClientId();
        logger.w(
            'Changed the client-id because another client seems to be using it.');
      }
      // @todo Merge all the transactions into one and provide send the data as a single update message
      doc.emit('afterTransactionCleanup', [transaction, doc]);
      if (doc.innerObservers.containsKey('update')) {
        final encoder = DefaultUpdateEncoder();
        final hasContent =
            writeUpdateMessageFromTransaction(encoder, transaction);
        if (hasContent) {
          doc.emit('update', [encoder.toUint8Array(), transaction.origin, doc]);
        }
      }
      if (doc.innerObservers.containsKey('updateV2')) {
        final encoder = UpdateEncoderV2();
        final hasContent =
            writeUpdateMessageFromTransaction(encoder, transaction);
        if (hasContent) {
          doc.emit(
              'updateV2', [encoder.toUint8Array(), transaction.origin, doc]);
        }
      }
      transaction.subdocsAdded.forEach((subdoc) => doc.subdocs.add(subdoc));
      transaction.subdocsRemoved
          .forEach((subdoc) => doc.subdocs.remove(subdoc));

      doc.emit('subdocs', [
        {
          "loaded": transaction.subdocsLoaded,
          "added": transaction.subdocsAdded,
          "removed": transaction.subdocsRemoved
        },
      ]);
      transaction.subdocsRemoved.forEach((subdoc) => subdoc.destroy());

      if (transactionCleanups.length <= i + 1) {
        doc.transactionCleanups = [];
        doc.emit('afterAllTransactions', [doc, transactionCleanups]);
      } else {
        cleanupTransactions(transactionCleanups, i + 1);
      }
    }
  }
}

/**
 * Implements the functionality of `y.transact(()=>{..})`
 *
 * @param {Doc} doc
 * @param {function(Transaction):void} f
 * @param {any} [origin=true]
 *
 * @function
 */
void transact(Doc doc, void Function(Transaction) f,
    [Object? origin, bool local = true]) {
  final transactionCleanups = doc.transactionCleanups;
  var initialCall = false;
  if (doc.transaction == null) {
    initialCall = true;
    doc.transaction = Transaction(doc, origin, local);
    transactionCleanups.add(doc.transaction!);
    if (transactionCleanups.length == 1) {
      doc.emit('beforeAllTransactions', [doc]);
    }
    doc.emit('beforeTransaction', [doc.transaction, doc]);
  }
  try {
    f(doc.transaction!);
  } finally {
    if (initialCall && transactionCleanups[0] == doc.transaction) {
      // The first transaction ended, now process observer calls.
      // Observer call may create new transactions for which we need to call the observers and do cleanup.
      // We don't want to nest these calls, so we execute these calls one after
      // another.
      // Also we need to ensure that all cleanups are called, even if the
      // observes throw errors.
      // This file is full of hacky try {} finally {} blocks to ensure that an
      // event can throw errors and also that the cleanup is called.
      cleanupTransactions(transactionCleanups, 0);
    }
  }
}
