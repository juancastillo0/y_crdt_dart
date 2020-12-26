// import {
//   mergeDeleteSets,
//   iterateDeletedStructs,
//   keepItem,
//   transact,
//   createID,
//   redoItem,
//   iterateStructs,
//   isParentOf,
//   followRedone,
//   getItemCleanStart,
//   getState,
//   ID,
//   Transaction,
//   Doc,
//   Item,
//   GC,
//   DeleteSet,
//   AbstractType, // eslint-disable-line
// } from "../internals.js";

// import * as time from "lib0/time.js";
// import { Observable } from "lib0/observable.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/is_parent_of.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

import 'observable.dart';

class StackItem {
  /**
   * @param {DeleteSet} ds
   * @param {Map<number,number>} beforeState
   * @param {Map<number,number>} afterState
   */
  StackItem(this.ds, this.beforeState, this.afterState);
  DeleteSet ds;
  final Map<int, int> beforeState;
  Map<int, int> afterState;
  /**
     * Use this to save and restore metadata like selection range
     */
  final Map meta = {};
}

/**
 * @param {UndoManager} undoManager
 * @param {List<StackItem>} stack
 * @param {string} eventType
 * @return {StackItem?}
 */
StackItem? popStackItem(
    UndoManager undoManager, List<StackItem> stack, String eventType) {
  /**
   * Whether a change happened
   * @type {StackItem?}
   */
  StackItem? result;
  final doc = undoManager.doc;
  final scope = undoManager.scope;
  transact(doc, (transaction) {
    while (stack.length > 0 && result == null) {
      final store = doc.store;
      final stackItem = /** @type {StackItem} */ (stack.removeLast());
      /**
         * @type {Set<Item>}
         */
      final itemsToRedo = <Item>{};
      /**
         * @type {List<Item>}
         */
      final itemsToDelete = <Item>[];
      var performedChange = false;
      stackItem.afterState.forEach((client, endClock) {
        final startClock = stackItem.beforeState.get(client) ?? 0;
        final len = endClock - startClock;

        // @todo iterateStructs should not need the structs parameter
        final structs = /** @type {List<GC|Item>} */ (store.clients
            .get(client));
        if (startClock != endClock) {
          // make sure structs don't overlap with the range of created operations [stackItem.start, stackItem.start + stackItem.end)
          // this must be executed before deleted structs are iterated.
          getItemCleanStart(transaction, createID(client, startClock));
          if (endClock < getState(doc.store, client)) {
            getItemCleanStart(transaction, createID(client, endClock));
          }
          iterateStructs(transaction, structs!, startClock, len, (struct) {
            if (struct is Item) {
              if (struct.redone != null) {
                var _v = followRedone(store, struct.id);
                var item = _v.item;
                var diff = _v.diff;
                if (diff > 0) {
                  item = getItemCleanStart(transaction,
                      createID(item.id.client, item.id.clock + diff));
                }
                if (item.length > len) {
                  getItemCleanStart(
                      transaction, createID(item.id.client, endClock));
                }
                struct = item;
              }
              if (!struct.deleted &&
                  struct is Item &&
                  scope.any((type) =>
                      isParentOf(type, /** @type {Item} */ (struct as Item)))) {
                itemsToDelete.add(struct);
              }
            }
          });
        }
      });
      iterateDeletedStructs(transaction, stackItem.ds, (struct) {
        final id = struct.id;
        final clock = id.clock;
        final client = id.client;
        final startClock = stackItem.beforeState.get(client) ?? 0;
        final endClock = stackItem.afterState.get(client) ?? 0;
        if (struct is Item &&
            scope.any((type) => isParentOf(type, struct)) &&
            // Never redo structs in [stackItem.start, stackItem.start + stackItem.end) because they were created and deleted in the same capture interval.
            !(clock >= startClock && clock < endClock)) {
          itemsToRedo.add(struct);
        }
      });
      itemsToRedo.forEach((struct) {
        performedChange = redoItem(transaction, struct, itemsToRedo) != null ||
            performedChange;
      });
      // We want to delete in reverse order so that children are deleted before
      // parents, so we have more information available when items are filtered.
      for (var i = itemsToDelete.length - 1; i >= 0; i--) {
        final item = itemsToDelete[i];
        if (undoManager.deleteFilter(item)) {
          item.delete(transaction);
          performedChange = true;
        }
      }
      result = stackItem;
      if (result != null) {
        undoManager.emit("stack-item-popped", [
          {"stackItem": result, "type": eventType},
          undoManager,
        ]);
      }
    }
    transaction.changed.forEach((type, subProps) {
      // destroy search marker if necessary
      if (subProps.contains(null) && type.innerSearchMarker != null) {
        type.innerSearchMarker!.length = 0;
      }
    });
  }, undoManager);
  return result;
}

/**
 * @typedef {Object} UndoManagerOptions
 * @property {number} [UndoManagerOptions.captureTimeout=500]
 * @property {function(Item):boolean} [UndoManagerOptions.deleteFilter=()=>true] Sometimes
 * it is necessary to filter whan an Undo/Redo operation can delete. If this
 * filter returns false, the type/item won't be deleted even it is in the
 * undo/redo scope.
 * @property {Set<any>} [UndoManagerOptions.trackedOrigins=new Set([null])]
 */

bool _defaultDeleteFilter(Item _) => true;

/**
 * Fires 'stack-item-added' event when a stack item was added to either the undo- or
 * the redo-stack. You may store additional stack information via the
 * metadata property on `event.stackItem.meta` (it is a `Map` of metadata properties).
 * Fires 'stack-item-popped' event when a stack item was popped from either the
 * undo- or the redo-stack. You may restore the saved stack information from `event.stackItem.meta`.
 *
 * @extends {Observable<'stack-item-added'|'stack-item-popped'>}
 */
class UndoManager extends Observable {
  /**
   * @param {AbstractType<any>|List<AbstractType<any>>} typeScope Accepts either a single type, or an array of types
   * @param {UndoManagerOptions} options
   */
  UndoManager(
    ValueOrList<AbstractType> typeScope, {
    int captureTimeout = 500,
    this.deleteFilter = _defaultDeleteFilter,
    this.trackedOrigins = const {
      [null]
    },
  }) {
    this.scope = typeScope.when(
      list: (v) => v,
      value: (v) => [v],
    );
    this.doc = /** @type {Doc} */ (this.scope[0].doc!);
    trackedOrigins.add(this);

    this.doc.on("afterTransaction",
        /** @param {Transaction} transaction */ (args) {
      final transaction = args[0] as Transaction;
      // Only track certain transactions
      if (!this.scope.any(
              (type) => transaction.changedParentTypes.containsKey(type)) ||
          (!this.trackedOrigins.contains(transaction.origin) &&
              (transaction.origin == null ||
                  !this
                      .trackedOrigins
                      .contains(transaction.origin.runtimeType)))) {
        return;
      }
      final undoing = this.undoing;
      final redoing = this.redoing;
      final stack = undoing ? this.redoStack : this.undoStack;
      if (undoing) {
        this.stopCapturing(); // next undo should not be appended to last stack item
      } else if (!redoing) {
        // neither undoing nor redoing: delete redoStack
        this.redoStack = [];
      }
      final beforeState = transaction.beforeState;
      final afterState = transaction.afterState;
      // TODO: is milliseconds?
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - this.lastChange < captureTimeout &&
          stack.length > 0 &&
          !undoing &&
          !redoing) {
        // append change to last stack op
        final lastOp = stack[stack.length - 1];
        lastOp.ds = mergeDeleteSets([lastOp.ds, transaction.deleteSet]);
        lastOp.afterState = afterState;
      } else {
        // create a new stack op
        stack.add(StackItem(transaction.deleteSet, beforeState, afterState));
      }
      if (!undoing && !redoing) {
        this.lastChange = now;
      }
      // make sure that deleted structs are not gc'd
      iterateDeletedStructs(transaction, transaction.deleteSet,
          /** @param {Item|GC} item */ (item) {
        if (item is Item && this.scope.any((type) => isParentOf(type, item))) {
          keepItem(item, true);
        }
      });
      this.emit("stack-item-added", [
        {
          "stackItem": stack[stack.length - 1],
          "origin": transaction.origin,
          "type": undoing ? "redo" : "undo",
        },
        this,
      ]);
    });
  }

  late final List<AbstractType<dynamic>> scope;
  Set<dynamic> trackedOrigins;

  final bool Function(Item) deleteFilter;
  /**
     * @type {List<StackItem>}
     */
  List<StackItem> undoStack = [];
  /**
     * @type {List<StackItem>}
     */
  List<StackItem> redoStack = [];
  /**
     * Whether the client is currently undoing (calling UndoManager.undo)
     *
     * @type {boolean}
     */
  bool undoing = false;
  bool redoing = false;
  late final Doc doc;
  int lastChange = 0;

  void clear() {
    this.doc.transact((transaction) {
      /**
       * @param {StackItem} stackItem
       */
      void clearItem(StackItem stackItem) {
        iterateDeletedStructs(transaction, stackItem.ds, (item) {
          if (item is Item &&
              this.scope.any((type) => isParentOf(type, item))) {
            keepItem(item, false);
          }
        });
      }

      this.undoStack.forEach(clearItem);
      this.redoStack.forEach(clearItem);
    });
    this.undoStack = [];
    this.redoStack = [];
  }

  /**
   * UndoManager merges Undo-StackItem if they are created within time-gap
   * smaller than `options.captureTimeout`. Call `um.stopCapturing()` so that the next
   * StackItem won't be merged.
   *
   *
   * @example
   *     // without stopCapturing
   *     ytext.insert(0, 'a')
   *     ytext.insert(1, 'b')
   *     um.undo()
   *     ytext.toString() // => '' (note that 'ab' was removed)
   *     // with stopCapturing
   *     ytext.insert(0, 'a')
   *     um.stopCapturing()
   *     ytext.insert(0, 'b')
   *     um.undo()
   *     ytext.toString() // => 'a' (note that only 'b' was removed)
   *
   */
  void stopCapturing() {
    this.lastChange = 0;
  }

  /**
   * Undo last changes on type.
   *
   * @return {StackItem?} Returns StackItem if a change was applied
   */
  StackItem? undo() {
    this.undoing = true;
    final res;
    try {
      res = popStackItem(this, this.undoStack, "undo");
    } finally {
      this.undoing = false;
    }
    return res;
  }

  /**
   * Redo last undo operation.
   *
   * @return {StackItem?} Returns StackItem if a change was applied
   */
  StackItem? redo() {
    this.redoing = true;
    var res;
    try {
      res = popStackItem(this, this.redoStack, "redo");
    } finally {
      this.redoing = false;
    }
    return res;
  }
}

abstract class ValueOrList<V> {
  const ValueOrList._();

  const factory ValueOrList.list(
    List<V> list,
  ) = _List;
  const factory ValueOrList.value(
    V value,
  ) = _Value;

  T when<T>({
    required T Function(List<V> list) list,
    required T Function(V value) value,
  }) {
    final v = this;
    if (v is _List<V>) return list(v.list);
    if (v is _Value<V>) return value(v.value);
    throw "";
  }

  T? maybeWhen<T>({
    T Function()? orElse,
    T Function(List<V> list)? list,
    T Function(V value)? value,
  }) {
    final v = this;
    if (v is _List<V>) return list != null ? list(v.list) : orElse?.call();
    if (v is _Value<V>) return value != null ? value(v.value) : orElse?.call();
    throw "";
  }

  T map<T>({
    required T Function(_List value) list,
    required T Function(_Value value) value,
  }) {
    final v = this;
    if (v is _List<V>) return list(v);
    if (v is _Value<V>) return value(v);
    throw "";
  }

  T? maybeMap<T>({
    T Function()? orElse,
    T Function(_List value)? list,
    T Function(_Value value)? value,
  }) {
    final v = this;
    if (v is _List<V>) return list != null ? list(v) : orElse?.call();
    if (v is _Value<V>) return value != null ? value(v) : orElse?.call();
    throw "";
  }
}

class _List<V> extends ValueOrList<V> {
  final List<V> list;

  const _List(
    this.list,
  ) : super._();
}

class _Value<V> extends ValueOrList<V> {
  final V value;

  const _Value(
    this.value,
  ) : super._();
}
