// import {
//   isDeleted,
//   Item,
//   AbstractType,
//   Transaction,
//   AbstractStruct, // eslint-disable-line
// } from "../internals.js";

// import * as set from "lib0/set.js";
// import * as array from "lib0/array.js";

import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

/**
 * YEvent describes the changes on a YType.
 */
class YEvent {
  /**
   * @param {AbstractType<any>} target The changed type.
   * @param {Transaction} transaction
   */
  YEvent(this.target, this.transaction) : currentTarget = target;
  /**
     * The type on which this event was created on.
     * @type {AbstractType<any>}
     */
  final AbstractType<YEvent> target;
  /**
     * The current target on which the observe callback is called.
     * @type {AbstractType<any>}
     */
  AbstractType currentTarget;
  /**
     * The transaction that triggered this event.
     * @type {Transaction}
     */
  Transaction transaction;
  /**
     * @type {Object|null}
     */
  YChanges? _changes;

  /**
   * Computes the path from `y` to the changed type.
   *
   * The following property holds:
   * @example
   *   var type = y
   *   event.path.forEach(dir => {
   *     type = type.get(dir)
   *   })
   *   type == event.target // => true
   */
  List get path {
    // @ts-ignore _item is defined because target is integrated
    return getPathTo(this.currentTarget, this.target);
  }

  /**
   * Check if a struct is deleted by this event.
   *
   * In contrast to change.deleted, this method also returns true if the struct was added and then deleted.
   *
   * @param {AbstractStruct} struct
   * @return {boolean}
   */
  bool deletes(AbstractStruct struct) {
    return isDeleted(this.transaction.deleteSet, struct.id);
  }

  /**
   * Check if a struct is added by this event.
   *
   * In contrast to change.deleted, this method also returns true if the struct was added and then deleted.
   *
   * @param {AbstractStruct} struct
   * @return {boolean}
   */
  bool adds(AbstractStruct struct) {
    return (struct.id.clock >=
        (this.transaction.beforeState.get(struct.id.client) ?? 0));
  }

  /**
   * @return {{added:Set<Item>,deleted:Set<Item>,keys:Map<string,{action:'add'|'update'|'delete',oldValue:any}>,delta:List<{insert:List<any>}|{delete:number}|{retain:number}>}}
   */
  YChanges get changes {
    var changes = this._changes;
    if (changes == null) {
      final target = this.target;
      final added = <Item>{};
      final deleted = <Item>{};
      /**
       * @type {List<{insert:List<any>}|{delete:number}|{retain:number}>}
       */
      final delta = <YDelta>[];
      /**
       * @type {Map<string,{ action: 'add' | 'update' | 'delete', oldValue: any}>}
       */
      final keys = <String, _Change>{};
      changes = YChanges(
        added: added,
        deleted: deleted,
        delta: delta,
        keys: keys,
      );
      final changed = /** @type Set<string|null> */ (this
          .transaction
          .changed
          .get(target));
      if (changed!.contains(null)) {
        /**
         * @type {any}
         */
        YDelta? lastOp;
        void packOp() {
          if (lastOp != null) {
            delta.add(lastOp);
          }
        }

        for (var item = target.innerStart; item != null; item = item.right) {
          if (item.deleted) {
            if (this.deletes(item) && !this.adds(item)) {
              if (lastOp == null || lastOp.type != _DeltaType.delete) {
                packOp();
                lastOp = YDelta.delete(0);
              }
              lastOp.amount = lastOp.amount! + item.length;
              deleted.add(item);
            } // else nop
          } else {
            if (this.adds(item)) {
              if (lastOp == null || lastOp.type != _DeltaType.insert) {
                packOp();
                lastOp = YDelta.insert([]);
              }
              lastOp.inserts = [
                ...lastOp.inserts!,
                ...item.content.getContent(),
              ];
              added.add(item);
            } else {
              if (lastOp == null || lastOp.type != _DeltaType.retain) {
                packOp();
                lastOp = YDelta.retain(0);
              }
              lastOp.amount = lastOp.amount! + item.length;
            }
          }
        }
        if (lastOp != null && lastOp.amount == null) {
          packOp();
        }
      }
      changed.forEach((key) {
        if (key != null) {
          final item = /** @type {Item} */ (target.innerMap.get(key));
          /**
           * @type {'delete' | 'add' | 'update'}
           */
          _ChangeType action;
          var oldValue;
          if (this.adds(item!)) {
            var prev = item.left;
            while (prev != null && this.adds(prev)) {
              prev = prev.left;
            }
            if (this.deletes(item)) {
              if (prev != null && this.deletes(prev)) {
                action = _ChangeType.delete;
                oldValue = prev.content.getContent().last;
              } else {
                return;
              }
            } else {
              if (prev != null && this.deletes(prev)) {
                action = _ChangeType.update;
                oldValue = prev.content.getContent().last;
              } else {
                action = _ChangeType.add;
                oldValue = null;
              }
            }
          } else {
            if (this.deletes(item)) {
              action = _ChangeType.delete;
              oldValue =
                  /** @type {Item} */ item.content.getContent().last;
            } else {
              return; // nop
            }
          }
          keys.set(key, _Change(action, oldValue));
        }
      });
      this._changes = changes;
    }
    return /** @type {any} */ (changes);
  }
}

class YChanges {
  final Set<Item> added;
  final Set<Item> deleted;
  final Map<String, _Change> keys;
  final List<YDelta> delta;

  YChanges({
    required this.added,
    required this.deleted,
    required this.keys,
    required this.delta,
  });
}

enum _ChangeType { add, update, delete }

class _Change {
  final _ChangeType action;
  final Object oldValue;

  _Change(this.action, this.oldValue);
}

enum _DeltaType { insert, retain, delete }

class YDelta {
  _DeltaType type;
  List<dynamic>? inserts;
  int? amount;

  factory YDelta.insert(List<dynamic> inserts) {
    return YDelta._(_DeltaType.insert, inserts, null);
  }
  factory YDelta.retain(int amount) {
    return YDelta._(_DeltaType.retain, null, amount);
  }
  factory YDelta.delete(int amount) {
    return YDelta._(_DeltaType.delete, null, amount);
  }
  YDelta._(this.type, this.inserts, this.amount);
}

/**
 * Compute the path from this type to the specified target.
 *
 * @example
 *   // `child` should be accessible via `type.get(path[0]).get(path[1])..`
 *   const path = type.getPathTo(child)
 *   // assuming `type is YArray`
 *   console.log(path) // might look like => [2, 'key1']
 *   child == type.get(path[0]).get(path[1])
 *
 * @param {AbstractType<any>} parent
 * @param {AbstractType<any>} child target
 * @return {List<string|number>} Path to the target
 *
 * @private
 * @function
 */
List getPathTo(AbstractType parent, AbstractType child) {
  final path = [];
  var childItem = child.innerItem;
  while (childItem != null && child != parent) {
    if (childItem.parentSub != null) {
      // parent is map-ish
      path.insert(0, childItem.parentSub);
    } else {
      // parent is array-ish
      var i = 0;
      var c = /** @type {AbstractType<any>} */ (childItem.parent
              as AbstractType)
          .innerStart;
      while (c != childItem && c != null) {
        if (!c.deleted) {
          i++;
        }
        c = c.right;
      }
      path.insert(0, i);
    }
    child = /** @type {AbstractType<any>} */ (childItem.parent as AbstractType);
    childItem = child.innerItem;
  }
  return path;
}
