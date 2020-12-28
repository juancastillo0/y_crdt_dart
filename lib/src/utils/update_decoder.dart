// import * as buffer from "lib0/buffer.js";
// import * as error from "lib0/error.js";
// import * as decoding from "lib0/decoding.js";
// import { ID, createID } from "../internals.js";

import 'dart:convert';
import 'dart:typed_data';

import 'package:y_crdt/src/lib0/decoding.dart';
import 'package:y_crdt/src/utils/id.dart';

import 'package:y_crdt/src/lib0/decoding.dart' as decoding;

abstract class AbstractDSDecoder {
  /**
   * @param {decoding.Decoder} decoder
   */
  AbstractDSDecoder(this.restDecoder) {
    UnimplementedError();
  }
  final decoding.Decoder restDecoder;

  resetDsCurVal() {}

  /**
   * @return {number}
   */
  int readDsClock();

  /**
   * @return {number}
   */
  int readDsLen();
}

abstract class AbstractUpdateDecoder extends AbstractDSDecoder {
  AbstractUpdateDecoder(Decoder decoder) : super(decoder);

  /**
   * @return {ID}
   */
  ID readLeftID();

  /**
   * @return {ID}
   */
  ID readRightID();

  /**
   * Read the next client id.
   * Use this in favor of readID whenever possible to reduce the number of objects created.
   *
   * @return {number}
   */
  int readClient();

  /**
   * @return {number} info An unsigned 8-bit integer
   */
  int readInfo();

  /**
   * @return {string}
   */
  String readString();

  /**
   * @return {boolean} isKey
   */
  bool readParentInfo();

  /**
   * @return {number} info An unsigned 8-bit integer
   */
  int readTypeRef();

  /**
   * Write len of a struct - well suited for Opt RLE encoder.
   *
   * @return {number} len
   */
  int readLen();

  /**
   * @return {any}
   */
  dynamic readAny();

  /**
   * @return {Uint8Array}
   */
  Uint8List readBuf();

  /**
   * Legacy implementation uses JSON parse. We use any-decoding in v2.
   *
   * @return {any}
   */
  dynamic readJSON();

  /**
   * @return {string}
   */
  String readKey();
}

class DSDecoderV1 implements AbstractDSDecoder {
  /**
   * @param {decoding.Decoder} decoder
   */
  DSDecoderV1(this.restDecoder);
  final decoding.Decoder restDecoder;
  static DSDecoderV1 create(decoding.Decoder decoder) => DSDecoderV1(decoder);

  resetDsCurVal() {
    // nop
  }

  /**
   * @return {number}
   */
  int readDsClock() {
    return decoding.readVarUint(this.restDecoder);
  }

  /**
   * @return {number}
   */
  int readDsLen() {
    return decoding.readVarUint(this.restDecoder);
  }
}

class UpdateDecoderV1 extends DSDecoderV1 implements AbstractUpdateDecoder {
  UpdateDecoderV1(Decoder decoder) : super(decoder);
  static UpdateDecoderV1 create(decoding.Decoder decoder) =>
      UpdateDecoderV1(decoder);

  /**
   * @return {ID}
   */
  ID readLeftID() {
    return createID(decoding.readVarUint(this.restDecoder),
        decoding.readVarUint(this.restDecoder));
  }

  /**
   * @return {ID}
   */
  ID readRightID() {
    return createID(decoding.readVarUint(this.restDecoder),
        decoding.readVarUint(this.restDecoder));
  }

  /**
   * Read the next client id.
   * Use this in favor of readID whenever possible to reduce the number of objects created.
   */
  int readClient() {
    return decoding.readVarUint(this.restDecoder);
  }

  /**
   * @return {number} info An unsigned 8-bit integer
   */
  int readInfo() {
    return decoding.readUint8(this.restDecoder);
  }

  /**
   * @return {string}
   */
  String readString() {
    return decoding.readVarString(this.restDecoder);
  }

  /**
   * @return {boolean} isKey
   */
  bool readParentInfo() {
    return decoding.readVarUint(this.restDecoder) == 1;
  }

  /**
   * @return {number} info An unsigned 8-bit integer
   */
  int readTypeRef() {
    return decoding.readVarUint(this.restDecoder);
  }

  /**
   * Write len of a struct - well suited for Opt RLE encoder.
   *
   * @return {number} len
   */
  int readLen() {
    return decoding.readVarUint(this.restDecoder);
  }

  /**
   * @return {any}
   */
  dynamic readAny() {
    return decoding.readAny(this.restDecoder);
  }

  /**
   * @return {Uint8Array}
   */
  Uint8List readBuf() {
    // TODO:
    return Uint8List.fromList(decoding.readVarUint8Array(this.restDecoder));
  }

  /**
   * Legacy implementation uses JSON parse. We use any-decoding in v2.
   *
   * @return {any}
   */
  dynamic readJSON() {
    return jsonDecode(decoding.readVarString(this.restDecoder));
  }

  /**
   * @return {string}
   */
  String readKey() {
    return decoding.readVarString(this.restDecoder);
  }
}

class DSDecoderV2 implements AbstractDSDecoder {
  /**
   * @param {decoding.Decoder} decoder
   */
  DSDecoderV2(this.restDecoder);
  int dsCurrVal = 0;
  final decoding.Decoder restDecoder;
  static DSDecoderV2 create(decoding.Decoder decoder) => DSDecoderV2(decoder);

  void resetDsCurVal() {
    this.dsCurrVal = 0;
  }

  int readDsClock() {
    this.dsCurrVal += decoding.readVarUint(this.restDecoder);
    return this.dsCurrVal;
  }

  int readDsLen() {
    final diff = decoding.readVarUint(this.restDecoder) + 1;
    this.dsCurrVal += diff;
    return diff;
  }
}

class UpdateDecoderV2 extends DSDecoderV2 implements AbstractUpdateDecoder {
  static UpdateDecoderV2 create(decoding.Decoder decoder) =>
      UpdateDecoderV2(decoder);
  /**
   * @param {decoding.Decoder} decoder
   */
  UpdateDecoderV2(Decoder decoder) : super(decoder) {
    decoding.readUint8(decoder); // read feature flag - currently unused
    this.keyClockDecoder =
        decoding.IntDiffOptRleDecoder(decoding.readVarUint8Array(decoder));
    this.clientDecoder =
        decoding.UintOptRleDecoder(decoding.readVarUint8Array(decoder));
    this.leftClockDecoder =
        decoding.IntDiffOptRleDecoder(decoding.readVarUint8Array(decoder));
    this.rightClockDecoder =
        decoding.IntDiffOptRleDecoder(decoding.readVarUint8Array(decoder));
    this.infoDecoder = decoding.RleDecoder(
        decoding.readVarUint8Array(decoder), decoding.readUint8);
    this.stringDecoder =
        decoding.StringDecoder(decoding.readVarUint8Array(decoder));
    this.parentInfoDecoder = decoding.RleDecoder(
        decoding.readVarUint8Array(decoder), decoding.readUint8);
    this.typeRefDecoder =
        decoding.UintOptRleDecoder(decoding.readVarUint8Array(decoder));
    this.lenDecoder =
        decoding.UintOptRleDecoder(decoding.readVarUint8Array(decoder));
  }
  /**
     * List of cached keys. If the keys[id] does not exist, we read a new key
     * from stringEncoder and push it to keys.
     *
     * @type {List<string>}
     */
  final keys = <String>[];
  late final IntDiffOptRleDecoder keyClockDecoder;
  late final UintOptRleDecoder clientDecoder;
  late final IntDiffOptRleDecoder leftClockDecoder;
  late final IntDiffOptRleDecoder rightClockDecoder;
  late final RleDecoder infoDecoder;
  late final StringDecoder stringDecoder;
  late final RleDecoder parentInfoDecoder;
  late final UintOptRleDecoder typeRefDecoder;
  late final UintOptRleDecoder lenDecoder;

  /**
   * @return {ID}
   */
  ID readLeftID() {
    return ID(this.clientDecoder.read(), this.leftClockDecoder.read());
  }

  /**
   * @return {ID}
   */
  ID readRightID() {
    return ID(this.clientDecoder.read(), this.rightClockDecoder.read());
  }

  /**
   * Read the next client id.
   * Use this in favor of readID whenever possible to reduce the number of objects created.
   */
  readClient() {
    return this.clientDecoder.read();
  }

  /**
   * @return {number} info An unsigned 8-bit integer
   */
  int readInfo() {
    return /** @type {number} */ (this.infoDecoder.read() as int);
  }

  /**
   * @return {string}
   */
  String readString() {
    return this.stringDecoder.read();
  }

  /**
   * @return {boolean}
   */
  bool readParentInfo() {
    return this.parentInfoDecoder.read() == 1;
  }

  /**
   * @return {number} An unsigned 8-bit integer
   */
  int readTypeRef() {
    return this.typeRefDecoder.read();
  }

  /**
   * Write len of a struct - well suited for Opt RLE encoder.
   *
   * @return {number}
   */
  int readLen() {
    return this.lenDecoder.read();
  }

  /**
   * @return {any}
   */
  dynamic readAny() {
    return decoding.readAny(this.restDecoder);
  }

  /**
   * @return {Uint8Array}
   */
  Uint8List readBuf() {
    return decoding.readVarUint8Array(this.restDecoder);
  }

  /**
   * This is mainly here for legacy purposes.
   *
   * Initial we incoded objects using JSON. Now we use the much faster lib0/any-encoder. This method mainly exists for legacy purposes for the v1 encoder.
   *
   * @return {any}
   */
  dynamic readJSON() {
    return decoding.readAny(this.restDecoder);
  }

  /**
   * @return {string}
   */
  String readKey() {
    final keyClock = this.keyClockDecoder.read();
    if (keyClock < this.keys.length) {
      return this.keys[keyClock];
    } else {
      final key = this.stringDecoder.read();
      this.keys.add(key);
      return key;
    }
  }
}
