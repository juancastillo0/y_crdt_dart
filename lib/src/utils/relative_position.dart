// import {
//   writeID,
//   readID,
//   compareIDs,
//   getState,
//   findRootTypeKey,
//   Item,
//   createID,
//   ContentType,
//   followRedone,
//   ID,
//   Doc,
//   AbstractType, // eslint-disable-line
// } from "../internals.js";

// import * as encoding from "lib0/encoding.js";
// import * as decoding from "lib0/decoding.js";
// import * as error from "lib0/error.js";

import 'dart:typed_data';

import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/lib0/decoding.dart' as decoding;
import 'package:y_crdt/src/lib0/encoding.dart' as encoding;

/**
 * A relative position is based on the Yjs model and is not affected by document changes.
 * E.g. If you place a relative position before a certain character, it will always point to this character.
 * If you place a relative position at the end of a type, it will always point to the end of the type.
 *
 * A numeric position is often unsuited for user selections, because it does not change when content is inserted
 * before or after.
 *
 * Insert(0, 'x')('a|bc') = 'xa|bc' Where | is the relative position.
 *
 * One of the properties must be defined.
 *
 * @example
 *   // Current cursor position is at position 10
 *   const relativePosition = createRelativePositionFromIndex(yText, 10)
 *   // modify yText
 *   yText.insert(0, 'abc')
 *   yText.delete(3, 10)
 *   // Compute the cursor position
 *   const absolutePosition = createAbsolutePositionFromRelativePosition(y, relativePosition)
 *   absolutePosition.type == yText // => true
 *   console.log('cursor location is ' + absolutePosition.index) // => cursor location is 3
 *
 */

class RelativePosition {
  /**
   * @param {ID|null} type
   * @param {string|null} tname
   * @param {ID|null} item
   */
  RelativePosition(this.type, this.tname, this.item);
  /**
     * @type {ID|null}
     */
  ID? type;
  /**
     * @type {string|null}
     */
  String? tname;
  /**
     * @type {ID | null}
     */
  ID? item;
}

/**
 * @param {any} json
 * @return {RelativePosition}
 *
 * @function
 */
RelativePosition createRelativePositionFromJSON(Map<String, Object?> json) {
  final type = json["type"] as Map<String, Object?>?;
  // TODO: innerItem?
  final innerItem = json["innerItem"] as Map<String, Object?>?;
  return RelativePosition(
    type == null
        ? null
        : createID(
            type["client"] as int,
            type["clock"] as int,
          ),
    json["tname"] as String?,
    innerItem == null
        ? null
        : createID(
            innerItem["client"] as int,
            innerItem["clock"] as int,
          ),
  );
}

class AbsolutePosition {
  /**
   * @param {AbstractType<any>} type
   * @param {number} index
   */
  AbsolutePosition(this.type, this.index);
  /**
     * @type {AbstractType<any>}
     */
  final AbstractType type;
  /**
     * @type {number}
     */
  final int index;
}

/**
 * @param {AbstractType<any>} type
 * @param {number} index
 *
 * @function
 */
AbsolutePosition createAbsolutePosition(AbstractType type, int index) =>
    AbsolutePosition(type, index);

/**
 * @param {AbstractType<any>} type
 * @param {ID|null} item
 *
 * @function
 */
RelativePosition createRelativePosition(AbstractType type, ID? item) {
  ID? typeid;
  String? tname;
  final typeItem = type.innerItem;
  if (typeItem == null) {
    tname = findRootTypeKey(type);
  } else {
    typeid = createID(typeItem.id.client, typeItem.id.clock);
  }
  return RelativePosition(typeid, tname, item);
}

/**
 * Create a relativePosition based on a absolute position.
 *
 * @param {AbstractType<any>} type The base type (e.g. YText or YArray).
 * @param {number} index The absolute position.
 * @return {RelativePosition}
 *
 * @function
 */
RelativePosition createRelativePositionFromTypeIndex(
    AbstractType type, int index) {
  Item? t = type.innerStart;
  while (t != null) {
    if (!t.deleted && t.countable) {
      if (t.length > index) {
        // case 1: found position somewhere in the linked list
        return createRelativePosition(
            type, createID(t.id.client, t.id.clock + index));
      }
      index -= t.length;
    }
    t = t.right;
  }
  return createRelativePosition(type, null);
}

/**
 * @param {encoding.Encoder} encoder
 * @param {RelativePosition} rpos
 *
 * @function
 */
encoding.Encoder writeRelativePosition(
    encoding.Encoder encoder, RelativePosition rpos) {
  final type = rpos.type;
  final tname = rpos.tname;
  final item = rpos.item;
  if (item != null) {
    encoding.writeVarUint(encoder, 0);
    writeID(encoder, item);
  } else if (tname != null) {
    // case 2: found position at the end of the list and type is stored in y.share
    encoding.writeUint8(encoder, 1);
    encoding.writeVarString(encoder, tname);
  } else if (type != null) {
    // case 3: found position at the end of the list and type is attached to an item
    encoding.writeUint8(encoder, 2);
    writeID(encoder, type);
  } else {
    throw Exception('Unexpected case');
  }
  return encoder;
}

/**
 * @param {RelativePosition} rpos
 * @return {Uint8Array}
 */
Uint8List encodeRelativePosition(RelativePosition rpos) {
  final encoder = encoding.createEncoder();
  writeRelativePosition(encoder, rpos);
  return encoding.toUint8Array(encoder);
}

/**
 * @param {decoding.Decoder} decoder
 * @return {RelativePosition|null}
 *
 * @function
 */
RelativePosition readRelativePosition(decoding.Decoder decoder) {
  ID? type;
  String? tname;
  ID? itemID;
  switch (decoding.readVarUint(decoder)) {
    case 0:
      // case 1: found position somewhere in the linked list
      itemID = readID(decoder);
      break;
    case 1:
      // case 2: found position at the end of the list and type is stored in y.share
      tname = decoding.readVarString(decoder);
      break;
    case 2:
      // case 3: found position at the end of the list and type is attached to an item
      type = readID(decoder);
  }
  return RelativePosition(type, tname, itemID);
}

/**
 * @param {Uint8Array} uint8Array
 * @return {RelativePosition|null}
 */
RelativePosition decodeRelativePosition(Uint8List uint8Array) =>
    readRelativePosition(decoding.createDecoder(uint8Array));

/**
 * @param {RelativePosition} rpos
 * @param {Doc} doc
 * @return {AbsolutePosition|null}
 *
 * @function
 */
AbsolutePosition? createAbsolutePositionFromRelativePosition(
    RelativePosition rpos, Doc doc) {
  final store = doc.store;
  final rightID = rpos.item;
  final typeID = rpos.type;
  final tname = rpos.tname;
  AbstractType type;
  var index = 0;
  if (rightID != null) {
    if (getState(store, rightID.client) <= rightID.clock) {
      return null;
    }
    final res = followRedone(store, rightID);
    final right = res.item;
    if (!(right is Item)) {
      return null;
    }
    type = /** @type {AbstractType<any>} */ (right.parent as AbstractType);
    if (type.innerItem == null || !type.innerItem!.deleted) {
      index = right.deleted || !right.countable ? 0 : res.diff;
      var n = right.left;
      while (n != null) {
        if (!n.deleted && n.countable) {
          index += n.length;
        }
        n = n.left;
      }
    }
  } else {
    if (tname != null) {
      type = doc.get(tname);
    } else if (typeID != null) {
      if (getState(store, typeID.client) <= typeID.clock) {
        // type does not exist yet
        return null;
      }
      final item = followRedone(store, typeID).item;
      if (item is Item && item.content is ContentType) {
        type = (item.content as ContentType).type;
      } else {
        // struct is garbage collected
        return null;
      }
    } else {
      throw Exception('Unexpected case');
    }
    index = type.innerLength;
  }
  return createAbsolutePosition(type, index);
}

/**
 * @param {RelativePosition|null} a
 * @param {RelativePosition|null} b
 *
 * @function
 */
bool compareRelativePositions(RelativePosition? a, RelativePosition? b) =>
    a == b ||
    (a != null &&
        b != null &&
        a.tname == b.tname &&
        compareIDs(a.item, b.item) &&
        compareIDs(a.type, b.type));
