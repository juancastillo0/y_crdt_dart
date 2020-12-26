import 'package:y_crdt/src/structs/content_embed.dart';
import 'package:y_crdt/src/structs/content_format.dart';
import 'package:y_crdt/src/structs/content_string.dart';
import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/gc.dart';
/**
 * @module YText
 */

// import {
//   YEvent,
//   AbstractType,
//   getItemCleanStart,
//   getState,
//   isVisible,
//   createID,
//   YTextRefID,
//   callTypeObservers,
//   transact,
//   ContentEmbed,
//   GC,
//   ContentFormat,
//   ContentString,
//   splitSnapshotAffectedStructs,
//   iterateDeletedStructs,
//   iterateStructs,
//   findMarker,
//   updateMarkerChanges,
//   ArraySearchMarker,
//   AbstractUpdateDecoder,
//   AbstractUpdateEncoder,
//   ID,
//   Doc,
//   Item,
//   Snapshot,
//   Transaction, // eslint-disable-line
// } from "../internals.js";

// import * as object from "lib0/object.js";
// import * as map from "lib0/map.js";
// import * as error from "lib0/error.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/Snapshot.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/utils/y_event.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

/**
 * @param {any} a
 * @param {any} b
 * @return {boolean}
 */
bool equalAttrs(dynamic a, dynamic b) =>
    a == b ||
    (a is Map &&
        b is Map &&
        a.length == b.length &&
        a.entries.every((entry) =>
            b.containsKey(entry.key) && b[entry.key] == entry.value));

class ItemTextListPosition {
  /**
   * @param {Item|null} left
   * @param {Item|null} right
   * @param {number} index
   * @param {Map<string,any>} currentAttributes
   */
  ItemTextListPosition(
      this.left, this.right, this.index, this.currentAttributes);
  Item? left;
  Item? right;
  int index;
  final Map<String, dynamic> currentAttributes;

  /**
   * Only call this if you know that this.right is defined
   */
  void forward() {
    final _right = this.right;
    if (_right == null) {
      throw Exception('Unexpected case');
    }
    if (_right.content is ContentEmbed || _right.content is ContentString) {
      if (!_right.deleted) {
        this.index += _right.length;
      }
    } else if (_right.content is ContentFormat) {
      if (!_right.deleted) {
        updateCurrentAttributes(
            this.currentAttributes,
            /** @type {ContentFormat} */ (_right.content as ContentFormat));
      }
    }

    this.left = this.right;
    this.right = this.right!.right;
  }
}

/**
 * @param {Transaction} transaction
 * @param {ItemTextListPosition} pos
 * @param {number} count steps to move forward
 * @return {ItemTextListPosition}
 *
 * @private
 * @function
 */
ItemTextListPosition findNextPosition(
    Transaction transaction, ItemTextListPosition pos, int count) {
  var _right = pos.right;
  while (_right != null && count > 0) {
    if (_right.content is ContentEmbed || _right.content is ContentString) {
      if (!_right.deleted) {
        if (count < _right.length) {
          // split right
          getItemCleanStart(
              transaction, createID(_right.id.client, _right.id.clock + count));
        }
        pos.index += _right.length;
        count -= _right.length;
      }
    } else if (_right.content is ContentFormat) {
      if (!_right.deleted) {
        updateCurrentAttributes(
            pos.currentAttributes,
            /** @type {ContentFormat} */ (_right.content as ContentFormat));
      }
    }
    pos.left = pos.right;
    pos.right = _right.right;
    _right = pos.right;
    // pos.forward() - we don't forward because that would halve the performance because we already do the checks above
  }
  return pos;
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {number} index
 * @return {ItemTextListPosition}
 *
 * @private
 * @function
 */
ItemTextListPosition findPosition(
    Transaction transaction, AbstractType parent, int index) {
  final currentAttributes = <String, dynamic>{};
  final marker = findMarker(parent, index);
  if (marker != null) {
    final pos = ItemTextListPosition(
        marker.p.left, marker.p, marker.index, currentAttributes);
    return findNextPosition(transaction, pos, index - marker.index);
  } else {
    final pos =
        ItemTextListPosition(null, parent.innerStart, 0, currentAttributes);
    return findNextPosition(transaction, pos, index);
  }
}

/**
 * Negate applied formats
 *
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {ItemTextListPosition} currPos
 * @param {Map<string,any>} negatedAttributes
 *
 * @private
 * @function
 */
void insertNegatedAttributes(Transaction transaction, AbstractType parent,
    ItemTextListPosition currPos, Map<String, dynamic> negatedAttributes) {
  // check if we really need to remove attributes
  var _right = currPos.right;
  while (_right != null &&
      (_right.deleted == true ||
          (_right.content is ContentFormat &&
              equalAttrs(
                  negatedAttributes.get(
                      /** @type {ContentFormat} */ (_right.content
                              as ContentFormat)
                          .key),
                  /** @type {ContentFormat} */ (_right.content as ContentFormat)
                      .value)))) {
    if (!_right.deleted) {
      negatedAttributes.remove(
          /** @type {ContentFormat} */ (_right.content as ContentFormat).key);
    }
    currPos.forward();
    _right = currPos.right;
  }
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  var left = currPos.left;
  final right = currPos.right;
  negatedAttributes.forEach((key, val) {
    left = new Item(
        createID(ownClientId, getState(doc.store, ownClientId)),
        left,
        left?.lastId,
        right,
        right?.id,
        parent,
        null,
        ContentFormat(key, val));
    left!.integrate(transaction, 0);
  });
}

/**
 * @param {Map<string,any>} currentAttributes
 * @param {ContentFormat} format
 *
 * @private
 * @function
 */
void updateCurrentAttributes(
    Map<String, dynamic> currentAttributes, ContentFormat format) {
  final key = format.key;
  final value = format.value;
  if (value == null) {
    currentAttributes.remove(key);
  } else {
    currentAttributes.set(key, value);
  }
}

/**
 * @param {ItemTextListPosition} currPos
 * @param {Object<string,any>} attributes
 *
 * @private
 * @function
 */
void minimizeAttributeChanges(
    ItemTextListPosition currPos, Map<String, dynamic> attributes) {
  // go right while attributes[right.key] == right.value (or right is deleted)
  while (true) {
    final _right = currPos.right;
    if (_right == null) {
      break;
    } else if (_right.deleted ||
        (_right.content is ContentFormat &&
            equalAttrs(
                attributes[
                    /** @type {ContentFormat} */ (_right.content
                            as ContentFormat)
                        .key],
                /** @type {ContentFormat} */ (_right.content as ContentFormat)
                    .value))) {
      //
    } else {
      break;
    }
    currPos.forward();
  }
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {ItemTextListPosition} currPos
 * @param {Object<string,any>} attributes
 * @return {Map<string,any>}
 *
 * @private
 * @function
 **/
Map<String, dynamic> insertAttributes(
    Transaction transaction,
    AbstractType parent,
    ItemTextListPosition currPos,
    Map<String, dynamic> attributes) {
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  final negatedAttributes = <String, dynamic>{};
  // insert format-start items
  for (final key in attributes.keys) {
    final val = attributes[key];
    final currentVal = currPos.currentAttributes.get(key);
    if (!equalAttrs(currentVal, val)) {
      // save negated attribute (set null if currentVal undefined)
      negatedAttributes.set(key, currentVal);
      final left = currPos.left;
      final right = currPos.right;
      currPos.right = Item(
          createID(ownClientId, getState(doc.store, ownClientId)),
          left,
          left?.lastId,
          right,
          right?.id,
          parent,
          null,
          ContentFormat(key, val));
      currPos.right!.integrate(transaction, 0);
      currPos.forward();
    }
  }
  return negatedAttributes;
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {ItemTextListPosition} currPos
 * @param {string|object} text
 * @param {Object<string,any>} attributes
 *
 * @private
 * @function
 **/
void insertText(
    Transaction transaction,
    AbstractType parent,
    ItemTextListPosition currPos,
    dynamic text,
    Map<String, dynamic> attributes) {
  // currPos.currentAttributes.forEach((key, val) {
  //   if (attributes[key] == null) {
  //     attributes[key] = null;
  //   }
  // });
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  minimizeAttributeChanges(currPos, attributes);
  final negatedAttributes =
      insertAttributes(transaction, parent, currPos, attributes);
  // insert content
  final content = text is String
      ? ContentString(/** @type {string} */ (text))
      : ContentEmbed(text);
  var index = currPos.index;
  var right = currPos.right;
  var left = currPos.left;
  if (parent.innerSearchMarker != null) {
    updateMarkerChanges(
        parent.innerSearchMarker!, currPos.index, content.getLength());
  }
  right = Item(createID(ownClientId, getState(doc.store, ownClientId)), left,
      left?.lastId, right, right?.id, parent, null, content);
  right.integrate(transaction, 0);
  currPos.right = right;
  currPos.index = index;
  currPos.forward();
  insertNegatedAttributes(transaction, parent, currPos, negatedAttributes);
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {ItemTextListPosition} currPos
 * @param {number} length
 * @param {Object<string,any>} attributes
 *
 * @private
 * @function
 */
void formatText(Transaction transaction, AbstractType parent,
    ItemTextListPosition currPos, int length, Map<String, dynamic> attributes) {
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  minimizeAttributeChanges(currPos, attributes);
  final negatedAttributes =
      insertAttributes(transaction, parent, currPos, attributes);
  // iterate until first non-format or null is found
  // delete all formats with attributes[format.key] != null
  while (length > 0 && currPos.right != null) {
    final _right = currPos.right!;
    if (!_right.deleted) {
      final _content = _right.content;
      if (_content is ContentFormat) {
        final key = /** @type {ContentFormat} */ _content.key;
        final value = /** @type {ContentFormat} */ _content.value;
        final attr = attributes[key];
        if (attr != null) {
          if (equalAttrs(attr, value)) {
            negatedAttributes.remove(key);
          } else {
            negatedAttributes.set(key, value);
          }
          _right.delete(transaction);
        }
      } else if (_content is ContentEmbed || _content is ContentString) {
        if (length < _right.length) {
          getItemCleanStart(transaction,
              createID(_right.id.client, _right.id.clock + length));
        }
        length -= _right.length;
      }
    }
    currPos.forward();
  }
  // Quill just assumes that the editor starts with a newline and that it always
  // ends with a newline. We only insert that newline when a new newline is
  // inserted - i.e when length is bigger than type.length
  if (length > 0) {
    var newlines = "";
    for (; length > 0; length--) {
      newlines += "\n";
    }
    currPos.right = Item(
        createID(ownClientId, getState(doc.store, ownClientId)),
        currPos.left,
        currPos.left?.lastId,
        currPos.right,
        currPos.right?.id,
        parent,
        null,
        ContentString(newlines));
    currPos.right!.integrate(transaction, 0);
    currPos.forward();
  }
  insertNegatedAttributes(transaction, parent, currPos, negatedAttributes);
}

/**
 * Call this function after string content has been deleted in order to
 * clean up formatting Items.
 *
 * @param {Transaction} transaction
 * @param {Item} start
 * @param {Item|null} end exclusive end, automatically iterates to the next Content Item
 * @param {Map<string,any>} startAttributes
 * @param {Map<string,any>} endAttributes This attribute is modified!
 * @return {number} The amount of formatting Items deleted.
 *
 * @function
 */
int cleanupFormattingGap(Transaction transaction, Item start, Item? end,
    Map<String, dynamic> startAttributes, Map<String, dynamic> endAttributes) {
  while (end != null &&
      end.content is! ContentString &&
      end.content is! ContentEmbed) {
    if (!end.deleted && end.content is ContentFormat) {
      updateCurrentAttributes(
          endAttributes,
          /** @type {ContentFormat} */ (end.content as ContentFormat));
    }
    end = end.right;
  }
  var cleanups = 0;
  while (start != end) {
    if (!start.deleted) {
      final content = start.content;
      if (content is ContentFormat) {
        if ((endAttributes.get(content.key)) != content.value ||
            (startAttributes.get(content.key)) == content.value) {
          // Either this format is overwritten or it is not necessary because the attribute already existed.
          start.delete(transaction);
          cleanups++;
        }
      }
    }

    start = /** @type {Item} */ (start.right!);
  }
  return cleanups;
}

/**
 * @param {Transaction} transaction
 * @param {Item | null} item
 */
void cleanupContextlessFormattingGap(Transaction transaction, Item? item) {
  // iterate until item.right is null or content
  final _right = item?.right;
  while (_right != null &&
      (_right.deleted ||
          (_right.content is ContentString &&
              _right.content is ContentEmbed))) {
    item = _right;
  }
  final attrs = <String>{};
  // iterate back until a content item is found
  while (item != null &&
      (item.deleted ||
          (item.content is! ContentString && item.content is! ContentEmbed))) {
    if (!item.deleted && item.content is ContentFormat) {
      final key = /** @type {ContentFormat} */ (item.content as ContentFormat)
          .key;
      if (attrs.contains(key)) {
        item.delete(transaction);
      } else {
        attrs.add(key);
      }
    }
    item = item.left;
  }
}

/**
 * This function is experimental and subject to change / be removed.
 *
 * Ideally, we don't need this function at all. Formatting attributes should be cleaned up
 * automatically after each change. This function iterates twice over the complete YText type
 * and removes unnecessary formatting attributes. This is also helpful for testing.
 *
 * This function won't be exported anymore as soon as there is confidence that the YText type works as intended.
 *
 * @param {YText} type
 * @return {number} How many formatting attributes have been cleaned up.
 */
int cleanupYTextFormatting(YText type) {
  var res = 0;
  transact(/** @type {Doc} */ (type.doc!), (transaction) {
    var start = /** @type {Item} */ (type.innerStart);
    var end = type.innerStart;
    var startAttributes = <String, dynamic>{};
    final currentAttributes = {...startAttributes};
    while (end != null) {
      if (end.deleted == false) {
        if (end.content is ContentFormat) {
          updateCurrentAttributes(
              currentAttributes,
              /** @type {ContentFormat} */ (end.content as ContentFormat));
        } else if (end.content is ContentEmbed ||
            end.content is ContentString) {
          res += cleanupFormattingGap(
              transaction, start!, end, startAttributes, currentAttributes);
          startAttributes = {...currentAttributes};
          start = end;
        }
      }
      end = end.right;
    }
  });
  return res;
}

/**
 * @param {Transaction} transaction
 * @param {ItemTextListPosition} currPos
 * @param {number} length
 * @return {ItemTextListPosition}
 *
 * @private
 * @function
 */
ItemTextListPosition deleteText(
    Transaction transaction, ItemTextListPosition currPos, int length) {
  final startLength = length;
  final startAttrs = {...currPos.currentAttributes};
  final start = currPos.right;
  while (length > 0 && currPos.right != null) {
    final _right = currPos.right!;
    if (_right.deleted == false) {
      if (_right.content is ContentEmbed || _right.content is ContentString) {
        if (length < _right.length) {
          getItemCleanStart(transaction,
              createID(_right.id.client, _right.id.clock + length));
        }
        length -= _right.length;
        _right.delete(transaction);
      }
    }
    currPos.forward();
  }
  if (start != null) {
    cleanupFormattingGap(transaction, start, currPos.right, startAttrs,
        {...currPos.currentAttributes});
  }
  final parent = /** @type {AbstractType<any>} */ (
      /** @type {Item} */ (currPos.left ?? currPos.right as Item).parent
          as AbstractType);
  if (parent.innerSearchMarker != null) {
    updateMarkerChanges(
        parent.innerSearchMarker!, currPos.index, -startLength + length);
  }
  return currPos;
}

/**
 * The Quill Delta format represents changes on a text document with
 * formatting information. For mor information visit {@link https://quilljs.com/docs/delta/|Quill Delta}
 *
 * @example
 *   {
 *     ops: [
 *       { insert: 'Gandalf', attributes: { bold: true } },
 *       { insert: ' the ' },
 *       { insert: 'Grey', attributes: { color: '#cccccc' } }
 *     ]
 *   }
 *
 */

/**
 * Attributes that can be assigned to a selection of text.
 *
 * @example
 *   {
 *     bold: true,
 *     font-size: '40px'
 *   }
 *
 * @typedef {Object} TextAttributes
 */

/**
 * @typedef {Object} DeltaItem
 * @property {number|undefined} DeltaItem.delete
 * @property {number|undefined} DeltaItem.retain
 * @property {string|undefined} DeltaItem.insert
 * @property {Object<string,any>} DeltaItem.attributes
 */

/**
 * Event that describes the changes on a YText type.
 */
class YTextEvent extends YEvent {
  /**
   * @param {YText} ytext
   * @param {Transaction} transaction
   */
  YTextEvent(YText ytext, Transaction transaction) : super(ytext, transaction);
  /**
     * @type {List<DeltaItem>|null}
     */
  List<DeltaItem>? _delta;

  /**
   * Compute the changes in the delta format.
   * A {@link https://quilljs.com/docs/delta/|Quill Delta}) that represents the changes on the document.
   *
   * @type {List<DeltaItem>}
   *
   * @public
   */
  List<DeltaItem> get delta {
    if (this._delta == null) {
      final y = /** @type {Doc} */ (this.target.doc!);
      this._delta = [];
      transact(y, (transaction) {
        final delta = /** @type {List<DeltaItem>} */ (this._delta!);
        final currentAttributes =
            <String, dynamic>{}; // saves all current attributes for insert
        final oldAttributes = <String, dynamic>{};
        var item = this.target.innerStart;
        /**
         * @type {string?}
         */
        String? action;
        /**
         * @type {Object<string,any>}
         */
        final attributes = <String,
            dynamic>{}; // counts added or removed new attributes for retain
        /**
         * @type {string|object}
         */
        Object insert = "";
        var retain = 0;
        var deleteLen = 0;
        void addOp() {
          if (action != null) {
            /**
             * @type {any}
             */
            DeltaItem op;
            switch (action) {
              case "delete":
                op = DeltaItem.delete(deleteLen, attributes: null);
                deleteLen = 0;
                break;
              case "insert":
                Map<String, dynamic>? _attr;
                if (currentAttributes.length > 0) {
                  _attr = {};
                  currentAttributes.forEach((key, value) {
                    if (value != null) {
                      _attr![key] = value;
                    }
                  });
                }
                op = DeltaItem.insert(insert, attributes: _attr);

                insert = "";
                break;
              case "retain":
                op = DeltaItem.retain(retain,
                    attributes: attributes.length > 0 ? {...attributes} : null);
                retain = 0;
                break;
              default:
                throw Exception("Unexpected case");
            }
            delta.add(op);
            action = null;
          }
        }

        ;
        while (item != null) {
          if (item.content is ContentEmbed) {
            if (this.adds(item)) {
              if (!this.deletes(item)) {
                addOp();
                action = "insert";
                insert = /** @type {ContentEmbed} */ (item.content
                        as ContentEmbed)
                    .embed;
                addOp();
              }
            } else if (this.deletes(item)) {
              if (action != "delete") {
                addOp();
                action = "delete";
              }
              deleteLen += 1;
            } else if (!item.deleted) {
              if (action != "retain") {
                addOp();
                action = "retain";
              }
              retain += 1;
            }
          } else if (item.content is ContentString) {
            if (this.adds(item)) {
              if (!this.deletes(item)) {
                if (action != "insert") {
                  addOp();
                  action = "insert";
                }
                insert = (insert as String) + /** @type {ContentString} */ (item
                        .content as ContentString)
                    .str;
              }
            } else if (this.deletes(item)) {
              if (action != "delete") {
                addOp();
                action = "delete";
              }
              deleteLen += item.length;
            } else if (!item.deleted) {
              if (action != "retain") {
                addOp();
                action = "retain";
              }
              retain += item.length;
            }
          } else if (item.content is ContentFormat) {
            final key = /** @type {ContentFormat} */ (item.content
                    as ContentFormat)
                .key;
            final value = /** @type {ContentFormat} */ (item.content
                    as ContentFormat)
                .value;
            if (this.adds(item)) {
              if (!this.deletes(item)) {
                final curVal = currentAttributes.get(key);
                if (!equalAttrs(curVal, value)) {
                  if (action == "retain") {
                    addOp();
                  }
                  if (equalAttrs(value, oldAttributes.get(key))) {
                    attributes.remove(key);
                  } else {
                    attributes[key] = value;
                  }
                } else {
                  item.delete(transaction);
                }
              }
            } else if (this.deletes(item)) {
              oldAttributes.set(key, value);
              final curVal = currentAttributes.get(key);
              if (!equalAttrs(curVal, value)) {
                if (action == "retain") {
                  addOp();
                }
                attributes[key] = curVal;
              }
            } else if (!item.deleted) {
              oldAttributes.set(key, value);
              final attr = attributes[key];
              if (attr != null) {
                if (!equalAttrs(attr, value)) {
                  if (action == "retain") {
                    addOp();
                  }
                  if (value == null) {
                    attributes[key] = value;
                  } else {
                    attributes.remove(key);
                  }
                } else {
                  item.delete(transaction);
                }
              }
            }
            if (!item.deleted) {
              if (action == "insert") {
                addOp();
              }
              updateCurrentAttributes(
                  currentAttributes,
                  /** @type {ContentFormat} */ (item.content as ContentFormat));
            }
          }
          item = item.right;
        }
        addOp();
        while (delta.length > 0) {
          final lastOp = delta[delta.length - 1];
          if (lastOp.maybeMap(retain: (_) => true, orElse: () => false)! &&
              lastOp.attributes == null) {
            // retain delta's if they don't assign attributes
            delta.removeLast();
          } else {
            break;
          }
        }
      });
    }
    return this._delta!;
  }
}

/**
 * Type that represents text with formatting information.
 *
 * This type replaces y-richtext as this implementation is able to handle
 * block formats (format information on a paragraph), embeds (complex elements
 * like pictures and videos), and text formats (**bold**, *italic*).
 *
 * @extends AbstractType<YTextEvent>
 */
class YText extends AbstractType<YTextEvent> {
  static YText create() => YText();
  /**
   * @param {String} [string] The initial value of the YText.
   */
  YText([String? string]) {
    /**
     * Array of pending operations on this type
     * @type {List<function():void>?}
     */
    this._pending = string != null ? [() => this.insert(0, string)] : [];
  }
  /**
     * @type {List<ArraySearchMarker>}
     */
  final List<ArraySearchMarker> _searchMarker = [];

  List<void Function()>? _pending;

  /**
   * Number of characters of this text type.
   *
   * @type {number}
   */
  int get length {
    return this.innerLength;
  }

  /**
   * @param {Doc} y
   * @param {Item} item
   */
  innerIntegrate(Doc y, Item? item) {
    super.innerIntegrate(y, item);
    try {
      /** @type {List<function>} */ (this._pending!).forEach((f) => f());
    } catch (e) {
      logger.e(e);
    }
    this._pending = null;
  }

  innerCopy() {
    return YText();
  }

  /**
   * @return {YText}
   */
  clone() {
    final text = YText();
    text.applyDelta(this.toDelta());
    return text;
  }

  /**
   * Creates YTextEvent and calls observers.
   *
   * @param {Transaction} transaction
   * @param {Set<null|string>} parentSubs Keys changed on this type. `null` if list was modified.
   */
  void innerCallObserver(Transaction transaction, Set<String?> parentSubs) {
    super.innerCallObserver(transaction, parentSubs);
    final event = YTextEvent(this, transaction);
    final doc = transaction.doc;
    // If a remote change happened, we try to cleanup potential formatting duplicates.
    if (!transaction.local) {
      // check if another formatting item was inserted
      var foundFormattingItem = false;
      for (final entry in transaction.afterState.entries) {
        final client = entry.key;
        final afterClock = entry.key;
        final clock = transaction.beforeState.get(client) ?? 0;
        if (afterClock == clock) {
          continue;
        }
        iterateStructs(
            transaction,
            /** @type {List<Item|GC>} */ (doc.store.clients.get(client)!),
            clock,
            afterClock, (item) {
          if (!item.deleted &&
              /** @type {Item} */ (item as Item).content is ContentFormat) {
            foundFormattingItem = true;
          }
        });
        if (foundFormattingItem) {
          break;
        }
      }
      if (!foundFormattingItem) {
        iterateDeletedStructs(transaction, transaction.deleteSet, (item) {
          if (item is GC || foundFormattingItem) {
            return;
          }
          if (item is Item &&
              item.parent == this &&
              item.content is ContentFormat) {
            foundFormattingItem = true;
          }
        });
      }
      transact(doc, (t) {
        if (foundFormattingItem) {
          // If a formatting item was inserted, we simply clean the whole type.
          // We need to compute currentAttributes for the current position anyway.
          cleanupYTextFormatting(this);
        } else {
          // If no formatting attribute was inserted, we can make due with contextless
          // formatting cleanups.
          // Contextless: it is not necessary to compute currentAttributes for the affected position.
          iterateDeletedStructs(t, t.deleteSet, (item) {
            if (item is GC) {
              return;
            }
            if (item is Item && item.parent == this) {
              cleanupContextlessFormattingGap(t, item);
            }
          });
        }
      });
    }
    callTypeObservers<YTextEvent>(this, transaction, event);
  }

  /**
   * Returns the unformatted string representation of this YText type.
   *
   * @public
   */
  String toString() {
    var str = "";
    /**
     * @type {Item|null}
     */
    var n = this.innerStart;
    while (n != null) {
      if (!n.deleted && n.countable && n.content is ContentString) {
        str += /** @type {ContentString} */ (n.content as ContentString).str;
      }
      n = n.right;
    }
    return str;
  }

  /**
   * Returns the unformatted string representation of this YText type.
   *
   * @return {string}
   * @public
   */
  String toJSON() {
    return this.toString();
  }

  /**
   * Apply a {@link Delta} on this shared YText type.
   *
   * @param {any} delta The changes to apply on this element.
   * @param {object}  [opts]
   * @param {boolean} [opts.sanitize] Sanitize input delta. Removes ending newlines if set to true.
   *
   *
   * @public
   */
  void applyDelta(dynamic delta, {bool sanitize = true}) {
    if (this.doc != null) {
      transact(this.doc!, (transaction) {
        final currPos = ItemTextListPosition(null, this.innerStart, 0, {});
        for (var i = 0; i < delta.length; i++) {
          final op = delta[i];
          if (op.insert != null) {
            // Quill assumes that the content starts with an empty paragraph.
            // Yjs/Y.Text assumes that it starts empty. We always hide that
            // there is a newline at the end of the content.
            // If we omit this step, clients will see a different number of
            // paragraphs, but nothing bad will happen.
            final ins = !sanitize &&
                    op.insert is String &&
                    i == delta.length - 1 &&
                    currPos.right == null &&
                    op.insert.slice(-1) == "\n"
                ? op.insert.slice(0, -1)
                : op.insert;
            if (ins is! String || ins.length > 0) {
              insertText(transaction, this, currPos, ins, op.attributes ?? {});
            }
          } else if (op.retain != null) {
            formatText(
                transaction, this, currPos, op.retain, op.attributes ?? {});
          } else if (op.delete != null) {
            deleteText(transaction, currPos, op.delete);
          }
        }
      });
    } else {
      /** @type {List<function>} */ (this._pending!)
          .add(() => this.applyDelta(delta));
    }
  }

  /**
   * Returns the Delta representation of this YText type.
   *
   * @param {Snapshot} [snapshot]
   * @param {Snapshot} [prevSnapshot]
   * @param {function('removed' | 'added', ID):any} [computeYChange]
   * @return {any} The Delta representation of this type.
   *
   * @public
   */
  List<Map<String, Object>> toDelta(
      [Snapshot? snapshot,
      Snapshot? prevSnapshot,
      dynamic Function(String, ID)? computeYChange]) {
    /**
     * @type{List<any>}
     */
    final ops = <Map<String, Object>>[];
    final currentAttributes = <String, dynamic>{};
    final doc = /** @type {Doc} */ (this.doc);
    var str = "";
    var n = this.innerStart;
    void packStr() {
      if (str.length > 0) {
        // pack str with attributes to ops
        /**
         * @type {Object<string,any>}
         */
        final attributes = <String, dynamic>{};
        var addAttributes = false;
        currentAttributes.forEach((key, value) {
          addAttributes = true;
          attributes[key] = value;
        });
        /**
         * @type {Object<string,any>}
         */
        final op = <String, Object>{"insert": str};
        if (addAttributes) {
          op["attributes"] = attributes;
        }
        ops.add(op);
        str = "";
      }
    }

    // snapshots are merged again after the transaction, so we need to keep the
    // transalive until we are done
    transact(doc!, (transaction) {
      if (snapshot != null) {
        splitSnapshotAffectedStructs(transaction, snapshot);
      }
      if (prevSnapshot != null) {
        splitSnapshotAffectedStructs(transaction, prevSnapshot);
      }
      while (n != null) {
        final _n = n!;
        if (isVisible(_n, snapshot) ||
            (prevSnapshot != null && isVisible(_n, prevSnapshot))) {
          if (_n.content is ContentString) {
            final cur = currentAttributes.get("ychange");
            if (snapshot != null && !isVisible(_n, snapshot)) {
              if (cur == null ||
                  cur.user != _n.id.client ||
                  cur.state != "removed") {
                packStr();
                currentAttributes.set(
                    "ychange",
                    computeYChange != null
                        ? computeYChange("removed", _n.id)
                        : {"type": "removed"});
              }
            } else if (prevSnapshot != null && !isVisible(_n, prevSnapshot)) {
              if (cur == null ||
                  cur.user != _n.id.client ||
                  cur.state != "added") {
                packStr();
                currentAttributes.set(
                    "ychange",
                    computeYChange != null
                        ? computeYChange("added", _n.id)
                        : {"type": "added"});
              }
            } else if (cur != null) {
              packStr();
              currentAttributes.remove("ychange");
            }
            str += /** @type {ContentString} */ (_n.content as ContentString)
                .str;
          } else if (_n.content is ContentEmbed) {
            packStr();
            /**
                 * @type {Object<string,any>}
                 */
            final op = <String, Object>{
              "insert": /** @type {ContentEmbed} */ (_n.content as ContentEmbed)
                  .embed,
            };
            if (currentAttributes.length > 0) {
              final attrs = /** @type {Object<string,any>} */ ({});
              op["attributes"] = attrs;
              currentAttributes.forEach((key, value) {
                attrs[key] = value;
              });
            }
            ops.add(op);
          } else if (_n.content is ContentFormat) {
            if (isVisible(_n, snapshot)) {
              packStr();
              updateCurrentAttributes(
                  currentAttributes,
                  /** @type {ContentFormat} */ (_n.content as ContentFormat));
            }
          }
        }
        n = _n.right;
      }
      packStr();
    }, splitSnapshotAffectedStructs);
    return ops;
  }

  /**
   * Insert text at a given index.
   *
   * @param {number} index The index at which to start inserting.
   * @param {String} text The text to insert at the specified position.
   * @param {TextAttributes} [attributes] Optionally define some formatting
   *                                    information to apply on the inserted
   *                                    Text.
   * @public
   */
  void insert(int index, String text, [Map<String, dynamic>? _attributes]) {
    if (text.length <= 0) {
      return;
    }
    final y = this.doc;
    if (y != null) {
      transact(y, (transaction) {
        final pos = findPosition(transaction, this, index);
        final Map<String, dynamic> attributes;
        if (_attributes == null) {
          attributes = {};
          // @ts-ignore
          pos.currentAttributes.forEach((k, v) {
            attributes[k] = v;
          });
        } else {
          attributes = _attributes;
        }
        insertText(transaction, this, pos, text, attributes);
      });
    } else {
      /** @type {List<function>} */ (this._pending!)
          .add(() => this.insert(index, text, _attributes));
    }
  }

  /**
   * Inserts an embed at a index.
   *
   * @param {number} index The index to insert the embed at.
   * @param {Object} embed The Object that represents the embed.
   * @param {TextAttributes} attributes Attribute information to apply on the
   *                                    embed
   *
   * @public
   */
  void insertEmbed(int index, Map<String, dynamic> embed,
      [Map<String, dynamic> attributes = const {}]) {
    // if (embed.constructor != Object) {
    //   throw  Exception("Embed must be an Object");
    // }
    final y = this.doc;
    if (y != null) {
      transact(y, (transaction) {
        final pos = findPosition(transaction, this, index);
        insertText(transaction, this, pos, embed, attributes);
      });
    } else {
      /** @type {List<function>} */ (this._pending!)
          .add(() => this.insertEmbed(index, embed, attributes));
    }
  }

  /**
   * Deletes text starting from an index.
   *
   * @param {number} index Index at which to start deleting.
   * @param {number} length The number of characters to remove. Defaults to 1.
   *
   * @public
   */
  void delete(int index, int length) {
    if (length == 0) {
      return;
    }
    final y = this.doc;
    if (y != null) {
      transact(y, (transaction) {
        deleteText(transaction, findPosition(transaction, this, index), length);
      });
    } else {
      /** @type {List<function>} */ (this._pending!)
          .add(() => this.delete(index, length));
    }
  }

  /**
   * Assigns properties to a range of text.
   *
   * @param {number} index The position where to start formatting.
   * @param {number} length The amount of characters to assign properties to.
   * @param {TextAttributes} attributes Attribute information to apply on the
   *                                    text.
   *
   * @public
   */
  format(int index, int length, Map<String, dynamic> attributes) {
    if (length == 0) {
      return;
    }
    final y = this.doc;
    if (y != null) {
      transact(y, (transaction) {
        final pos = findPosition(transaction, this, index);
        if (pos.right == null) {
          return;
        }
        formatText(transaction, this, pos, length, attributes);
      });
    } else {
      /** @type {List<function>} */ (this._pending!)
          .add(() => this.format(index, length, attributes));
    }
  }

  /**
   * @param {AbstractUpdateEncoder} encoder
   */
  _write(AbstractUpdateEncoder encoder) {
    encoder.writeTypeRef(YTextRefID);
  }
}

/**
 * @param {AbstractUpdateDecoder} decoder
 * @return {YText}
 *
 * @private
 * @function
 */
YText readYText(AbstractUpdateDecoder decoder) => YText();

abstract class DeltaItem {
  DeltaItem._();

  Map<String, dynamic>? get attributes => this.map(
        delete: (e) => e.attributes,
        retain: (e) => e.attributes,
        insert: (e) => e.attributes,
      );

  factory DeltaItem.delete(
    int delete, {
    required Map<String, dynamic>? attributes,
  }) = _Delete;
  factory DeltaItem.retain(
    int retain, {
    required Map<String, dynamic>? attributes,
  }) = _Retain;
  factory DeltaItem.insert(
    Object insert, {
    required Map<String, dynamic>? attributes,
  }) = _Insert;

  T when<T>({
    required T Function(int delete, Map<String, dynamic>? attributes) delete,
    required T Function(int retain, Map<String, dynamic>? attributes) retain,
    required T Function(Object insert, Map<String, dynamic>? attributes) insert,
  }) {
    final v = this;
    if (v is _Delete) return delete(v.delete, v.attributes);
    if (v is _Retain) return retain(v.retain, v.attributes);
    if (v is _Insert) return insert(v.insert, v.attributes);
    throw "";
  }

  T? maybeWhen<T>({
    T Function()? orElse,
    T Function(int delete, Map<String, dynamic>? attributes)? delete,
    T Function(int retain, Map<String, dynamic>? attributes)? retain,
    T Function(Object insert, Map<String, dynamic>? attributes)? insert,
  }) {
    final v = this;
    if (v is _Delete)
      return delete != null ? delete(v.delete, v.attributes) : orElse?.call();
    if (v is _Retain)
      return retain != null ? retain(v.retain, v.attributes) : orElse?.call();
    if (v is _Insert)
      return insert != null ? insert(v.insert, v.attributes) : orElse?.call();
    throw "";
  }

  T map<T>({
    required T Function(_Delete value) delete,
    required T Function(_Retain value) retain,
    required T Function(_Insert value) insert,
  }) {
    final v = this;
    if (v is _Delete) return delete(v);
    if (v is _Retain) return retain(v);
    if (v is _Insert) return insert(v);
    throw "";
  }

  T? maybeMap<T>({
    T Function()? orElse,
    T Function(_Delete value)? delete,
    T Function(_Retain value)? retain,
    T Function(_Insert value)? insert,
  }) {
    final v = this;
    if (v is _Delete) return delete != null ? delete(v) : orElse?.call();
    if (v is _Retain) return retain != null ? retain(v) : orElse?.call();
    if (v is _Insert) return insert != null ? insert(v) : orElse?.call();
    throw "";
  }
}

class _Delete extends DeltaItem {
  final int delete;
  final Map<String, dynamic>? attributes;

  _Delete(
    this.delete, {
    required this.attributes,
  }) : super._();
}

class _Retain extends DeltaItem {
  final int retain;
  final Map<String, dynamic>? attributes;

  _Retain(
    this.retain, {
    required this.attributes,
  }) : super._();
}

class _Insert extends DeltaItem {
  final Object insert;
  final Map<String, dynamic>? attributes;

  _Insert(
    this.insert, {
    required this.attributes,
  }) : super._();
}
