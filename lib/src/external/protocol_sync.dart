import 'dart:typed_data';

import 'package:y_crdt/src/lib0/decoding.dart' as decoding;
import 'package:y_crdt/src/lib0/encoding.dart' as encoding;
/**
 * @module sync-protocol
 */
import 'package:y_crdt/y_crdt.dart' as Y;

/**
 * @typedef {Map<number, number>} StateMap
 */

/**
 * Core Yjs defines two message types:
 * • YjsSyncStep1: Includes the State Set of the sending client. When received, the client should reply with YjsSyncStep2.
 * • YjsSyncStep2: Includes all missing structs and the complete delete set. When received, the client is assured that it
 *   received all information from the remote client.
 *
 * In a peer-to-peer network, you may want to introduce a SyncDone message type. Both parties should initiate the connection
 * with SyncStep1. When a client received SyncStep2, it should reply with SyncDone. When the local client received both
 * SyncStep2 and SyncDone, it is assured that it is synced to the remote client.
 *
 * In a client-server model, you want to handle this differently: The client should initiate the connection with SyncStep1.
 * When the server receives SyncStep1, it should reply with SyncStep2 immediately followed by SyncStep1. The client replies
 * with SyncStep2 when it receives SyncStep1. Optionally the server may send a SyncDone after it received SyncStep2, so the
 * client knows that the sync is finished.  There are two reasons for this more elaborated sync model: 1. This protocol can
 * easily be implemented on top of http and websockets. 2. The server shoul only reply to requests, and not initiate them.
 * Therefore it is necesarry that the client initiates the sync.
 *
 * Construction of a message:
 * [messageType : varUint, message definition..]
 *
 * Note: A message does not include information about the room name. This must to be handled by the upper layer protocol!
 *
 * stringify[messageType] stringifies a message definition (messageType is already read from the bufffer)
 */

const messageYjsSyncStep1 = 0;
const messageYjsSyncStep2 = 1;
const messageYjsUpdate = 2;

/**
 * Create a sync step 1 message based on the state of the current shared document.
 *
 * @param {encoding.Encoder} encoder
 * @param {Y.Doc} doc
 */
void writeSyncStep1(encoding.Encoder encoder, Y.Doc doc) {
  encoding.writeVarUint(encoder, messageYjsSyncStep1);
  final sv = Y.encodeStateVector(doc);
  encoding.writeVarUint8Array(encoder, sv);
}

/**
 * @param {encoding.Encoder} encoder
 * @param {Y.Doc} doc
 * @param {Uint8Array} [encodedStateVector]
 */
void writeSyncStep2(
  encoding.Encoder encoder,
  Y.Doc doc,
  Uint8List? encodedStateVector,
) {
  encoding.writeVarUint(encoder, messageYjsSyncStep2);
  encoding.writeVarUint8Array(
    encoder,
    Y.encodeStateAsUpdate(doc, encodedStateVector),
  );
}

/**
 * Read SyncStep1 message and reply with SyncStep2.
 *
 * @param {decoding.Decoder} decoder The reply to the received message
 * @param {encoding.Encoder} encoder The received message
 * @param {Y.Doc} doc
 */
void readSyncStep1(
        decoding.Decoder decoder, encoding.Encoder encoder, Y.Doc doc) =>
    writeSyncStep2(encoder, doc, decoding.readVarUint8Array(decoder));

/**
 * Read and apply Structs and then DeleteStore to a y instance.
 *
 * @param {decoding.Decoder} decoder
 * @param {Y.Doc} doc
 * @param {any} transactionOrigin
 */
void readSyncStep2(
    decoding.Decoder decoder, Y.Doc doc, dynamic transactionOrigin) {
  Y.applyUpdate(doc, decoding.readVarUint8Array(decoder), transactionOrigin);
}

/**
 * @param {encoding.Encoder} encoder
 * @param {Uint8Array} update
 */
void writeUpdate(encoding.Encoder encoder, Uint8List update) {
  encoding.writeVarUint(encoder, messageYjsUpdate);
  encoding.writeVarUint8Array(encoder, update);
}

/**
 * Read and apply Structs and then DeleteStore to a y instance.
 *
 * @param {decoding.Decoder} decoder
 * @param {Y.Doc} doc
 * @param {any} transactionOrigin
 */
const readUpdate = readSyncStep2;

/**
 * @param {decoding.Decoder} decoder A message received from another client
 * @param {encoding.Encoder} encoder The reply message. Will not be sent if empty.
 * @param {Y.Doc} doc
 * @param {any} transactionOrigin
 */
int readSyncMessage(decoding.Decoder decoder, encoding.Encoder encoder,
    Y.Doc doc, Object transactionOrigin) {
  final messageType = decoding.readVarUint(decoder);
  switch (messageType) {
    case messageYjsSyncStep1:
      readSyncStep1(decoder, encoder, doc);
      break;
    case messageYjsSyncStep2:
      readSyncStep2(decoder, doc, transactionOrigin);
      break;
    case messageYjsUpdate:
      readUpdate(decoder, doc, transactionOrigin);
      break;
    default:
      throw Exception("Unknown message type");
  }
  return messageType;
}
