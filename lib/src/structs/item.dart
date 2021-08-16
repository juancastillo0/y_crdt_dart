// import {
//   GC,
//   getState,
//   AbstractStruct,
//   replaceStruct,
//   addStruct,
//   addToDeleteSet,
//   findRootTypeKey,
//   compareIDs,
//   getItem,
//   getItemCleanEnd,
//   getItemCleanStart,
//   readContentDeleted,
//   readContentBinary,
//   readContentJSON,
//   readContentAny,
//   readContentString,
//   readContentEmbed,
//   readContentDoc,
//   createID,
//   readContentFormat,
//   readContentType,
//   addChangedTypeToTransaction,
//   AbstractUpdateDecoder, AbstractUpdateEncoder, ContentType, ContentDeleted, StructStore, ID, AbstractType, Transaction // eslint-disable-line
// } from '../internals.js'

import 'package:y_crdt/src/lib0/binary.dart' as binary;
// import * as error from 'lib0/error.js'
// import * as binary from 'lib0/binary.js'

import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/structs/content_any.dart';
import 'package:y_crdt/src/structs/content_binary.dart';
import 'package:y_crdt/src/structs/content_deleted.dart';
import 'package:y_crdt/src/structs/content_doc.dart';
import 'package:y_crdt/src/structs/content_embed.dart';
import 'package:y_crdt/src/structs/content_format.dart';
import 'package:y_crdt/src/structs/content_json.dart';
import 'package:y_crdt/src/structs/content_string.dart';
import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/gc.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/utils/y_event.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

export 'package:y_crdt/src/structs/content_any.dart' show readContentAny;
export 'package:y_crdt/src/structs/content_binary.dart' show readContentBinary;
export 'package:y_crdt/src/structs/content_deleted.dart'
    show readContentDeleted;
export 'package:y_crdt/src/structs/content_doc.dart' show readContentDoc;
export 'package:y_crdt/src/structs/content_embed.dart' show readContentEmbed;
export 'package:y_crdt/src/structs/content_format.dart' show readContentFormat;
export 'package:y_crdt/src/structs/content_json.dart' show readContentJSON;
export 'package:y_crdt/src/structs/content_string.dart' show readContentString;
export 'package:y_crdt/src/structs/content_type.dart' show readContentType;

/**
 * @todo This should return several items
 *
 * @param {StructStore} store
 * @param {ID} id
 * @return {{item:Item, diff:number}}
 */
_R followRedone(StructStore store, ID id) {
  /**
   * @type {ID|null}
   */
  ID? nextID = id;
  var diff = 0;
  Item item;
  do {
    if (nextID == null) {
      throw Error();
    }
    if (diff > 0) {
      nextID = createID(nextID.client, nextID.clock + diff);
    }
    item = getItem(store, nextID) as Item;
    diff = nextID.clock - item.id.clock;
    nextID = item.redone;
  } while (nextID != null && item is Item);

  return _R(item, diff);
}

class _R {
  final Item item;
  final int diff;

  const _R(this.item, this.diff);
}

/**
 * Make sure that neither item nor any of its parents is ever deleted.
 *
 * This property does not persist when storing it into a database or when
 * sending it to other peers
 *
 * @param {Item|null} item
 * @param {boolean} keep
 */
void keepItem(item, keep) {
  while (item != null && item.keep != keep) {
    item.keep = keep;
    item = /** @type {AbstractType<any>} */ (item.parent as AbstractType)
        .innerItem;
  }
}

/**
 * Split leftItem into two items
 * @param {Transaction} transaction
 * @param {Item} leftItem
 * @param {number} diff
 * @return {Item}
 *
 * @function
 * @private
 */
Item splitItem(Transaction transaction, Item leftItem, int diff) {
  // create rightItem
  final client = leftItem.id.client;
  final clock = leftItem.id.clock;
  final rightItem = Item(
      createID(client, clock + diff),
      leftItem,
      createID(client, clock + diff - 1),
      leftItem.right,
      leftItem.rightOrigin,
      leftItem.parent,
      leftItem.parentSub,
      leftItem.content.splice(diff));
  if (leftItem.deleted) {
    rightItem.markDeleted();
  }
  if (leftItem.keep) {
    rightItem.keep = true;
  }
  final leftItemRedone = leftItem.redone;
  if (leftItemRedone != null) {
    rightItem.redone =
        createID(leftItemRedone.client, leftItemRedone.clock + diff);
  }
  // update left (do not set leftItem.rightOrigin as it will lead to problems when syncing)
  leftItem.right = rightItem;
  // update right
  if (rightItem.right != null) {
    rightItem.right!.left = rightItem;
  }
  // right is more specific.
  transaction.mergeStructs.add(rightItem);
  // update parent._map
  if (rightItem.parentSub != null && rightItem.right == null) {
    /** @type {AbstractType<any>} */ (rightItem.parent as AbstractType)
        .innerMap
        .set(rightItem.parentSub!, rightItem);
  }
  leftItem.length = diff;
  return rightItem;
}

/**
 * Redoes the effect of this operation.
 *
 * @param {Transaction} transaction The Yjs instance.
 * @param {Item} item
 * @param {Set<Item>} redoitems
 *
 * @return {Item|null}
 *
 * @private
 */
Item? redoItem(Transaction transaction, Item item, Set<Item> redoitems) {
  final doc = transaction.doc;
  final store = doc.store;
  final ownClientID = doc.clientID;
  final redone = item.redone;
  if (redone != null) {
    return getItemCleanStart(transaction, redone);
  }
  Item? parentItem =
      /** @type {AbstractType<any>} */ (item.parent as AbstractType).innerItem;
  /**
   * @type {Item|null}
   */
  Item? left;
  /**
   * @type {Item|null}
   */
  Item? right;
  if (item.parentSub == null) {
    // Is an array item. Insert at the old position
    left = item.left;
    right = item;
  } else {
    // Is a map item. Insert as current value
    left = item;
    while (left!.right != null) {
      left = left.right;
      if (left!.id.client != ownClientID) {
        // It is not possible to redo this item because it conflicts with a
        // change from another client
        return null;
      }
    }
    if (left.right != null) {
      left = /** @type {Item} */ /** @type {AbstractType<any>} */ (item.parent
              as AbstractType)
          .innerMap
          .get(item.parentSub!);
    }
    right = null;
  }
  // make sure that parent is redone
  if (parentItem != null &&
      parentItem.deleted == true &&
      parentItem.redone == null) {
    // try to undo parent if it will be undone anyway
    if (!redoitems.contains(parentItem) ||
        redoItem(transaction, parentItem, redoitems) == null) {
      return null;
    }
  }
  if (parentItem != null && parentItem.redone != null) {
    while (parentItem?.redone != null) {
      parentItem = getItemCleanStart(transaction, parentItem!.redone!);
    }
    // find next cloned_redo items
    while (left != null) {
      /**
       * @type {Item|null}
       */
      Item? leftTrace = left;
      // trace redone until parent matches
      while (leftTrace != null &&
          (leftTrace.parent as AbstractType).innerItem != parentItem) {
        leftTrace = leftTrace.redone == null
            ? null
            : getItemCleanStart(transaction, leftTrace.redone!);
      }
      if (leftTrace != null &&
          (leftTrace.parent as AbstractType).innerItem == parentItem) {
        left = leftTrace;
        break;
      }
      left = left.left;
    }
    while (right != null) {
      /**
       * @type {Item|null}
       */
      Item? rightTrace = right;
      // trace redone until parent matches
      while (rightTrace != null &&
          (rightTrace.parent as AbstractType).innerItem != parentItem) {
        rightTrace = rightTrace.redone == null
            ? null
            : getItemCleanStart(transaction, rightTrace.redone!);
      }
      if (rightTrace != null &&
          (rightTrace.parent as AbstractType).innerItem == parentItem) {
        right = rightTrace;
        break;
      }
      right = right.right;
    }
  }
  final nextClock = getState(store, ownClientID);
  final nextId = createID(ownClientID, nextClock);
  final redoneItem = Item(
      nextId,
      left,
      left?.lastId,
      right,
      right?.id,
      parentItem == null
          ? item.parent
          : /** @type {ContentType} */ (parentItem.content as ContentType).type,
      item.parentSub,
      item.content.copy());
  item.redone = nextId;
  keepItem(redoneItem, true);
  redoneItem.integrate(transaction, 0);
  return redoneItem;
}

/**
 * Abstract class that represents any content.
 */
class Item extends AbstractStruct {
  /**
   * @param {ID} id
   * @param {Item | null} left
   * @param {ID | null} origin
   * @param {Item | null} right
   * @param {ID | null} rightOrigin
   * @param {AbstractType<any>|ID|null} parent Is a type if integrated, is null if it is possible to copy parent from left or right, is ID before integration to search for it.
   * @param {string | null} parentSub
   * @param {AbstractContent} content
   */
  Item(ID id, this.left, this.origin, this.right, this.rightOrigin, this.parent,
      this.parentSub, this.content)
      : info = content.isCountable() ? binary.BIT2 : 0,
        super(id, content.getLength());

  /**
     * The item that was originally to the left of this item.
     * @type {ID | null}
     */
  ID? origin;
  /**
     * The item that is currently to the left of this item.
     * @type {Item | null}
     */
  Item? left;
  /**
     * The item that is currently to the right of this item.
     * @type {Item | null}
     */
  Item? right;
  /**
     * The item that was originally to the right of this item.
     * @type {ID | null}
     */
  ID? rightOrigin;
  /**
     * @type {AbstractType<any>|ID|null}
     */
  Object? parent;
  /**
     * If the parent refers to this item with some kind of key (e.g. YMap, the
     * key is specified here. The key is then used to refer to the list in which
     * to insert this item. If `parentSub = null` type._start is the list in
     * which to insert to. Otherwise it is `parent._map`.
     * @type {String | null}
     */
  String? parentSub;
  /**
     * If this type's effect is reundone this type refers to the type that undid
     * this operation.
     * @type {ID | null}
     */
  ID? redone;
  /**
     * @type {AbstractContent}
     */
  AbstractContent content;
  /**
     * bit1: keep
     * bit2: countable
     * bit3: deleted
     * bit4: mark - mark node as fast-search-marker
     * @type {number} byte
     */
  int info;

  /**
   * This is used to mark the item as an indexed fast-search marker
   *
   * @type {boolean}
   */
  set marker(bool isMarked) {
    if (((this.info & binary.BIT4) > 0) != isMarked) {
      this.info ^= binary.BIT4;
    }
  }

  bool get marker {
    return (this.info & binary.BIT4) > 0;
  }

  /**
   * If true, do not garbage collect this Item.
   */
  bool get keep {
    return (this.info & binary.BIT1) > 0;
  }

  set keep(bool doKeep) {
    if (this.keep != doKeep) {
      this.info ^= binary.BIT1;
    }
  }

  bool get countable {
    return (this.info & binary.BIT2) > 0;
  }

  /**
   * Whether this item was deleted or not.
   * @type {Boolean}
   */
  @override
  bool get deleted {
    return (this.info & binary.BIT3) > 0;
  }

  set deleted(doDelete) {
    if (this.deleted != doDelete) {
      this.info ^= binary.BIT3;
    }
  }

  void markDeleted() {
    this.info |= binary.BIT3;
  }

  /**
   * Return the creator clientID of the missing op or define missing items and return null.
   *
   * @param {Transaction} transaction
   * @param {StructStore} store
   * @return {null | number}
   */
  int? getMissing(Transaction transaction, StructStore store) {
    final _origin = this.origin;
    if (_origin != null &&
        _origin.client != this.id.client &&
        _origin.clock >= getState(store, _origin.client)) {
      return _origin.client;
    }
    final _rightOrigin = this.rightOrigin;
    if (_rightOrigin != null &&
        _rightOrigin.client != this.id.client &&
        _rightOrigin.clock >= getState(store, _rightOrigin.client)) {
      return _rightOrigin.client;
    }
    final _parent = this.parent;
    if (_parent != null &&
        _parent is ID &&
        this.id.client != _parent.client &&
        _parent.clock >= getState(store, _parent.client)) {
      return _parent.client;
    }

    // We have all missing ids, now find the items

    if (_origin != null) {
      this.left = getItemCleanEnd(transaction, store, _origin);
      this.origin = this.left!.lastId;
    }
    if (this.rightOrigin != null) {
      this.right = getItemCleanStart(transaction, this.rightOrigin!);
      this.rightOrigin = this.right!.id;
    }
    if (this.left is GC || this.right is GC) {
      this.parent = null;
    }
    // only set parent if this shouldn't be garbage collected
    if (this.parent == null) {
      final _left = this.left;
      if (_left is Item) {
        this.parent = _left.parent;
        this.parentSub = _left.parentSub;
      }
      final _right = this.right;
      if (_right is Item) {
        this.parent = _right.parent;
        this.parentSub = _right.parentSub;
      }
    } else if (this.parent is ID) {
      final parentItem = getItem(store, this.parent as ID);
      // if (parentItem is GC) {
      //   this.parent = null;
      // } else
      if (parentItem is Item && parentItem.content is ContentType) {
        // TODO:
        this.parent = (parentItem.content as ContentType).type;
      } else {
        this.parent = null;
      }
    }
    return null;
  }

  /**
   * @param {Transaction} transaction
   * @param {number} offset
   */
  @override
  void integrate(Transaction transaction, int offset) {
    if (offset > 0) {
      this.id.clock += offset;
      this.left = getItemCleanEnd(
        transaction,
        transaction.doc.store,
        createID(this.id.client, this.id.clock - 1),
      );
      this.origin = this.left!.lastId;
      this.content = this.content.splice(offset);
      this.length -= offset;
    }

    if (this.parent != null) {
      if ((this.left == null &&
              (this.right == null || this.right!.left != null)) ||
          (this.left != null && this.left!.right != this.right)) {
        /**
         * @type {Item|null}
         */
        Item? left = this.left;

        /**
         * @type {Item|null}
         */
        Item? o;
        // set o to the first conflicting item
        if (left != null) {
          o = left.right;
        } else if (this.parentSub != null) {
          o = /** @type {AbstractType<any>} */ (this.parent as AbstractType)
              .innerMap
              .get(this.parentSub!);
          while (o != null && o.left != null) {
            o = o.left;
          }
        } else {
          o = /** @type {AbstractType<any>} */ (this.parent as AbstractType)
              .innerStart;
        }
        // TODO: use something like DeleteSet here (a tree implementation would be best)
        // @todo use global set definitions
        /**
         * @type {Set<Item>}
         */
        final conflictingItems = <Item>{};
        /**
         * @type {Set<Item>}
         */
        final itemsBeforeOrigin = <Item>{};
        // var c in conflictingItems, b in itemsBeforeOrigin
        // ***{origin}bbbb{this}{c,b}{c,b}{o}***
        // Note that conflictingItems is a subset of itemsBeforeOrigin
        while (o != null && o != this.right) {
          itemsBeforeOrigin.add(o);
          conflictingItems.add(o);
          if (compareIDs(this.origin, o.origin)) {
            // case 1
            if (o.id.client < this.id.client) {
              left = o;
              conflictingItems.clear();
            } else if (compareIDs(this.rightOrigin, o.rightOrigin)) {
              // this and o are conflicting and point to the same integration points. The id decides which item comes first.
              // Since this is to the left of o, we can break here
              break;
            } // else, o might be integrated before an item that this conflicts with. If so, we will find it in the next iterations
          } else if (o.origin != null &&
              itemsBeforeOrigin
                  .contains(getItem(transaction.doc.store, o.origin!))) {
            // use getItem instead of getItemCleanEnd because we don't want / need to split items.
            // case 2
            if (!conflictingItems
                .contains(getItem(transaction.doc.store, o.origin!))) {
              left = o;
              conflictingItems.clear();
            }
          } else {
            break;
          }
          o = o.right;
        }
        this.left = left;
      }
      // reconnect left/right + update parent map/start if necessary
      final _left = this.left;
      if (_left != null) {
        final right = _left.right;
        this.right = right;
        _left.right = this;
      } else {
        Item? r;
        if (this.parentSub != null) {
          r = /** @type {AbstractType<any>} */ (this.parent as AbstractType)
              .innerMap
              .get(this.parentSub!);
          while (r != null && r.left != null) {
            r = r.left;
          }
        } else {
          r = /** @type {AbstractType<any>} */ (this.parent as AbstractType)
              .innerStart;
          /** @type {AbstractType<any>} */
          (this.parent as AbstractType).innerStart = this;
        }
        this.right = r;
      }
      if (this.right != null) {
        this.right!.left = this;
      } else if (this.parentSub != null) {
        // set as current parent value if right == null and this is parentSub
        /** @type {AbstractType<any>} */ (this.parent as AbstractType)
            .innerMap
            .set(this.parentSub!, this);
        if (this.left != null) {
          // this is the current attribute value of parent. delete right
          this.left!.delete(transaction);
        }
      }
      // adjust length of parent
      if (this.parentSub == null && this.countable && !this.deleted) {
        /** @type {AbstractType<any>} */ (this.parent as AbstractType)
            .innerLength += this.length;
      }
      addStruct(transaction.doc.store, this);
      this.content.integrate(transaction, this);
      // add parent to transaction.changed
      final _parent = this.parent;
      if (_parent is AbstractType<YEvent>) {
        addChangedTypeToTransaction(transaction, _parent, this.parentSub);
        if ((_parent.innerItem != null && _parent.innerItem!.deleted) ||
            (this.parentSub != null && this.right != null)) {
          // delete if parent is deleted or if this is not the current attribute value of parent
          this.delete(transaction);
        }
      }
    } else {
      // parent is not defined. Integrate GC struct instead
      GC(this.id, this.length).integrate(transaction, 0);
    }
  }

  /**
   * Returns the next non-deleted item
   */
  Item? get next {
    var n = this.right;
    while (n != null && n.deleted) {
      n = n.right;
    }
    return n;
  }

  /**
   * Returns the previous non-deleted item
   */
  Item? get prev {
    var n = this.left;
    while (n != null && n.deleted) {
      n = n.left;
    }
    return n;
  }

  /**
   * Computes the last content address of this Item.
   */
  ID get lastId {
    // allocating ids is pretty costly because of the amount of ids created, so we try to reuse whenever possible
    return this.length == 1
        ? this.id
        : createID(this.id.client, this.id.clock + this.length - 1);
  }

  /**
   * Try to merge two items
   *
   * @param {Item} right
   * @return {boolean}
   */
  @override
  bool mergeWith(AbstractStruct right) {
    if (right is! Item) {
      return false;
    }
    if (compareIDs(right.origin, this.lastId) &&
        this.right == right &&
        compareIDs(this.rightOrigin, right.rightOrigin) &&
        this.id.client == right.id.client &&
        this.id.clock + this.length == right.id.clock &&
        this.deleted == right.deleted &&
        this.redone == null &&
        right.redone == null &&
        this.content.runtimeType == right.content.runtimeType &&
        this.content.mergeWith(right.content)) {
      if (right.keep) {
        this.keep = true;
      }
      this.right = right.right;
      if (this.right != null) {
        this.right!.left = this;
      }
      this.length += right.length;
      return true;
    }
    return false;
  }

  /**
   * Mark this Item as deleted.
   *
   * @param {Transaction} transaction
   */
  void delete(Transaction transaction) {
    if (!this.deleted) {
      final parent =
          /** @type {AbstractType<any>} */ this.parent as AbstractType<YEvent>;
      // adjust the length of parent
      if (this.countable && this.parentSub == null) {
        parent.innerLength -= this.length;
      }
      this.markDeleted();
      addToDeleteSet(
        transaction.deleteSet,
        this.id.client,
        this.id.clock,
        this.length,
      );

      addChangedTypeToTransaction(transaction, parent, this.parentSub);
      this.content.delete(transaction);
    }
  }

  /**
   * @param {StructStore} store
   * @param {boolean} parentGCd
   */
  void gc(StructStore store, bool parentGCd) {
    if (!this.deleted) {
      throw Exception('Unexpected case');
    }
    this.content.gc(store);
    if (parentGCd) {
      replaceStruct(store, this, GC(this.id, this.length));
    } else {
      this.content = ContentDeleted(this.length);
    }
  }

  /**
   * Transform the properties of this type to binary and write it to an
   * BinaryEncoder.
   *
   * This is called when this Item is sent to a remote peer.
   *
   * @param {AbstractUpdateEncoder} encoder The encoder to write data to.
   * @param {number} offset
   */
  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    final origin = offset > 0
        ? createID(this.id.client, this.id.clock + offset - 1)
        : this.origin;
    final rightOrigin = this.rightOrigin;
    final parentSub = this.parentSub;
    final info = (this.content.getRef() & binary.BITS5) |
        (origin == null ? 0 : binary.BIT8) | // origin is defined
        (rightOrigin == null ? 0 : binary.BIT7) | // right origin is defined
        (parentSub == null ? 0 : binary.BIT6); // parentSub is non-null
    encoder.writeInfo(info);
    if (origin != null) {
      encoder.writeLeftID(origin);
    }
    if (rightOrigin != null) {
      encoder.writeRightID(rightOrigin);
    }
    if (origin == null && rightOrigin == null) {
      final parent =
          /** @type {AbstractType<any>} */ this.parent as AbstractType;
      final parentItem = parent.innerItem;
      if (parentItem == null) {
        // parent type on y._map
        // find the correct key
        final ykey = findRootTypeKey(parent);
        encoder.writeParentInfo(true); // write parentYKey
        encoder.writeString(ykey);
      } else {
        encoder.writeParentInfo(false); // write parent id
        encoder.writeLeftID(parentItem.id);
      }
      if (parentSub != null) {
        encoder.writeString(parentSub);
      }
    }
    this.content.write(encoder, offset);
  }
}

/**
 * @param {AbstractUpdateDecoder} decoder
 * @param {number} info
 */
dynamic readItemContent(AbstractUpdateDecoder decoder, int info) =>
    contentRefs[info & binary.BITS5](decoder);

/**
 * A lookup map for reading Item content.
 *
 * @type {List<function(AbstractUpdateDecoder):AbstractContent>}
 */
final contentRefs = [
  () {
    throw Exception('Unexpected case');
  }, // GC is not ItemContent
  readContentDeleted, // 1
  readContentJSON, // 2
  readContentBinary, // 3
  readContentString, // 4
  readContentEmbed, // 5
  readContentFormat, // 6
  readContentType, // 7
  readContentAny, // 8
  readContentDoc // 9
];

/**
 * Do not implement this class!
 */
abstract class AbstractContent {
  /**
   * @return {number}
   */
  int getLength();

  /**
   * @return {List<any>}
   */
  List getContent();

  /**
   * Should return false if this Item is some kind of meta information
   * (e.g. format information).
   *
   * * Whether this Item should be addressable via `yarray.get(i)`
   * * Whether this Item should be counted when computing yarray.length
   *
   * @return {boolean}
   */
  bool isCountable();

  /**
   * @return {AbstractContent}
   */
  AbstractContent copy();

  /**
   * @param {number} offset
   * @return {AbstractContent}
   */
  AbstractContent splice(int offset);

  /**
   * @param {AbstractContent} right
   * @return {boolean}
   */
  bool mergeWith(AbstractContent right);

  /**
   * @param {Transaction} transaction
   * @param {Item} item
   */
  void integrate(Transaction transaction, Item item);

  /**
   * @param {Transaction} transaction
   */
  void delete(Transaction transaction);

  /**
   * @param {StructStore} store
   */
  void gc(StructStore store);

  /**
   * @param {AbstractUpdateEncoder} encoder
   * @param {number} offset
   */
  void write(AbstractUpdateEncoder encoder, int offset);

  /**
   * @return {number}
   */
  int getRef();
}
