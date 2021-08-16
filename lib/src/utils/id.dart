// import { AbstractType } from '../internals.js' // eslint-disable-line

import 'package:y_crdt/src/lib0/decoding.dart' as decoding;
import 'package:y_crdt/src/lib0/encoding.dart' as encoding;
// import * as decoding from 'lib0/decoding.js'
// import * as encoding from 'lib0/encoding.js'
// import * as error from 'lib0/error.js'

import 'package:y_crdt/src/types/abstract_type.dart';

class ID {
  /**
   * @param {number} client client id
   * @param {number} clock unique per client id, continuous number
   */
  ID(this.client, this.clock);

  /**
   * Client id
   * @type {number}
   */
  final int client;

  /**
   * unique per client id, continuous number
   * @type {number}
   */
  int clock;
}

/**
 * @param {ID | null} a
 * @param {ID | null} b
 * @return {boolean}
 *
 * @function
 */
bool compareIDs(ID? a, ID? b) =>
    a == b ||
    (a != null && b != null && a.client == b.client && a.clock == b.clock);

/**
 * @param {number} client
 * @param {number} clock
 *
 * @private
 * @function
 */
ID createID(int client, int clock) => ID(client, clock);

/**
 * @param {encoding.Encoder} encoder
 * @param {ID} id
 *
 * @private
 * @function
 */
void writeID(encoding.Encoder encoder, ID id) {
  encoding.writeVarUint(encoder, id.client);
  encoding.writeVarUint(encoder, id.clock);
}

/**
 * Read ID.
 * * If first varUint read is 0xFFFFFF a RootID is returned.
 * * Otherwise an ID is returned
 *
 * @param {decoding.Decoder} decoder
 * @return {ID}
 *
 * @private
 * @function
 */
ID readID(decoding.Decoder decoder) =>
    createID(decoding.readVarUint(decoder), decoding.readVarUint(decoder));

/**
 * The top types are mapped from y.share.get(keyname) => type.
 * `type` does not store any information about the `keyname`.
 * This function finds the correct `keyname` for `type` and throws otherwise.
 *
 * @param {AbstractType<any>} type
 * @return {string}
 *
 * @private
 * @function
 */
String findRootTypeKey(AbstractType type) {
  // @ts-ignore _y must be defined, otherwise unexpected case
  for (final entrie in type.doc!.share.entries) {
    if (entrie.value == type) {
      return entrie.key;
    }
  }
  throw Exception('Unexpected case');
}
