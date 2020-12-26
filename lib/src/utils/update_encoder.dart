import 'dart:convert';
import 'dart:typed_data';

import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/lib0/encoding.dart' as encoding;
import 'package:y_crdt/src/y_crdt_base.dart';

// import * as error from "lib0/error.js";
// import * as encoding from "lib0/encoding.js";

// import {
//   ID, // eslint-disable-line
// } from "../internals.js";

abstract class AbstractDSEncoder {
  final restEncoder = encoding.createEncoder();

  /**
   * @return {Uint8Array}
   */
  Uint8List toUint8Array();

  /**
   * Resets the ds value to 0.
   * The v2 encoder uses this information to reset the initial diff value.
   */
  void resetDsCurVal() {}

  /**
   * @param {number} clock
   */
  void writeDsClock(int clock) {}

  /**
   * @param {number} len
   */
  void writeDsLen(int len) {}
}

abstract class AbstractUpdateEncoder extends AbstractDSEncoder {
  /**
   * @return {Uint8Array}
   */
  Uint8List toUint8Array();

  /**
   * @param {ID} id
   */
  void writeLeftID(ID id) {}

  /**
   * @param {ID} id
   */
  void writeRightID(ID id) {}

  /**
   * Use writeClient and writeClock instead of writeID if possible.
   * @param {number} client
   */
  void writeClient(int client) {}

  /**
   * @param {number} info An unsigned 8-bit integer
   */
  void writeInfo(int info) {}

  /**
   * @param {string} s
   */
  void writeString(String s) {}

  /**
   * @param {boolean} isYKey
   */
  void writeParentInfo(bool isYKey) {}

  /**
   * @param {number} info An unsigned 8-bit integer
   */
  void writeTypeRef(int info) {}

  /**
   * Write len of a struct - well suited for Opt RLE encoder.
   *
   * @param {number} len
   */
  void writeLen(int len) {}

  /**
   * @param {any} any
   */
  void writeAny(dynamic any) {}

  /**
   * @param {Uint8Array} buf
   */
  void writeBuf(Uint8List buf) {}

  /**
   * @param {any} embed
   */
  void writeJSON(dynamic embed) {}

  /**
   * @param {string} key
   */
  void writeKey(String key) {}
}

class DSEncoderV1 implements AbstractDSEncoder {
  final restEncoder = encoding.Encoder();

  static DSEncoderV1 create() => DSEncoderV1();

  @override
  Uint8List toUint8Array() {
    return encoding.toUint8Array(this.restEncoder);
  }

  @override
  void resetDsCurVal() {
    // nop
  }

  /**
   * @param {number} clock
   */
  @override
  void writeDsClock(int clock) {
    encoding.writeVarUint(this.restEncoder, clock);
  }

  /**
   * @param {number} len
   */
  @override
  void writeDsLen(int len) {
    encoding.writeVarUint(this.restEncoder, len);
  }
}

class UpdateEncoderV1 extends DSEncoderV1 implements AbstractUpdateEncoder {
  static UpdateEncoderV1 create() => UpdateEncoderV1();
  /**
   * @param {ID} id
   */
  void writeLeftID(id) {
    encoding.writeVarUint(this.restEncoder, id.client);
    encoding.writeVarUint(this.restEncoder, id.clock);
  }

  /**
   * @param {ID} id
   */
  void writeRightID(id) {
    encoding.writeVarUint(this.restEncoder, id.client);
    encoding.writeVarUint(this.restEncoder, id.clock);
  }

  /**
   * Use writeClient and writeClock instead of writeID if possible.
   * @param {number} client
   */
  void writeClient(client) {
    encoding.writeVarUint(this.restEncoder, client);
  }

  /**
   * @param {number} info An unsigned 8-bit integer
   */
  void writeInfo(info) {
    encoding.writeUint8(this.restEncoder, info);
  }

  /**
   * @param {string} s
   */
  void writeString(s) {
    encoding.writeVarString(this.restEncoder, s);
  }

  /**
   * @param {boolean} isYKey
   */
  void writeParentInfo(isYKey) {
    encoding.writeVarUint(this.restEncoder, isYKey ? 1 : 0);
  }

  /**
   * @param {number} info An unsigned 8-bit integer
   */
  void writeTypeRef(info) {
    encoding.writeVarUint(this.restEncoder, info);
  }

  /**
   * Write len of a struct - well suited for Opt RLE encoder.
   *
   * @param {number} len
   */
  void writeLen(len) {
    encoding.writeVarUint(this.restEncoder, len);
  }

  /**
   * @param {any} any
   */
  void writeAny(any) {
    encoding.writeAny(this.restEncoder, any);
  }

  /**
   * @param {Uint8Array} buf
   */
  void writeBuf(buf) {
    encoding.writeVarUint8Array(this.restEncoder, buf);
  }

  /**
   * @param {any} embed
   */
  void writeJSON(embed) {
    encoding.writeVarString(this.restEncoder, jsonEncode(embed));
  }

  /**
   * @param {string} key
   */
  void writeKey(key) {
    encoding.writeVarString(this.restEncoder, key);
  }
}

class DSEncoderV2 implements AbstractDSEncoder {
  static DSEncoderV2 create() => DSEncoderV2();
  // encodes all the rest / non-optimized
  final restEncoder = new encoding.Encoder();
  int dsCurrVal = 0;

  Uint8List toUint8Array() {
    return encoding.toUint8Array(this.restEncoder);
  }

  void resetDsCurVal() {
    this.dsCurrVal = 0;
  }

  /**
   * @param {number} clock
   */
  void writeDsClock(int clock) {
    final diff = clock - this.dsCurrVal;
    this.dsCurrVal = clock;
    encoding.writeVarUint(this.restEncoder, diff);
  }

  /**
   * @param {number} len
   */
  @override
  void writeDsLen(int len) {
    if (len == 0) {
      ArgumentError.value(len, "len", "must be different than 0");
    }
    encoding.writeVarUint(this.restEncoder, len - 1);
    this.dsCurrVal += len;
  }
}

class UpdateEncoderV2 extends DSEncoderV2 implements AbstractUpdateEncoder {
  static UpdateEncoderV2 create() => UpdateEncoderV2();

  /**
     * @type {Map<string,number>}
     */
  final keyMap = <String, int>{};
  /**
     * Refers to the next uniqe key-identifier to me used.
     * See writeKey method for more information.
     *
     * @type {number}
     */
  int keyClock = 0;
  final keyClockEncoder = encoding.IntDiffOptRleEncoder();
  final clientEncoder = encoding.UintOptRleEncoder();
  final leftClockEncoder = encoding.IntDiffOptRleEncoder();
  final rightClockEncoder = encoding.IntDiffOptRleEncoder();
  final infoEncoder = encoding.RleEncoder(encoding.writeUint8);
  final stringEncoder = encoding.StringEncoder();
  final parentInfoEncoder = encoding.RleEncoder(encoding.writeUint8);
  final typeRefEncoder = encoding.UintOptRleEncoder();
  final lenEncoder = encoding.UintOptRleEncoder();

  @override
  Uint8List toUint8Array() {
    final encoder = encoding.createEncoder();
    encoding.writeUint8(
        encoder, 0); // this is a feature flag that we might use in the future
    encoding.writeVarUint8Array(encoder, this.keyClockEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, this.clientEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, this.leftClockEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, this.rightClockEncoder.toUint8Array());
    encoding.writeVarUint8Array(
        encoder, encoding.toUint8Array(this.infoEncoder));
    encoding.writeVarUint8Array(encoder, this.stringEncoder.toUint8Array());
    encoding.writeVarUint8Array(
        encoder, encoding.toUint8Array(this.parentInfoEncoder));
    encoding.writeVarUint8Array(encoder, this.typeRefEncoder.toUint8Array());
    encoding.writeVarUint8Array(encoder, this.lenEncoder.toUint8Array());
    // @note The rest encoder is appended! (note the missing var)
    encoding.writeUint8Array(encoder, encoding.toUint8Array(this.restEncoder));
    return encoding.toUint8Array(encoder);
  }

  /**
   * @param {ID} id
   */
  void writeLeftID(ID id) {
    this.clientEncoder.write(id.client);
    this.leftClockEncoder.write(id.clock);
  }

  /**
   * @param {ID} id
   */
  void writeRightID(ID id) {
    this.clientEncoder.write(id.client);
    this.rightClockEncoder.write(id.clock);
  }

  /**
   * @param {number} client
   */
  void writeClient(int client) {
    this.clientEncoder.write(client);
  }

  /**
   * @param {number} info An unsigned 8-bit integer
   */
  void writeInfo(int info) {
    this.infoEncoder.write(info);
  }

  /**
   * @param {string} s
   */
  void writeString(String s) {
    this.stringEncoder.write(s);
  }

  /**
   * @param {boolean} isYKey
   */
  void writeParentInfo(isYKey) {
    this.parentInfoEncoder.write(isYKey ? 1 : 0);
  }

  /**
   * @param {number} info An unsigned 8-bit integer
   */
  void writeTypeRef(int info) {
    this.typeRefEncoder.write(info);
  }

  /**
   * Write len of a struct - well suited for Opt RLE encoder.
   *
   * @param {number} len
   */
  void writeLen(int len) {
    this.lenEncoder.write(len);
  }

  /**
   * @param {any} any
   */
  void writeAny(dynamic any) {
    encoding.writeAny(this.restEncoder, any);
  }

  /**
   * @param {Uint8Array} buf
   */
  void writeBuf(Uint8List buf) {
    encoding.writeVarUint8Array(this.restEncoder, buf);
  }

  /**
   * This is mainly here for legacy purposes.
   *
   * Initial we incoded objects using JSON. Now we use the much faster lib0/any-encoder. This method mainly exists for legacy purposes for the v1 encoder.
   *
   * @param {any} embed
   */
  void writeJSON(dynamic embed) {
    encoding.writeAny(this.restEncoder, embed);
  }

  /**
   * Property keys are often reused. For example, in y-prosemirror the key `bold` might
   * occur very often. For a 3d application, the key `position` might occur very often.
   *
   * We cache these keys in a Map and refer to them via a unique number.
   *
   * @param {string} key
   */
  void writeKey(String key) {
    final clock = this.keyMap.get(key);
    if (clock == null) {
      this.keyClockEncoder.write(this.keyClock++);
      this.stringEncoder.write(key);
    } else {
      this.keyClockEncoder.write(this.keyClock++);
    }
  }
}
