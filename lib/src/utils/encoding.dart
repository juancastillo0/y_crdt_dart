import 'dart:typed_data';

import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/structs/gc.dart';
import 'package:y_crdt/src/y_crdt_base.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';

/**
 * @module encoding
 */
/*
 * We use the first five bits in the info flag for determining the type of the struct.
 *
 * 0: GC
 * 1: Item with Deleted content
 * 2: Item with JSON content
 * 3: Item with Binary content
 * 4: Item with String content
 * 5: Item with Embed content (for richtext content)
 * 6: Item with Format content (a formatting marker for richtext content)
 * 7: Item with Type
 */

// import {
//   findIndexSS,
//   getState,
//   createID,
//   getStateVector,
//   readAndApplyDeleteSet,
//   writeDeleteSet,
//   createDeleteSetFromStructStore,
//   transact,
//   readItemContent,
//   UpdateDecoderV1,
//   UpdateDecoderV2,
//   UpdateEncoderV1,
//   UpdateEncoderV2,
//   DSDecoderV2,
//   DSEncoderV2,
//   DSDecoderV1,
//   DSEncoderV1,
//   AbstractDSEncoder,
//   AbstractDSDecoder,
//   AbstractUpdateEncoder,
//   AbstractUpdateDecoder,
//   AbstractContent,
//   Doc,
//   Transaction,
//   GC,
//   Item,
//   StructStore,
//   ID, // eslint-disable-line
// } from "../internals.js";

// import * as encoding from "lib0/encoding.js";
// import * as decoding from "lib0/decoding.js";
// import * as binary from "lib0/binary.js";
// import * as map from "lib0/map.js";

import "package:y_crdt/src/lib0/decoding.dart" as decoding;
import "package:y_crdt/src/lib0/encoding.dart" as encoding;
import 'package:y_crdt/src/lib0/binary.dart' as binary;

AbstractDSEncoder Function() DefaultDSEncoder = DSEncoderV1.create;
AbstractDSDecoder Function(decoding.Decoder) DefaultDSDecoder =
    DSDecoderV1.create;
AbstractUpdateEncoder Function() DefaultUpdateEncoder = UpdateEncoderV1.create;
AbstractUpdateDecoder Function(decoding.Decoder) DefaultUpdateDecoder =
    UpdateDecoderV1.create;

void useV1Encoding() {
  DefaultDSEncoder = DSEncoderV1.create;
  DefaultDSDecoder = DSDecoderV1.create;
  DefaultUpdateEncoder = UpdateEncoderV1.create;
  DefaultUpdateDecoder = UpdateDecoderV1.create;
}

void useV2Encoding() {
  DefaultDSEncoder = DSEncoderV2.create;
  DefaultDSDecoder = DSDecoderV2.create;
  DefaultUpdateEncoder = UpdateEncoderV2.create;
  DefaultUpdateDecoder = UpdateDecoderV2.create;
}

/**
 * @param {AbstractUpdateEncoder} encoder
 * @param {List<GC|Item>} structs All structs by `client`
 * @param {number} client
 * @param {number} clock write structs starting with `ID(client,clock)`
 *
 * @function
 */
void _writeStructs(AbstractUpdateEncoder encoder, List<AbstractStruct> structs,
    int client, int clock) {
  // write first id
  final startNewStructs = findIndexSS(structs, clock);
  // write # encoded structs
  encoding.writeVarUint(encoder.restEncoder, structs.length - startNewStructs);
  encoder.writeClient(client);
  encoding.writeVarUint(encoder.restEncoder, clock);
  final firstStruct = structs[startNewStructs];
  // write first struct with an offset
  firstStruct.write(encoder, clock - firstStruct.id.clock);
  for (var i = startNewStructs + 1; i < structs.length; i++) {
    structs[i].write(encoder, 0);
  }
}

/**
 * @param {AbstractUpdateEncoder} encoder
 * @param {StructStore} store
 * @param {Map<number,number>} _sm
 *
 * @private
 * @function
 */
void writeClientsStructs(
    AbstractUpdateEncoder encoder, StructStore store, Map<int, int> _sm) {
  // we filter all valid _sm entries into sm
  final sm = <int, int>{};
  _sm.forEach((client, clock) {
    // only write if new structs are available
    if (getState(store, client) > clock) {
      sm.set(client, clock);
    }
  });
  getStateVector(store).forEach((client, clock) {
    if (!_sm.containsKey(client)) {
      sm.set(client, 0);
    }
  });
  // write # states that were updated
  encoding.writeVarUint(encoder.restEncoder, sm.length);
  // Write items with higher client ids first
  // This heavily improves the conflict algorithm.
  final entries = sm.entries.toList();
  entries.sort((a, b) => b.key - a.key);
  entries.forEach((entry) {
    // @ts-ignore
    _writeStructs(
        encoder, store.clients.get(entry.key)!, entry.key, entry.value);
  });
}

/**
 * @param {AbstractUpdateDecoder} decoder The decoder object to read data from.
 * @param {Map<number,List<GC|Item>>} clientRefs
 * @param {Doc} doc
 * @return {Map<number,List<GC|Item>>}
 *
 * @private
 * @function
 */
Map<int, List<AbstractStruct>> readClientsStructRefs(
    AbstractUpdateDecoder decoder,
    Map<int, List<AbstractStruct>> clientRefs,
    Doc doc) {
  final numOfStateUpdates = decoding.readVarUint(decoder.restDecoder);
  for (var i = 0; i < numOfStateUpdates; i++) {
    final numberOfStructs = decoding.readVarUint(decoder.restDecoder);
    /**
     * @type {List<GC|Item>}
     */
    final refs = <AbstractStruct>[];
    final client = decoder.readClient();
    var clock = decoding.readVarUint(decoder.restDecoder);
    // final start = performance.now()
    clientRefs.set(client, refs);
    for (var i = 0; i < numberOfStructs; i++) {
      final info = decoder.readInfo();
      if ((binary.BITS5 & info) != 0) {
        /**
         * The optimized implementation doesn't use any variables because inlining variables is faster.
         * Below a non-optimized version is shown that implements the basic algorithm with
         * a few comments
         */
        final cantCopyParentInfo = (info & (binary.BIT7 | binary.BIT8)) == 0;
        // If parent = null and neither left nor right are defined, then we know that `parent` is child of `y`
        // and we read the next string as parentYKey.
        // It indicates how we store/retrieve parent from `y.share`
        // @type {string|null}
        final struct = Item(
            createID(client, clock),
            null, // leftd
            (info & binary.BIT8) == binary.BIT8
                ? decoder.readLeftID()
                : null, // origin
            null, // right
            (info & binary.BIT7) == binary.BIT7
                ? decoder.readRightID()
                : null, // right origin
            cantCopyParentInfo
                ? decoder.readParentInfo()
                    ? doc.get(decoder.readString())
                    : decoder.readLeftID()
                : null, // parent
            cantCopyParentInfo && (info & binary.BIT6) == binary.BIT6
                ? decoder.readString()
                : null, // parentSub
            readItemContent(decoder, info) as AbstractContent // item content
            );
        /* A non-optimized implementation of the above algorithm:

        // The item that was originally to the left of this item.
        const origin = (info & binary.BIT8) == binary.BIT8 ? decoder.readLeftID() : null
        // The item that was originally to the right of this item.
        const rightOrigin = (info & binary.BIT7) == binary.BIT7 ? decoder.readRightID() : null
        const cantCopyParentInfo = (info & (binary.BIT7 | binary.BIT8)) == 0
        const hasParentYKey = cantCopyParentInfo ? decoder.readParentInfo() : false
        // If parent = null and neither left nor right are defined, then we know that `parent` is child of `y`
        // and we read the next string as parentYKey.
        // It indicates how we store/retrieve parent from `y.share`
        // @type {string|null}
        const parentYKey = cantCopyParentInfo && hasParentYKey ? decoder.readString() : null

        const struct = new Item(
          createID(client, clock),
          null, // leftd
          origin, // origin
          null, // right
          rightOrigin, // right origin
          cantCopyParentInfo && !hasParentYKey ? decoder.readLeftID() : (parentYKey != null ? doc.get(parentYKey) : null), // parent
          cantCopyParentInfo && (info & binary.BIT6) == binary.BIT6 ? decoder.readString() : null, // parentSub
          readItemContent(decoder, info) // item content
        )
        */
        refs.add(struct);
        clock += struct.length;
      } else {
        final len = decoder.readLen();
        refs.add(GC(createID(client, clock), len));
        clock += len;
      }
    }
    // console.log('time to read: ', performance.now() - start) // @todo remove
  }
  return clientRefs;
}

/**
 * Resume computing structs generated by struct readers.
 *
 * While there is something to do, we integrate structs in this order
 * 1. top element on stack, if stack is not empty
 * 2. next element from current struct reader (if empty, use next struct reader)
 *
 * If struct causally depends on another struct (ref.missing), we put next reader of
 * `ref.id.client` on top of stack.
 *
 * At some point we find a struct that has no causal dependencies,
 * then we start emptying the stack.
 *
 * It is not possible to have circles: i.e. struct1 (from client1) depends on struct2 (from client2)
 * depends on struct3 (from client1). Therefore the max stack size is eqaul to `structReaders.length`.
 *
 * This method is implemented in a way so that we can resume computation if this update
 * causally depends on another update.
 *
 * @param {Transaction} transaction
 * @param {StructStore} store
 *
 * @private
 * @function
 */
void _resumeStructIntegration(Transaction transaction, StructStore store) {
  final stack =
      store.pendingStack; // @todo don't forget to append stackhead at the end
  final clientsStructRefs = store.pendingClientsStructRefs;
  // sort them so that we take the higher id first, in case of conflicts the lower id will probably not conflict with the id from the higher user.
  final clientsStructRefsIds = clientsStructRefs.keys.toList();
  clientsStructRefsIds.sort((a, b) => a - b);
  if (clientsStructRefsIds.length == 0) {
    return;
  }
  final getNextStructTarget = () {
    var nextStructsTarget = /** @type {{i:number,refs:List<GC|Item>}} */ (clientsStructRefs
        .get(clientsStructRefsIds[clientsStructRefsIds.length - 1]));
    while (nextStructsTarget!.refs.length == nextStructsTarget.i) {
      clientsStructRefsIds.removeLast();
      if (clientsStructRefsIds.length > 0) {
        nextStructsTarget = /** @type {{i:number,refs:List<GC|Item>}} */ (clientsStructRefs
            .get(clientsStructRefsIds[clientsStructRefsIds.length - 1]));
      } else {
        store.pendingClientsStructRefs.clear();
        return null;
      }
    }
    return nextStructsTarget;
  };
  var curStructsTarget = getNextStructTarget();
  if (curStructsTarget == null && stack.length == 0) {
    return;
  }
  /**
   * @type {GC|Item}
   */
  var stackHead = stack.length > 0
      ? /** @type {GC|Item} */ (stack.removeLast())
      : /** @type {any} */ (curStructsTarget!).refs[
          /** @type {any} */ (curStructsTarget).i++];
  // caching the state because it is used very often
  final state = <int, int>{};
  // iterate over all struct readers until we are done
  while (true) {
    final localClock = state.putIfAbsent(
        stackHead.id.client, () => getState(store, stackHead.id.client));
    final offset =
        stackHead.id.clock < localClock ? localClock - stackHead.id.clock : 0;
    if (stackHead.id.clock + offset != localClock) {
      // A previous message from this client is missing
      // check if there is a pending structRef with a smaller clock and switch them
      /**
       * @type {{ refs: List<GC|Item>, i: number }}
       */
      final structRefs = clientsStructRefs.get(stackHead.id.client) ??
          PendingStructRef(
            refs: [],
            i: 0,
          );
      if (structRefs.refs.length != structRefs.i) {
        final r = structRefs.refs[structRefs.i];
        if (r.id.clock < stackHead.id.clock) {
          // put ref with smaller clock on stack instead and continue
          structRefs.refs[structRefs.i] = stackHead;
          stackHead = r;
          // sort the set because this approach might bring the list out of order
          structRefs.refs = structRefs.refs
              .getRange(structRefs.i, structRefs.refs.length)
              .toList()
                ..sort((r1, r2) => r1.id.clock - r2.id.clock);
          structRefs.i = 0;
          continue;
        }
      }
      // wait until missing struct is available
      stack.add(stackHead);
      return;
    }
    int? missing;
    if (stackHead is Item) {
      missing = stackHead.getMissing(transaction, store);
    } else if (stackHead is GC) {
      missing = stackHead.getMissing(transaction, store);
    } else {
      throw Exception();
    }
    if (missing == null) {
      if (offset == 0 || offset < stackHead.length) {
        stackHead.integrate(transaction, offset);
        state.set(stackHead.id.client, stackHead.id.clock + stackHead.length);
      }
      // iterate to next stackHead
      if (stack.length > 0) {
        stackHead = /** @type {GC|Item} */ (stack.removeLast());
      } else if (curStructsTarget != null &&
          curStructsTarget.i < curStructsTarget.refs.length) {
        stackHead = /** @type {GC|Item} */ (curStructsTarget
            .refs[curStructsTarget.i++]);
      } else {
        curStructsTarget = getNextStructTarget();
        if (curStructsTarget == null) {
          // we are done!
          break;
        } else {
          stackHead = /** @type {GC|Item} */ (curStructsTarget
              .refs[curStructsTarget.i++]);
        }
      }
    } else {
      // get the struct reader that has the missing struct
      /**
       * @type {{ refs: List<GC|Item>, i: number }}
       */
      final structRefs =
          clientsStructRefs.get(missing) ?? PendingStructRef(refs: [], i: 0);
      if (structRefs.refs.length == structRefs.i) {
        // This update message causally depends on another update message.
        stack.add(stackHead);
        return;
      }
      stack.add(stackHead);
      stackHead = structRefs.refs[structRefs.i++];
    }
  }
  store.pendingClientsStructRefs.clear();
}

/**
 * @param {Transaction} transaction
 * @param {StructStore} store
 *
 * @private
 * @function
 */
void tryResumePendingDeleteReaders(Transaction transaction, StructStore store) {
  final pendingReaders = store.pendingDeleteReaders;
  store.pendingDeleteReaders = [];
  for (var i = 0; i < pendingReaders.length; i++) {
    readAndApplyDeleteSet(pendingReaders[i], transaction, store);
  }
}

/**
 * @param {AbstractUpdateEncoder} encoder
 * @param {Transaction} transaction
 *
 * @private
 * @function
 */
void writeStructsFromTransaction(
        AbstractUpdateEncoder encoder, Transaction transaction) =>
    writeClientsStructs(
        encoder, transaction.doc.store, transaction.beforeState);

/**
 * @param {StructStore} store
 * @param {Map<number, List<GC|Item>>} clientsStructsRefs
 *
 * @private
 * @function
 */
void mergeReadStructsIntoPendingReads(
    StructStore store, Map<int, List<AbstractStruct>> clientsStructsRefs) {
  final pendingClientsStructRefs = store.pendingClientsStructRefs;
  clientsStructsRefs.forEach((client, structRefs) {
    final pendingStructRefs = pendingClientsStructRefs.get(client);
    if (pendingStructRefs == null) {
      pendingClientsStructRefs.set(
          client, PendingStructRef(refs: structRefs, i: 0));
    } else {
      // merge into existing structRefs
      final merged = pendingStructRefs.i > 0
          ? pendingStructRefs.refs
              .getRange(pendingStructRefs.i, pendingStructRefs.refs.length)
              .toList()
          : pendingStructRefs.refs;
      for (var i = 0; i < structRefs.length; i++) {
        merged.add(structRefs[i]);
      }
      pendingStructRefs.i = 0;

      merged.sort((r1, r2) => r1.id.clock - r2.id.clock);
      pendingStructRefs.refs = merged;
    }
  });
}

/**
 * @param {Map<number,{refs:List<GC|Item>,i:number}>} pendingClientsStructRefs
 */
void cleanupPendingStructs(
    Map<int, PendingStructRef> pendingClientsStructRefs) {
  // cleanup pendingClientsStructs if not fully finished
  // TODO: should we copy?
  ({...pendingClientsStructRefs}).forEach((client, refs) {
    if (refs.i == refs.refs.length) {
      pendingClientsStructRefs.remove(client);
    } else {
      refs.refs.removeRange(0, refs.i);
      refs.i = 0;
    }
  });
}

/**
 * Read the next Item in a Decoder and fill this Item with the read data.
 *
 * This is called when data is received from a remote peer.
 *
 * @param {AbstractUpdateDecoder} decoder The decoder object to read data from.
 * @param {Transaction} transaction
 * @param {StructStore} store
 *
 * @private
 * @function
 */
void readStructs(
    AbstractUpdateDecoder decoder, Transaction transaction, StructStore store) {
  final clientsStructRefs = <int, List<AbstractStruct>>{};
  // var start = performance.now()
  readClientsStructRefs(decoder, clientsStructRefs, transaction.doc);
  // console.log('time to read structs: ', performance.now() - start) // @todo remove
  // start = performance.now()
  mergeReadStructsIntoPendingReads(store, clientsStructRefs);
  // console.log('time to merge: ', performance.now() - start) // @todo remove
  // start = performance.now()
  _resumeStructIntegration(transaction, store);
  // console.log('time to integrate: ', performance.now() - start) // @todo remove
  // start = performance.now()
  cleanupPendingStructs(store.pendingClientsStructRefs);
  // console.log('time to cleanup: ', performance.now() - start) // @todo remove
  // start = performance.now()
  tryResumePendingDeleteReaders(transaction, store);
  // console.log('time to resume delete readers: ', performance.now() - start) // @todo remove
  // start = performance.now()
}

/**
 * Read and apply a document update.
 *
 * This function has the same effect as `applyUpdate` but accepts an decoder.
 *
 * @param {decoding.Decoder} decoder
 * @param {Doc} ydoc
 * @param {any} [transactionOrigin] This will be stored on `transaction.origin` and `.on('update', (update, origin))`
 * @param {AbstractUpdateDecoder} [structDecoder]
 *
 * @function
 */
void readUpdateV2(decoding.Decoder decoder, Doc ydoc, dynamic transactionOrigin,
    AbstractUpdateDecoder? structDecoder) {
  final _structDecoder = structDecoder ?? DefaultUpdateDecoder(decoder);
  transact(ydoc, (transaction) {
    readStructs(_structDecoder, transaction, ydoc.store);
    readAndApplyDeleteSet(_structDecoder, transaction, ydoc.store);
  }, transactionOrigin, false);
}

/**
 * Read and apply a document update.
 *
 * This function has the same effect as `applyUpdate` but accepts an decoder.
 *
 * @param {decoding.Decoder} decoder
 * @param {Doc} ydoc
 * @param {any} [transactionOrigin] This will be stored on `transaction.origin` and `.on('update', (update, origin))`
 *
 * @function
 */
void readUpdate(
        decoding.Decoder decoder, Doc ydoc, dynamic transactionOrigin) =>
    readUpdateV2(
        decoder, ydoc, transactionOrigin, DefaultUpdateDecoder(decoder));

/**
 * Apply a document update created by, for example, `y.on('update', update => ..)` or `update = encodeStateAsUpdate()`.
 *
 * This function has the same effect as `readUpdate` but accepts an Uint8Array instead of a Decoder.
 *
 * @param {Doc} ydoc
 * @param {Uint8Array} update
 * @param {any} [transactionOrigin] This will be stored on `transaction.origin` and `.on('update', (update, origin))`
 * @param {typeof UpdateDecoderV1 | typeof UpdateDecoderV2} [YDecoder]
 *
 * @function
 */
void applyUpdateV2(
  Doc ydoc,
  Uint8List update,
  dynamic transactionOrigin, [
  AbstractUpdateDecoder Function(decoding.Decoder decoder)? YDecoder,
]) {
  final _YDecoder = YDecoder ?? UpdateDecoderV2.create;
  final decoder = decoding.createDecoder(update);
  readUpdateV2(decoder, ydoc, transactionOrigin, _YDecoder(decoder));
}

/**
 * Apply a document update created by, for example, `y.on('update', update => ..)` or `update = encodeStateAsUpdate()`.
 *
 * This function has the same effect as `readUpdate` but accepts an Uint8Array instead of a Decoder.
 *
 * @param {Doc} ydoc
 * @param {Uint8Array} update
 * @param {any} [transactionOrigin] This will be stored on `transaction.origin` and `.on('update', (update, origin))`
 *
 * @function
 */
void applyUpdate(Doc ydoc, Uint8List update, dynamic transactionOrigin) =>
    applyUpdateV2(ydoc, update, transactionOrigin, DefaultUpdateDecoder);

/**
 * Write all the document as a single update message. If you specify the state of the remote client (`targetStateVector`) it will
 * only write the operations that are missing.
 *
 * @param {AbstractUpdateEncoder} encoder
 * @param {Doc} doc
 * @param {Map<number,number>} [targetStateVector] The state of the target that receives the update. Leave empty to write all known structs
 *
 * @function
 */
void writeStateAsUpdate(AbstractUpdateEncoder encoder, Doc doc,
    [Map<int, int> targetStateVector = const <int, int>{}]) {
  writeClientsStructs(encoder, doc.store, targetStateVector);
  writeDeleteSet(encoder, createDeleteSetFromStructStore(doc.store));
}

/**
 * Write all the document as a single update message that can be applied on the remote document. If you specify the state of the remote client (`targetState`) it will
 * only write the operations that are missing.
 *
 * Use `writeStateAsUpdate` instead if you are working with lib0/encoding.js#Encoder
 *
 * @param {Doc} doc
 * @param {Uint8Array} [encodedTargetStateVector] The state of the target that receives the update. Leave empty to write all known structs
 * @param {AbstractUpdateEncoder} [encoder]
 * @return {Uint8Array}
 *
 * @function
 */
Uint8List encodeStateAsUpdateV2(
  Doc doc,
  Uint8List? encodedTargetStateVector, [
  AbstractUpdateEncoder? encoder,
]) {
  final _encoder = encoder ?? UpdateEncoderV2();
  final targetStateVector = encodedTargetStateVector == null
      ? const <int, int>{}
      : decodeStateVector(encodedTargetStateVector);
  writeStateAsUpdate(_encoder, doc, targetStateVector);
  return _encoder.toUint8Array();
}

/**
 * Write all the document as a single update message that can be applied on the remote document. If you specify the state of the remote client (`targetState`) it will
 * only write the operations that are missing.
 *
 * Use `writeStateAsUpdate` instead if you are working with lib0/encoding.js#Encoder
 *
 * @param {Doc} doc
 * @param {Uint8Array} [encodedTargetStateVector] The state of the target that receives the update. Leave empty to write all known structs
 * @return {Uint8Array}
 *
 * @function
 */
Uint8List encodeStateAsUpdate(Doc doc, Uint8List? encodedTargetStateVector) =>
    encodeStateAsUpdateV2(
        doc, encodedTargetStateVector, DefaultUpdateEncoder());

/**
 * Read state vector from Decoder and return as Map
 *
 * @param {AbstractDSDecoder} decoder
 * @return {Map<number,number>} Maps `client` to the number next expected `clock` from that client.
 *
 * @function
 */
Map<int, int> readStateVector(AbstractDSDecoder decoder) {
  final ss = <int, int>{};
  final ssLength = decoding.readVarUint(decoder.restDecoder);
  for (var i = 0; i < ssLength; i++) {
    final client = decoding.readVarUint(decoder.restDecoder);
    final clock = decoding.readVarUint(decoder.restDecoder);
    ss.set(client, clock);
  }
  return ss;
}

/**
 * Read decodedState and return State as Map.
 *
 * @param {Uint8Array} decodedState
 * @return {Map<number,number>} Maps `client` to the number next expected `clock` from that client.
 *
 * @function
 */
Map<int, int> decodeStateVectorV2(Uint8List decodedState) =>
    readStateVector(DSDecoderV2(decoding.createDecoder(decodedState)));

/**
 * Read decodedState and return State as Map.
 *
 * @param {Uint8Array} decodedState
 * @return {Map<number,number>} Maps `client` to the number next expected `clock` from that client.
 *
 * @function
 */
Map<int, int> decodeStateVector(Uint8List decodedState) =>
    readStateVector(DefaultDSDecoder(decoding.createDecoder(decodedState)));

/**
 * @param {AbstractDSEncoder} encoder
 * @param {Map<number,number>} sv
 * @function
 */
AbstractDSEncoder writeStateVector(
    AbstractDSEncoder encoder, Map<int, int> sv) {
  encoding.writeVarUint(encoder.restEncoder, sv.length);
  sv.forEach((client, clock) {
    encoding.writeVarUint(encoder.restEncoder,
        client); // @todo use a special client decoder that is based on mapping
    encoding.writeVarUint(encoder.restEncoder, clock);
  });
  return encoder;
}

/**
 * @param {AbstractDSEncoder} encoder
 * @param {Doc} doc
 *
 * @function
 */
void writeDocumentStateVector(AbstractDSEncoder encoder, Doc doc) =>
    writeStateVector(encoder, getStateVector(doc.store));

/**
 * Encode State as Uint8Array.
 *
 * @param {Doc} doc
 * @param {AbstractDSEncoder} [encoder]
 * @return {Uint8Array}
 *
 * @function
 */
Uint8List encodeStateVectorV2(Doc doc, [AbstractDSEncoder? encoder]) {
  final _encoder = encoder ?? DSEncoderV2();
  writeDocumentStateVector(_encoder, doc);
  return _encoder.toUint8Array();
}

/**
 * Encode State as Uint8Array.
 *
 * @param {Doc} doc
 * @return {Uint8Array}
 *
 * @function
 */
Uint8List encodeStateVector(Doc doc) =>
    encodeStateVectorV2(doc, DefaultDSEncoder());
