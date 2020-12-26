/**
 * Efficient schema-less binary decoding with support for variable length encoding.
 *
 * Use [lib0/decoding] with [lib0/encoding]. Every encoding function has a corresponding decoding function.
 *
 * Encodes numbers in little-endian order (least to most significant byte order)
 * and is compatible with Golang's binary encoding (https://golang.org/pkg/encoding/binary/)
 * which is also used in Protocol Buffers.
 *
 * ```js
 * // encoding step
 * const encoder = new encoding.createEncoder()
 * encoding.writeVarUint(encoder, 256)
 * encoding.writeVarString(encoder, 'Hello world!')
 * const buf = encoding.toUint8List(encoder)
 * ```
 *
 * ```js
 * // decoding step
 * const decoder = new decoding.createDecoder(buf)
 * decoding.readVarUint(decoder) // => 256
 * decoding.readVarString(decoder) // => 'Hello world!'
 * decoding.hasContent(decoder) // => false - all data is read
 * ```
 *
 * @module decoding
 */

// import * as buffer from './buffer.js'
// import * as binary from './binary.js'
// import * as math from './math.js'

import 'dart:typed_data';
import 'binary.dart' as binary;
import 'package:fixnum/fixnum.dart' show Int64;

bool isNegativeZero(num n) => n != 0 ? n < 0 : 1 / n < 0;

int rightShift(int n, int shift) => Int64(n).shiftRightUnsigned(shift).toInt();

/**
 * A Decoder handles the decoding of an Uint8List.
 */
class Decoder {
  /**
   * @param {Uint8List} Uint8List Binary data to decode
   */
  Decoder(this.arr);
  /**
     * Decoding target.
     *
     * @type {Uint8List}
     */
  final Uint8List arr;
  /**
     * Current decoding position.
     *
     * @type {number}
     */
  int pos = 0;
}

/**
 * @function
 * @param {Uint8List} Uint8List
 * @return {Decoder}
 */
Decoder createDecoder(Uint8List arr) => Decoder(arr);

/**
 * @function
 * @param {Decoder} decoder
 * @return {boolean}
 */
bool hasContent(Decoder decoder) => decoder.pos != decoder.arr.length;

/**
 * Clone a decoder instance.
 * Optionally set a new position parameter.
 *
 * @function
 * @param {Decoder} decoder The decoder instance
 * @param {number} [newPos] Defaults to current position
 * @return {Decoder} A clone of `decoder`
 */
Decoder clone(Decoder decoder, [int? newPos]) {
  final _decoder = createDecoder(decoder.arr);
  if (newPos != null) {
    _decoder.pos = newPos;
  }
  return _decoder;
}

/**
 * Create an Uint8List view of the next `len` bytes and advance the position by `len`.
 *
 * Important: The Uint8List still points to the underlying ArrayBuffer. Make sure to discard the result as soon as possible to prevent any memory leaks.
 *            Use `buffer.copyUint8List` to copy the result into a new Uint8List.
 *
 * @function
 * @param {Decoder} decoder The decoder instance
 * @param {number} len The length of bytes to read
 * @return {Uint8List}
 */
Uint8List readUint8Array(Decoder decoder, int len) {
  final view = Uint8List.view(
      decoder.arr.buffer, decoder.pos + decoder.arr.offsetInBytes, len);
  decoder.pos += len;
  return view;
}

/**
 * Read variable length Uint8List.
 *
 * Important: The Uint8List still points to the underlying ArrayBuffer. Make sure to discard the result as soon as possible to prevent any memory leaks.
 *            Use `buffer.copyUint8List` to copy the result into a new Uint8List.
 *
 * @function
 * @param {Decoder} decoder
 * @return {Uint8List}
 */
Uint8List readVarUint8Array(Decoder decoder) =>
    readUint8Array(decoder, readVarUint(decoder));

/**
 * Read the rest of the content as an ArrayBuffer
 * @function
 * @param {Decoder} decoder
 * @return {Uint8List}
 */
Uint8List readTailAsUint8Array(Decoder decoder) =>
    readUint8Array(decoder, decoder.arr.length - decoder.pos);

/**
 * Skip one byte, jump to the next position.
 * @function
 * @param {Decoder} decoder The decoder instance
 * @return {number} The next position
 */
int skip8(Decoder decoder) => decoder.pos++;

/**
 * Read one byte as unsigned integer.
 * @function
 * @param {Decoder} decoder The decoder instance
 * @return {number} Unsigned 8-bit integer
 */
int readUint8(Decoder decoder) => decoder.arr[decoder.pos++];

/**
 * Read 2 bytes as unsigned integer.
 *
 * @function
 * @param {Decoder} decoder
 * @return {number} An unsigned integer.
 */
int readUint16(Decoder decoder) {
  final uint = decoder.arr[decoder.pos] + (decoder.arr[decoder.pos + 1] << 8);
  decoder.pos += 2;
  return uint;
}

/**
 * Read 4 bytes as unsigned integer.
 *
 * @function
 * @param {Decoder} decoder
 * @return {number} An unsigned integer.
 */
int readUint32(Decoder decoder) {
  final uint = rightShift(
      (decoder.arr[decoder.pos] +
          (decoder.arr[decoder.pos + 1] << 8) +
          (decoder.arr[decoder.pos + 2] << 16) +
          (decoder.arr[decoder.pos + 3] << 24)),
      0);
  decoder.pos += 4;
  return uint;
}

/**
 * Read 4 bytes as unsigned integer in big endian order.
 * (most significant byte first)
 *
 * @function
 * @param {Decoder} decoder
 * @return {number} An unsigned integer.
 */
int readUint32BigEndian(Decoder decoder) {
  final uint = rightShift(
      (decoder.arr[decoder.pos + 3] +
          (decoder.arr[decoder.pos + 2] << 8) +
          (decoder.arr[decoder.pos + 1] << 16) +
          (decoder.arr[decoder.pos] << 24)),
      0);
  decoder.pos += 4;
  return uint;
}

/**
 * Look ahead without incrementing position.
 * to the next byte and read it as unsigned integer.
 *
 * @function
 * @param {Decoder} decoder
 * @return {number} An unsigned integer.
 */
int peekUint8(Decoder decoder) => decoder.arr[decoder.pos];

/**
 * Look ahead without incrementing position.
 * to the next byte and read it as unsigned integer.
 *
 * @function
 * @param {Decoder} decoder
 * @return {number} An unsigned integer.
 */
int peekUint16(Decoder decoder) =>
    decoder.arr[decoder.pos] + (decoder.arr[decoder.pos + 1] << 8);

/**
 * Look ahead without incrementing position.
 * to the next byte and read it as unsigned integer.
 *
 * @function
 * @param {Decoder} decoder
 * @return {number} An unsigned integer.
 */
int peekUint32(Decoder decoder) => rightShift(
    (decoder.arr[decoder.pos] +
        (decoder.arr[decoder.pos + 1] << 8) +
        (decoder.arr[decoder.pos + 2] << 16) +
        (decoder.arr[decoder.pos + 3] << 24)),
    0);

/**
 * Read unsigned integer (32bit) with variable length.
 * 1/8th of the storage is used as encoding overhead.
 *  * numbers < 2^7 is stored in one bytlength
 *  * numbers < 2^14 is stored in two bylength
 *
 * @function
 * @param {Decoder} decoder
 * @return {number} An unsigned integer.length
 */
int readVarUint(Decoder decoder) {
  var number = 0;
  var len = 0;
  while (true) {
    final r = decoder.arr[decoder.pos++];
    number = number | ((r & binary.BITS7) << len);
    len += 7;
    if (r < binary.BIT8) {
      return rightShift(number, 0); // return unsigned number!
    }
    /* istanbul ignore if */
    if (len > 35) {
      throw Exception('Integer out of range!');
    }
  }
}

/**
 * Read signed integer (32bit) with variable length.
 * 1/8th of the storage is used as encoding overhead.
 *  * numbers < 2^7 is stored in one bytlength
 *  * numbers < 2^14 is stored in two bylength
 * @todo This should probably create the inverse ~num if unmber is negative - but this would be a breaking change.
 *
 * @function
 * @param {Decoder} decoder
 * @return {number} An unsigned integer.length
 */
int readVarInt(Decoder decoder) {
  var r = decoder.arr[decoder.pos++];
  var number = r & binary.BITS6;
  var len = 6;
  final sign = (r & binary.BIT7) > 0 ? -1 : 1;
  if ((r & binary.BIT8) == 0) {
    // don't continue reading
    return sign * number;
  }
  while (true) {
    r = decoder.arr[decoder.pos++];
    number = number | ((r & binary.BITS7) << len);
    len += 7;
    if (r < binary.BIT8) {
      return sign * rightShift(number, 0);
    }
    /* istanbul ignore if */
    if (len > 41) {
      throw Exception('Integer out of range!');
    }
  }
}

/**
 * Look ahead and read varUint without incrementing position
 *
 * @function
 * @param {Decoder} decoder
 * @return {number}
 */
int peekVarUint(Decoder decoder) {
  final pos = decoder.pos;
  final s = readVarUint(decoder);
  decoder.pos = pos;
  return s;
}

/**
 * Look ahead and read varUint without incrementing position
 *
 * @function
 * @param {Decoder} decoder
 * @return {number}
 */
int peekVarInt(Decoder decoder) {
  final pos = decoder.pos;
  final s = readVarInt(decoder);
  decoder.pos = pos;
  return s;
}

/**
 * Read string of variable length
 * * varUint is used to store the length of the string
 *
 * Transforming utf8 to a string is pretty expensive. The code performs 10x better
 * when String.fromCodePoint is fed with all characters as arguments.
 * But most environments have a maximum number of arguments per functions.
 * For effiency reasons we apply a maximum of 10000 characters at once.
 *
 * @function
 * @param {Decoder} decoder
 * @return {String} The read String.
 */
String readVarString(Decoder decoder) {
  var remainingLen = readVarUint(decoder);
  if (remainingLen == 0) {
    return '';
  } else {
    var encodedString = String.fromCharCode(
        readUint8(decoder)); // remember to decrease remainingLen
    if (--remainingLen < 100) {
      // do not create a Uint8List for small strings
      while (remainingLen-- != 0) {
        encodedString += String.fromCharCode(readUint8(decoder));
      }
    } else {
      while (remainingLen > 0) {
        final nextLen = remainingLen < 10000 ? remainingLen : 10000;
        // this is dangerous, we create a fresh array view from the existing buffer
        final bytes = decoder.arr.sublist(decoder.pos, decoder.pos + nextLen);
        decoder.pos += nextLen;
        // Starting with ES5.1 we can supply a generic array-like object as arguments
        encodedString += String.fromCharCodes(/** @type {any} */ (bytes));
        remainingLen -= nextLen;
      }
    }
    // TODO:
    // return decodeURIComponent(escape(encodedString));
    return Uri.decodeComponent(encodedString);
  }
}

/**
 * Look ahead and read varString without incrementing position
 *
 * @function
 * @param {Decoder} decoder
 * @return {string}
 */
String peekVarString(Decoder decoder) {
  final pos = decoder.pos;
  final s = readVarString(decoder);
  decoder.pos = pos;
  return s;
}

/**
 * @param {Decoder} decoder
 * @param {number} len
 * @return {DataView}
 */
ByteData readFromDataView(Decoder decoder, int len) {
  final dv = ByteData.view(
      decoder.arr.buffer, decoder.arr.offsetInBytes + decoder.pos, len);
  decoder.pos += len;
  return dv;
}

/**
 * @param {Decoder} decoder
 */
double readFloat32(Decoder decoder) =>
    readFromDataView(decoder, 4).getFloat32(0);

/**
 * @param {Decoder} decoder
 */
double readFloat64(Decoder decoder) =>
    readFromDataView(decoder, 8).getFloat64(0);

/**
 * @param {Decoder} decoder
 */
int readBigInt64(Decoder decoder) => /** @type {any} */ (readFromDataView(
        decoder, 8))
    .getInt64(0);

/**
 * @param {Decoder} decoder
 */
int readBigUint64(Decoder decoder) => /** @type {any} */ (readFromDataView(
        decoder, 8))
    .getUint64(0);

/**
 * @type {Array<function(Decoder):any>}
 */
final readAnyLookupTable = [
  // TODO: undefined as null
  (decoder) => null, // CASE 127: undefined
  (decoder) => null, // CASE 126: null
  readVarInt, // CASE 125: integer
  readFloat32, // CASE 124: float32
  readFloat64, // CASE 123: float64
  readBigInt64, // CASE 122: bigint
  (decoder) => false, // CASE 121: boolean (false)
  (decoder) => true, // CASE 120: boolean (true)
  readVarString, // CASE 119: string
  (decoder) {
    // CASE 118: object<string,any>
    final len = readVarUint(decoder);
    /**
     * @type {Object<string,any>}
     */
    final obj = {};
    for (var i = 0; i < len; i++) {
      final key = readVarString(decoder);
      obj[key] = readAny(decoder);
    }
    return obj;
  },
  (decoder) {
    // CASE 117: array<any>
    final len = readVarUint(decoder);
    final arr = [];
    for (var i = 0; i < len; i++) {
      arr.add(readAny(decoder));
    }
    return arr;
  },
  readVarUint8Array // CASE 116: Uint8List
];

/**
 * @param {Decoder} decoder
 */
dynamic readAny(Decoder decoder) =>
    readAnyLookupTable[127 - readUint8(decoder)](decoder);

/**
 * T must not be null.
 *
 * @template T
 */
class RleDecoder<T extends Object> extends Decoder {
  /**
   * @param {Uint8List} Uint8List
   * @param {function(Decoder):T} reader
   */
  RleDecoder(Uint8List arr, this.reader) : super(arr);

  /**
     * The reader
     */
  final T Function(Decoder) reader;
  /**
     * Current state
     * @type {T|null}
     */
  T? s;
  int count = 0;

  T? read() {
    if (this.count == 0) {
      this.s = this.reader(this);
      if (hasContent(this)) {
        this.count = readVarUint(this) +
            1; // see encoder implementation for the reason why this is incremented
      } else {
        this.count = -1; // read the current value forever
      }
    }
    this.count--;
    return /** @type {T} */ (this.s);
  }
}

class IntDiffDecoder extends Decoder {
  /**
   * @param {Uint8List} Uint8List
   * @param {number} start
   */
  IntDiffDecoder(Uint8List arr, this.s) : super(arr);
  /**
     * Current state
     * @type {number}
     */
  int s;

  /**
   * @return {number}
   */
  int read() {
    this.s += readVarInt(this);
    return this.s;
  }
}

class RleIntDiffDecoder extends Decoder {
  /**
   * @param {Uint8List} Uint8List
   * @param {number} start
   */
  RleIntDiffDecoder(Uint8List arr, this.s) : super(arr);
  /**
     * Current state
     * @type {number}
     */
  int s;
  int count = 0;

  /**
   * @return {number}
   */
  int read() {
    if (this.count == 0) {
      this.s += readVarInt(this);
      if (hasContent(this)) {
        this.count = readVarUint(this) +
            1; // see encoder implementation for the reason why this is incremented
      } else {
        this.count = -1; // read the current value forever
      }
    }
    this.count--;
    return /** @type {number} */ (this.s);
  }
}

class UintOptRleDecoder extends Decoder {
  /**
   * @param {Uint8List} Uint8List
   */
  UintOptRleDecoder(Uint8List arr) : super(arr);
  /**
     * @type {number}
     */
  int s = 0;
  int count = 0;

  int read() {
    if (this.count == 0) {
      this.s = readVarInt(this);
      // if the sign is negative, we read the count too, otherwise count is 1
      final isNegative = isNegativeZero(this.s);
      this.count = 1;
      if (isNegative) {
        this.s = -this.s;
        this.count = readVarUint(this) + 2;
      }
    }
    this.count--;
    return /** @type {number} */ (this.s);
  }
}

class IncUintOptRleDecoder extends Decoder {
  /**
   * @param {Uint8List} Uint8List
   */
  IncUintOptRleDecoder(Uint8List arr) : super(arr);
  /**
     * @type {number}
     */
  int s = 0;
  int count = 0;

  int read() {
    if (this.count == 0) {
      this.s = readVarInt(this);
      // if the sign is negative, we read the count too, otherwise count is 1
      final isNegative = isNegativeZero(this.s);
      this.count = 1;
      if (isNegative) {
        this.s = -this.s;
        this.count = readVarUint(this) + 2;
      }
    }
    this.count--;
    return /** @type {number} */ (this.s++);
  }
}

class IntDiffOptRleDecoder extends Decoder {
  /**
   * @param {Uint8List} Uint8List
   */
  IntDiffOptRleDecoder(Uint8List arr) : super(arr);
  /**
     * @type {number}
     */
  int s = 0;
  int count = 0;
  int diff = 0;

  /**
   * @return {number}
   */
  int read() {
    if (this.count == 0) {
      final diff = readVarInt(this);
      // if the first bit is set, we read more data
      final hasCount = diff & 1;
      this.diff = diff >> 1;
      this.count = 1;
      if (hasCount != 0) {
        this.count = readVarUint(this) + 2;
      }
    }
    this.s += this.diff;
    this.count--;
    return this.s;
  }
}

class StringDecoder {
  /**
   * @param {Uint8List} Uint8List
   */
  StringDecoder(Uint8List arr) {
    this.decoder = UintOptRleDecoder(arr);
    this.str = readVarString(this.decoder);
  }
  late final UintOptRleDecoder decoder;
  /**
     * @type {number}
     */
  int spos = 0;
  late final String str;

  /**
   * @return {string}
   */
  String read() {
    final end = this.spos + this.decoder.read();
    final res = this.str.substring(this.spos, end);
    this.spos = end;
    return res;
  }
}
