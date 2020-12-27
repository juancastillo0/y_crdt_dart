import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import 'package:y_crdt/src/structs/content_doc.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/types/y_array.dart';
import 'package:y_crdt/src/types/y_map.dart';
import 'package:y_crdt/src/types/y_text.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart' show Transaction, transact;
import 'package:y_crdt/src/utils/y_event.dart';
import 'package:y_crdt/src/utils/observable.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

const globalTransact = transact;
/**
 * @module Y
 */

// import {
//   StructStore,
//   AbstractType,
//   YArray,
//   YText,
//   YMap,
//   YXmlFragment,
//   transact,
//   ContentDoc,
//   Item,
//   Transaction,
//   YEvent, // eslint-disable-line
// } from "../internals.js";

// import { Observable } from "lib0/observable.js";
// import * as random from "lib0/random.js";
// import * as map from "lib0/map.js";
// import * as array from "lib0/array.js";

final _random = math.Random();
final _uuid = Uuid();
int generateNewClientId() => _random.nextInt(4294967295);

/**
 * @typedef {Object} DocOpts
 * @property {boolean} [DocOpts.gc=true] Disable garbage collection (default: gc=true)
 * @property {function(Item):boolean} [DocOpts.gcFilter] Will be called before an Item is garbage collected. Return false to keep the Item.
 * @property {string} [DocOpts.guid] Define a globally unique identifier for this document
 * @property {any} [DocOpts.meta] Any kind of meta information you want to associate with this document. If this is a subdocument, remote peers will store the meta information as well.
 * @property {boolean} [DocOpts.autoLoad] If a subdocument, automatically load document. If this is a subdocument, remote peers will load the document as well automatically.
 */

/**
 * A Yjs instance handles the state of shared data.
 * @extends Observable<string>
 */
class Doc extends Observable<String> {
  static bool defaultGcFilter(Item _) => true;
  /**
   * @param {DocOpts} [opts] configuration
   */
  Doc({
    String? guid,
    bool? gc,
    this.gcFilter = Doc.defaultGcFilter,
    this.meta,
    bool? autoLoad,
  })  : autoLoad = autoLoad ?? false,
        shouldLoad = autoLoad ?? false,
        gc = gc ?? true {
    this.guid = guid ?? _uuid.v4();
  }
  final bool gc;
  final bool Function(Item) gcFilter;
  int clientID = generateNewClientId();
  late final String guid;
  /**
     * @type {Map<string, AbstractType<YEvent>>}
     */
  final share = <String, AbstractType<YEvent>>{};
  final StructStore store = StructStore();
  /**
     * @type {Transaction | null}
     */
  Transaction? transaction;
  /**
     * @type {List<Transaction>}
     */
  List<Transaction> transactionCleanups = [];
  /**
     * @type {Set<Doc>}
     */
  final subdocs = <Doc>{};
  /**
     * If this document is a subdocument - a document integrated into another document - then _item is defined.
     * @type {Item?}
     */
  Item? item;
  bool shouldLoad;
  final bool autoLoad;
  final dynamic meta;

  /**
   * Notify the parent document that you request to load data into this subdocument (if it is a subdocument).
   *
   * `load()` might be used in the future to request any provider to load the most current data.
   *
   * It is safe to call `load()` multiple times.
   */
  void load() {
    final item = this.item;
    if (item != null && !this.shouldLoad) {
      globalTransact(
          /** @type {any} */ (item.parent as dynamic).doc as Doc,
          (transaction) {
        transaction.subdocsLoaded.add(this);
      }, null, true);
    }
    this.shouldLoad = true;
  }

  Set<Doc> getSubdocs() {
    return this.subdocs;
  }

  Set<dynamic> getSubdocGuids() {
    return this.subdocs.map((doc) => doc.guid).toSet();
  }

  /**
   * Changes that happen inside of a transaction are bundled. This means that
   * the observer fires _after_ the transaction is finished and that all changes
   * that happened inside of the transaction are sent as one message to the
   * other peers.
   *
   * @param {function(Transaction):void} f The function that should be executed as a transaction
   * @param {any} [origin] Origin of who started the transaction. Will be stored on transaction.origin
   *
   * @public
   */
  void transact(void Function(Transaction) f, [dynamic origin]) {
    globalTransact(this, f, origin);
  }

  /**
   * Define a shared data type.
   *
   * Multiple calls of `y.get(name, TypeConstructor)` yield the same result
   * and do not overwrite each other. I.e.
   * `y.define(name, Y.Array) == y.define(name, Y.Array)`
   *
   * After this method is called, the type is also available on `y.share.get(name)`.
   *
   * *Best Practices:*
   * Define all types right after the Yjs instance is created and store them in a separate object.
   * Also use the typed methods `getText(name)`, `getArray(name)`, ..
   *
   * @example
   *   const y = new Y(..)
   *   const appState = {
   *     document: y.getText('document')
   *     comments: y.getArray('comments')
   *   }
   *
   * @param {string} name
   * @param {Function} TypeConstructor The constructor of the type definition. E.g. Y.Text, Y.Array, Y.Map, ...
   * @return {AbstractType<any>} The created type. Constructed with TypeConstructor
   *
   * @public
   */
  AbstractType<YEvent> get<T extends AbstractType<YEvent>>(
    String name, [
    T Function()? typeConstructor,
  ]) {
    if (typeConstructor == null) {
      if (T.toString() == "AbstractType<YEvent>") {
        typeConstructor = () => AbstractType.create<YEvent>() as T;
      } else {
        throw Exception();
      }
    }
    final type = this.share.putIfAbsent(name, () {
      // @ts-ignore
      final t = typeConstructor!();
      t.innerIntegrate(this, null);
      return t;
    });
    if (type is AbstractType && type is! T) {
      if (T.toString() == "AbstractType<YEvent>") {
        // @ts-ignore
        final t = typeConstructor();
        t.innerMap = type.innerMap;
        type.innerMap.forEach(
            /** @param {Item?} n */ (_, n) {
          Item? item = n;
          for (; item != null; item = item.left) {
            // @ts-ignore
            item.parent = t;
          }
        });
        t.innerStart = type.innerStart;
        for (var n = t.innerStart; n != null; n = n.right) {
          n.parent = t;
        }
        t.innerLength = type.innerLength;
        this.share.set(name, t);
        t.innerIntegrate(this, null);
        return t;
      } else {
        throw Exception(
            "Type with the name ${name} has already been defined with a different constructor");
      }
    }
    return type;
  }

  /**
   * @template T
   * @param {string} [name]
   * @return {YList<T>}
   *
   * @public
   */
  YArray<T> getArray<T>([String name = ""]) {
    // @ts-ignore
    return this.get<YArray<T>>(name, YArray.create) as YArray<T>;
  }

  /**
   * @param {string} [name]
   * @return {YText}
   *
   * @public
   */
  YText getText([String name = ""]) {
    // @ts-ignore
    return this.get<YText>(name, YText.create) as YText;
  }

  /**
   * @param {string} [name]
   * @return {YMap<any>}
   *
   * @public
   */
  YMap<T> getMap<T>([String name = ""]) {
    // @ts-ignore
    return this.get<YMap<T>>(name, YMap.create) as YMap<T>;
  }

  /**
   * @param {string} [name]
   * @return {YXmlFragment}
   *
   * @public
   */
  // TODO
  // YXmlFragment getXmlFragment([String name = ""]) {
  //   // @ts-ignore
  //   return this.get(name, YXmlFragment.create) as YXmlFragment;
  // }

  /**
   * Converts the entire document into a js object, recursively traversing each yjs type
   *
   * @return {Object<string, any>}
   */
  Map<String, dynamic> toJSON() {
    /**
     * @type {Object<string, any>}
     */
    const doc = <String, dynamic>{};

    // TODO: use Map.map
    this.share.forEach((key, value) {
      doc[key] = value.toJSON();
    });

    return doc;
  }

  /**
   * Emit `destroy` event and unregister all event handlers.
   */
  void destroy() {
    this.subdocs.toList().forEach((subdoc) => subdoc.destroy());
    final item = this.item;
    if (item != null) {
      this.item = null;
      final content = /** @type {ContentDoc} */ (item.content) as ContentDoc;
      if (item.deleted) {
        // @ts-ignore
        content.doc = null;
      } else {
        content.doc = Doc(
          guid: this.guid,
          autoLoad: content.opts.autoLoad,
          gc: content.opts.gc,
          meta: content.opts.meta,
        );
        content.doc!.item = item;
      }
      globalTransact(
          /** @type {any} */ (item.parent as dynamic).doc as Doc,
          (transaction) {
        if (!item.deleted) {
          transaction.subdocsAdded.add(content.doc!);
        }
        transaction.subdocsRemoved.add(this);
      }, null, true);
    }
    this.emit("destroyed", [true]);
    this.emit("destroy", [this]);
    super.destroy();
  }

  /**
   * @param {string} eventName
   * @param {function(...any):any} f
   */
  void on(String eventName, void Function(List<dynamic>) f) {
    super.on(eventName, f);
  }

  /**
   * @param {string} eventName
   * @param {function} f
   */
  void off(String eventName, void Function(List<dynamic>) f) {
    super.off(eventName, f);
  }
}
