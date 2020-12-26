// import {
//   removeEventHandlerListener,
//   callEventHandlerListeners,
//   addEventHandlerListener,
//   createEventHandler,
//   getState,
//   isVisible,
//   ContentType,
//   createID,
//   ContentAny,
//   ContentBinary,
//   getItemCleanStart,
//   ContentDoc, YText, YArray, AbstractUpdateEncoder, Doc, Snapshot, Transaction, EventHandler, YEvent, Item, // eslint-disable-line
// } from '../internals.js'

// import * as map from 'lib0/map.js'
// import * as iterator from 'lib0/iterator.js'
// import * as error from 'lib0/error.js'
// import * as math from 'lib0/math.js'

import 'dart:typed_data';

import 'package:y_crdt/src/structs/content_any.dart';
import 'package:y_crdt/src/structs/content_binary.dart';
import 'package:y_crdt/src/structs/content_doc.dart';
import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/event_handler.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/y_crdt_base.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/snapshot.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/y_event.dart';
import 'dart:math' as math;

const maxSearchMarker = 80;

/**
 * A unique timestamp that identifies each marker.
 *
 * Time is relative,.. this is more like an ever-increasing clock.
 *
 * @type {number}
 */
int globalSearchMarkerTimestamp = 0;

class ArraySearchMarker {
  /**
   * @param {Item} p
   * @param {number} index
   */
  ArraySearchMarker(this.p, this.index)
      : timestamp = globalSearchMarkerTimestamp++ {
    p.marker = true;
  }
  Item p;
  int index;
  int timestamp;
}

/**
 * @param {ArraySearchMarker} marker
 */
void refreshMarkerTimestamp(ArraySearchMarker marker) {
  marker.timestamp = globalSearchMarkerTimestamp++;
}

/**
 * This is rather complex so this function is the only thing that should overwrite a marker
 *
 * @param {ArraySearchMarker} marker
 * @param {Item} p
 * @param {number} index
 */
void overwriteMarker(ArraySearchMarker marker, Item p, int index) {
  marker.p.marker = false;
  marker.p = p;
  p.marker = true;
  marker.index = index;
  marker.timestamp = globalSearchMarkerTimestamp++;
}

/**
 * @param {List<ArraySearchMarker>} searchMarker
 * @param {Item} p
 * @param {number} index
 */
ArraySearchMarker markPosition(
    List<ArraySearchMarker> searchMarker, Item p, int index) {
  if (searchMarker.length >= maxSearchMarker) {
    // override oldest marker (we don't want to create more objects)
    final marker =
        searchMarker.reduce((a, b) => a.timestamp < b.timestamp ? a : b);
    overwriteMarker(marker, p, index);
    return marker;
  } else {
    // create new marker
    final pm = ArraySearchMarker(p, index);
    searchMarker.add(pm);
    return pm;
  }
}

/**
 * Search marker help us to find positions in the associative array faster.
 *
 * They speed up the process of finding a position without much bookkeeping.
 *
 * A maximum of `maxSearchMarker` objects are created.
 *
 * This function always returns a refreshed marker (updated timestamp)
 *
 * @param {AbstractType<any>} yarray
 * @param {number} index
 */
ArraySearchMarker? findMarker(AbstractType yarray, int index) {
  final _searchMarker = yarray.innerSearchMarker;
  if (yarray.innerStart == null || index == 0 || _searchMarker == null) {
    return null;
  }
  final marker = _searchMarker.length == 0
      ? null
      : _searchMarker.reduce(
          (a, b) => (index - a.index).abs() < (index - b.index).abs() ? a : b);
  var p = yarray.innerStart;
  var pindex = 0;
  if (marker != null) {
    p = marker.p;
    pindex = marker.index;
    refreshMarkerTimestamp(marker); // we used it, we might need to use it again
  }
  // iterate to right if possible
  if (p == null) {
    throw Exception("");
  }
  while (p != null && p.right != null && pindex < index) {
    if (!p.deleted && p.countable) {
      if (index < pindex + p.length) {
        break;
      }
      pindex += p.length;
    }
    p = p.right;
  }
  // iterate to left if necessary (might be that pindex > index)
  var pLeft = p?.left;
  while (pLeft != null && pindex > index) {
    p = pLeft;
    if (!p.deleted && p.countable) {
      pindex -= p.length;
    }
  }
  // we want to make sure that p can't be merged with left, because that would screw up everything
  // in that cas just return what we have (it is most likely the best marker anyway)
  // iterate to left until p can't be merged with left
  pLeft = p?.left;
  while (p != null &&
      pLeft != null &&
      pLeft.id.client == p.id.client &&
      pLeft.id.clock + pLeft.length == p.id.clock) {
    p = pLeft;
    if (!p.deleted && p.countable) {
      pindex -= p.length;
    }
  }

  // @todo remove!
  // assure position
  // {
  //   var start = yarray._start
  //   var pos = 0
  //   while (start != p) {
  //     if (!start.deleted && start.countable) {
  //       pos += start.length
  //     }
  //     start = /** @type {Item} */ (start.right)
  //   }
  //   if (pos != pindex) {
  //     debugger
  //     throw new Error('Gotcha position fail!')
  //   }
  // }
  // if (marker) {
  //   if (window.lengthes == null) {
  //     window.lengthes = []
  //     window.getLengthes = () => window.lengthes.sort((a, b) => a - b)
  //   }
  //   window.lengthes.push(marker.index - pindex)
  //   console.log('distance', marker.index - pindex, 'len', p && p.parent.length)
  // }
  if (p == null) {
    throw Exception("");
  }
  if (marker != null &&
      (marker.index - pindex).abs() < /** @type {YText|YList<any>} */ (p.parent
                  as AbstractType)
              .innerLength /
          maxSearchMarker) {
    // adjust existing marker
    overwriteMarker(marker, p, pindex);
    return marker;
  } else {
    // create new marker
    return markPosition(yarray.innerSearchMarker!, p, pindex);
  }
}

/**
 * Update markers when a change happened.
 *
 * This should be called before doing a deletion!
 *
 * @param {List<ArraySearchMarker>} searchMarker
 * @param {number} index
 * @param {number} len If insertion, len is positive. If deletion, len is negative.
 */
void updateMarkerChanges(
    List<ArraySearchMarker> searchMarker, int index, int len) {
  for (var i = searchMarker.length - 1; i >= 0; i--) {
    final m = searchMarker[i];
    if (len > 0) {
      /**
       * @type {Item|null}
       */
      Item? p = m.p;
      p.marker = false;
      // Ideally we just want to do a simple position comparison, but this will only work if
      // search markers don't point to deleted items for formats.
      // Iterate marker to prev undeleted countable position so we know what to do when updating a position
      while (p != null && (p.deleted || !p.countable)) {
        p = p.left;
        if (p != null && !p.deleted && p.countable) {
          // adjust position. the loop should break now
          m.index -= p.length;
        }
      }
      if (p == null || p.marker == true) {
        // remove search marker if updated position is null or if position is already marked
        searchMarker.removeAt(i);
        continue;
      }
      m.p = p;
      p.marker = true;
    }
    if (index < m.index || (len > 0 && index == m.index)) {
      // a simple index <= m.index check would actually suffice
      m.index = math.max(index, m.index + len);
    }
  }
}

/**
 * Accumulate all (list) children of a type and return them as an Array.
 *
 * @param {AbstractType<any>} t
 * @return {List<Item>}
 */
List<Item> getTypeChildren(AbstractType t) {
  var s = t.innerStart;
  final arr = <Item>[];
  while (s != null) {
    arr.add(s);
    s = s.right;
  }
  return arr;
}

/**
 * Call event listeners with an event. This will also add an event to all
 * parents (for `.observeDeep` handlers).
 *
 * @template EventType
 * @param {AbstractType<EventType>} type
 * @param {Transaction} transaction
 * @param {EventType} event
 */
void callTypeObservers<EventType extends YEvent>(
    AbstractType<EventType> type, Transaction transaction, EventType event) {
  final changedType = type;
  final changedParentTypes = transaction.changedParentTypes;

  AbstractType<YEvent> _type = type;
  while (true) {
    // @ts-ignore
    changedParentTypes.putIfAbsent(_type, () => []).add(event);
    if (_type.innerItem == null) {
      break;
    }
    _type = /** @type {AbstractType<any>} */ (_type.innerItem!.parent
        as AbstractType<YEvent>);
  }
  callEventHandlerListeners(changedType._eH, event, transaction);
}

/**
 * @template EventType
 * Abstract Yjs Type class
 */
class AbstractType<EventType> {
  static AbstractType<EventType> create<EventType>() =>
      AbstractType<EventType>();
  /**
     * @type {Item|null}
     */
  Item? innerItem;
  /**
     * @type {Map<string,Item>}
     */
  Map<String, Item> innerMap = {};
  /**
     * @type {Item|null}
     */
  Item? innerStart;
  /**
     * @type {Doc|null}
     */
  Doc? doc;
  int innerLength = 0;
  /**
     * Event handlers
     * @type {EventHandler<EventType,Transaction>}
     */
  final EventHandler<EventType, Transaction> _eH = createEventHandler();
  /**
     * Deep event handlers
     * @type {EventHandler<List<YEvent>,Transaction>}
     */
  final EventHandler<List<YEvent>, Transaction> innerdEH = createEventHandler();
  /**
     * @type {null | List<ArraySearchMarker>}
     */
  List<ArraySearchMarker>? innerSearchMarker;

  /**
   * @return {AbstractType<any>|null}
   */
  AbstractType? get parent {
    return this.innerItem?.parent as AbstractType?;
  }

  /**
   * Integrate this type into the Yjs instance.
   *
   * * Save this struct in the os
   * * This type is sent to other client
   * * Observer functions are fired
   *
   * @param {Doc} y The Yjs instance
   * @param {Item|null} item
   */
  void innerIntegrate(Doc y, Item? item) {
    this.doc = y;
    this.innerItem = item;
  }

  /**
   * @return {AbstractType<EventType>}
   */
  AbstractType<EventType> innerCopy() {
    throw UnimplementedError();
  }

  /**
   * @return {AbstractType<EventType>}
   */
  AbstractType<EventType> clone() {
    throw UnimplementedError();
  }

  /**
   * @param {AbstractUpdateEncoder} encoder
   */
  void innerWrite(AbstractUpdateEncoder encoder) {}

  /**
   * The first non-deleted item
   */
  Item? get innerFirst {
    var n = this.innerStart;
    while (n != null && n.deleted) {
      n = n.right;
    }
    return n;
  }

  /**
   * Creates YEvent and calls all type observers.
   * Must be implemented by each type.
   *
   * @param {Transaction} transaction
   * @param {Set<null|string>} parentSubs Keys changed on this type. `null` if list was modified.
   */
  void innerCallObserver(Transaction transaction, Set<String?> parentSubs) {
    if (!transaction.local && (this.innerSearchMarker?.isNotEmpty ?? false)) {
      this.innerSearchMarker!.length = 0;
    }
  }

  /**
   * Observe all events that are created on this type.
   *
   * @param {function(EventType, Transaction):void} f Observer function
   */
  void observe(void Function(EventType, Transaction) f) {
    addEventHandlerListener(this._eH, f);
  }

  /**
   * Observe all events that are created by this type and its children.
   *
   * @param {function(List<YEvent>,Transaction):void} f Observer function
   */
  void observeDeep(void Function(List<YEvent>, Transaction) f) {
    addEventHandlerListener(this.innerdEH, f);
  }

  /**
   * Unregister an observer function.
   *
   * @param {function(EventType,Transaction):void} f Observer function
   */
  void unobserve(void Function(EventType, Transaction) f) {
    removeEventHandlerListener(this._eH, f);
  }

  /**
   * Unregister an observer function.
   *
   * @param {function(List<YEvent>,Transaction):void} f Observer function
   */
  void unobserveDeep(void Function(List<YEvent>, Transaction) f) {
    removeEventHandlerListener(this.innerdEH, f);
  }

  /**
   * @abstract
   * @return {any}
   */
  Object toJSON() {
    throw UnimplementedError();
  }
}

/**
 * @param {AbstractType<any>} type
 * @param {number} start
 * @param {number} end
 * @return {List<any>}
 *
 * @private
 * @function
 */
List typeListSlice(AbstractType type, int start, int end) {
  if (start < 0) {
    start = type.innerLength + start;
  }
  if (end < 0) {
    end = type.innerLength + end;
  }
  var len = end - start;
  final cs = [];
  var n = type.innerStart;
  while (n != null && len > 0) {
    if (n.countable && !n.deleted) {
      final c = n.content.getContent();
      if (c.length <= start) {
        start -= c.length;
      } else {
        for (var i = start; i < c.length && len > 0; i++) {
          cs.add(c[i]);
          len--;
        }
        start = 0;
      }
    }
    n = n.right;
  }
  return cs;
}

/**
 * @param {AbstractType<any>} type
 * @return {List<any>}
 *
 * @private
 * @function
 */
List typeListToArray(AbstractType type) {
  final cs = [];
  var n = type.innerStart;
  while (n != null) {
    if (n.countable && !n.deleted) {
      final c = n.content.getContent();
      for (var i = 0; i < c.length; i++) {
        cs.add(c[i]);
      }
    }
    n = n.right;
  }
  return cs;
}

/**
 * @param {AbstractType<any>} type
 * @param {Snapshot} snapshot
 * @return {List<any>}
 *
 * @private
 * @function
 */
List typeListToArraySnapshot(AbstractType type, Snapshot snapshot) {
  final cs = [];
  var n = type.innerStart;
  while (n != null) {
    if (n.countable && isVisible(n, snapshot)) {
      final c = n.content.getContent();
      for (var i = 0; i < c.length; i++) {
        cs.add(c[i]);
      }
    }
    n = n.right;
  }
  return cs;
}

/**
 * Executes a provided function on once on overy element of this YArray.
 *
 * @param {AbstractType<any>} type
 * @param {function(any,number,any):void} f A function to execute on every element of this YArray.
 *
 * @private
 * @function
 */
void typeListForEach<L, R extends AbstractType>(
    R type, void Function(L, int, R) f) {
  var index = 0;
  var n = type.innerStart;
  while (n != null) {
    if (n.countable && !n.deleted) {
      final c = n.content.getContent();
      for (var i = 0; i < c.length; i++) {
        f(c[i], index++, type);
      }
    }
    n = n.right;
  }
}

/**
 * @template C,R
 * @param {AbstractType<any>} type
 * @param {function(C,number,AbstractType<any>):R} f
 * @return {List<R>}
 *
 * @private
 * @function
 */
List<R> typeListMap<C, R, T extends AbstractType>(
    T type, R Function(C, int, T) f) {
  /**
   * @type {List<any>}
   */
  final result = <R>[];
  typeListForEach<C, T>(type, (c, i, _) {
    result.add(f(c, i, type));
  });
  return result;
}

/**
 * @param {AbstractType<any>} type
 * @return {IterableIterator<any>}
 *
 * @private
 * @function
 */
Iterator<T> typeListCreateIterator<T>(AbstractType type) {
  return TypeListIterator<T>(type.innerStart);
}

class TypeListIterator<T> extends Iterator<T> {
  TypeListIterator(this.n);
  Item? n;
  List<dynamic>? currentContent;
  int currentContentIndex = 0;
  T? _value;

  @override
  T get current => _value as T;

  @override
  bool moveNext() {
    // find some content
    if (currentContent == null) {
      while (n != null && n!.deleted) {
        n = n!.right;
      }
      // check if we reached the end, no need to check currentContent, because it does not exist
      if (n == null) {
        return false;
      }
      // we found n, so we can set currentContent
      currentContent = n!.content.getContent();
      currentContentIndex = 0;
      n = n!.right; // we used the content of n, now iterate to next
    }
    final _currentContent = currentContent!;
    _value = _currentContent[currentContentIndex++] as T;
    // check if we need to empty currentContent
    if (_currentContent.length <= currentContentIndex) {
      currentContent = null;
    }
    return true;
  }
}

/**
 * Executes a provided function on once on overy element of this YArray.
 * Operates on a snapshotted state of the document.
 *
 * @param {AbstractType<any>} type
 * @param {function(any,number,AbstractType<any>):void} f A function to execute on every element of this YArray.
 * @param {Snapshot} snapshot
 *
 * @private
 * @function
 */
void typeListForEachSnapshot(AbstractType type,
    void Function(dynamic, int, AbstractType) f, Snapshot snapshot) {
  var index = 0;
  var n = type.innerStart;
  while (n != null) {
    if (n.countable && isVisible(n, snapshot)) {
      final c = n.content.getContent();
      for (var i = 0; i < c.length; i++) {
        f(c[i], index++, type);
      }
    }
    n = n.right;
  }
}

/**
 * @param {AbstractType<any>} type
 * @param {number} index
 * @return {any}
 *
 * @private
 * @function
 */
dynamic typeListGet(AbstractType type, int index) {
  final marker = findMarker(type, index);
  var n = type.innerStart;
  if (marker != null) {
    n = marker.p;
    index -= marker.index;
  }
  for (; n != null; n = n.right) {
    if (!n.deleted && n.countable) {
      if (index < n.length) {
        return n.content.getContent()[index];
      }
      index -= n.length;
    }
  }
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {Item?} referenceItem
 * @param {List<Object<string,any>|List<any>|boolean|number|string|Uint8Array>} content
 *
 * @private
 * @function
 */
void typeListInsertGenericsAfter(
  Transaction transaction,
  AbstractType parent,
  Item? referenceItem,
  dynamic content,
) {
  var left = referenceItem;
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  final store = doc.store;
  final right = referenceItem == null ? parent.innerStart : referenceItem.right;
  /**
   * @type {List<Object|List<any>|number>}
   */
  var jsonContent = [];
  final packJsonContent = () {
    if (jsonContent.length > 0) {
      left = Item(
          createID(ownClientId, getState(store, ownClientId)),
          left,
          left?.lastId,
          right,
          right?.id,
          parent,
          null,
          ContentAny(jsonContent));
      left!.integrate(transaction, 0);
      jsonContent = [];
    }
  };
  content.forEach((c) {
    if (c is int ||
        c is double ||
        c is num ||
        c is Map ||
        c is bool ||
        c is List ||
        c is String) {
      jsonContent.add(c);
    } else {
      packJsonContent();
      // or ArrayBuffer
      if (c is Uint8List) {
        left = Item(
            createID(ownClientId, getState(store, ownClientId)),
            left,
            left?.lastId,
            right,
            right?.id,
            parent,
            null,
            ContentBinary(/** @type {Uint8Array} */ (c)));
        left!.integrate(transaction, 0);
      } else if (c is Doc) {
        left = Item(
            createID(ownClientId, getState(store, ownClientId)),
            left,
            left?.lastId,
            right,
            right?.id,
            parent,
            null,
            ContentDoc(/** @type {Doc} */ (c)));
        left!.integrate(transaction, 0);
      } else if (c is AbstractType) {
        left = Item(createID(ownClientId, getState(store, ownClientId)), left,
            left?.lastId, right, right?.id, parent, null, ContentType(c));
        left!.integrate(transaction, 0);
      } else {
        throw Exception('Unexpected content type in insert operation');
      }
    }
  });
  packJsonContent();
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {number} index
 * @param {List<Object<string,any>|List<any>|number|string|Uint8Array>} content
 *
 * @private
 * @function
 */
void typeListInsertGenerics(
    Transaction transaction, AbstractType parent, int index, dynamic content) {
  if (index == 0) {
    if (parent.innerSearchMarker != null) {
      updateMarkerChanges(parent.innerSearchMarker!, index, content.length);
    }
    return typeListInsertGenericsAfter(transaction, parent, null, content);
  }
  final startIndex = index;
  final marker = findMarker(parent, index);
  var n = parent.innerStart;
  if (marker != null) {
    n = marker.p;
    index -= marker.index;
    // we need to iterate one to the left so that the algorithm works
    if (index == 0) {
      // @todo refactor this as it actually doesn't consider formats
      n = n
          .prev; // important! get the left undeleted item so that we can actually decrease index
      index += (n != null && n.countable && !n.deleted) ? n.length : 0;
    }
  }
  for (; n != null; n = n.right) {
    if (!n.deleted && n.countable) {
      if (index <= n.length) {
        if (index < n.length) {
          // insert in-between
          getItemCleanStart(
              transaction, createID(n.id.client, n.id.clock + index));
        }
        break;
      }
      index -= n.length;
    }
  }
  if (parent.innerSearchMarker != null) {
    updateMarkerChanges(parent.innerSearchMarker!, startIndex, content.length);
  }
  return typeListInsertGenericsAfter(transaction, parent, n, content);
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {number} index
 * @param {number} length
 *
 * @private
 * @function
 */
void typeListDelete(
    Transaction transaction, AbstractType parent, int index, int _length) {
  var length = _length;
  if (length == 0) {
    return;
  }
  final startIndex = index;
  final startLength = length;
  final marker = findMarker(parent, index);
  var n = parent.innerStart;
  if (marker != null) {
    n = marker.p;
    index -= marker.index;
  }
  // compute the first item to be deleted
  for (; n != null && index > 0; n = n.right) {
    if (!n.deleted && n.countable) {
      if (index < n.length) {
        getItemCleanStart(
            transaction, createID(n.id.client, n.id.clock + index));
      }
      index -= n.length;
    }
  }
  // delete all items until done
  while (length > 0 && n != null) {
    print("length $length");
    if (!n.deleted) {
      if (length < n.length) {
        getItemCleanStart(
            transaction, createID(n.id.client, n.id.clock + length));
      }
      n.delete(transaction);
      length -= n.length;
    }
    n = n.right;
  }
  print("out length $length");
  if (length > 0) {
    throw Exception('array length exceeded');
  }
  if (parent.innerSearchMarker != null) {
    updateMarkerChanges(parent.innerSearchMarker!, startIndex,
        -startLength + length /* in case we remove the above exception */);
  }
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {string} key
 *
 * @private
 * @function
 */
void typeMapDelete(Transaction transaction, AbstractType parent, String key) {
  final c = parent.innerMap.get(key);
  if (c != null) {
    c.delete(transaction);
  }
}

/**
 * @param {Transaction} transaction
 * @param {AbstractType<any>} parent
 * @param {string} key
 * @param {Object|number|List<any>|string|Uint8Array|AbstractType<any>} value
 *
 * @private
 * @function
 */
void typeMapSet(
    Transaction transaction, AbstractType parent, String key, dynamic value) {
  final left = parent.innerMap.get(key);
  final doc = transaction.doc;
  final ownClientId = doc.clientID;
  var content;
  if (value == null) {
    content = ContentAny([value]);
  } else {
    if (value is int ||
        value is num ||
        value is double ||
        value is Map ||
        value is bool ||
        value is List ||
        value is String) {
      content = ContentAny([value]);
    } else if (value is Uint8List) {
      content = ContentBinary(/** @type {Uint8Array} */ (value));
    } else if (value is Doc) {
      content = ContentDoc(/** @type {Doc} */ (value));
    } else {
      if (value is AbstractType) {
        content = ContentType(value);
      } else {
        throw Exception('Unexpected content type');
      }
    }
  }
  Item(createID(ownClientId, getState(doc.store, ownClientId)), left,
          left?.lastId, null, null, parent, key, content)
      .integrate(transaction, 0);
}

/**
 * @param {AbstractType<any>} parent
 * @param {string} key
 * @return {Object<string,any>|number|List<any>|string|Uint8Array|AbstractType<any>|undefined}
 *
 * @private
 * @function
 */
dynamic typeMapGet(AbstractType parent, String key) {
  final val = parent.innerMap.get(key);
  return val != null && !val.deleted
      ? val.content.getContent()[val.length - 1]
      : null;
}

/**
 * @param {AbstractType<any>} parent
 * @return {Object<string,Object<string,any>|number|List<any>|string|Uint8Array|AbstractType<any>|undefined>}
 *
 * @private
 * @function
 */
dynamic typeMapGetAll(AbstractType parent) {
  /**
   * @type {Object<string,any>}
   */
  final res = <String, dynamic>{};
  parent.innerMap.forEach((key, value) {
    if (!value.deleted) {
      res[key] = value.content.getContent()[value.length - 1];
    }
  });
  return res;
}

/**
 * @param {AbstractType<any>} parent
 * @param {string} key
 * @return {boolean}
 *
 * @private
 * @function
 */
bool typeMapHas(AbstractType parent, String key) {
  final val = parent.innerMap.get(key);
  return val != null && !val.deleted;
}

/**
 * @param {AbstractType<any>} parent
 * @param {string} key
 * @param {Snapshot} snapshot
 * @return {Object<string,any>|number|List<any>|string|Uint8Array|AbstractType<any>|undefined}
 *
 * @private
 * @function
 */
dynamic typeMapGetSnapshot(AbstractType parent, String key, Snapshot snapshot) {
  var v = parent.innerMap.get(key);
  while (v != null &&
      (!snapshot.sv.containsKey(v.id.client) ||
          v.id.clock >= (snapshot.sv.get(v.id.client) ?? 0))) {
    v = v.left;
  }
  return v != null && isVisible(v, snapshot)
      ? v.content.getContent()[v.length - 1]
      : null;
}

/**
 * @param {Map<string,Item>} map
 * @return {IterableIterator<List<any>>}
 *
 * @private
 * @function
 */
Iterable<MapEntry<String, Item>> createMapIterator(Map<String, Item> map) =>
    map.entries.where((entry) => !entry.value.deleted);
