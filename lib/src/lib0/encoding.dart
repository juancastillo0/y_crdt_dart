/**
 * Efficient schema-less binary encoding with support for variable length encoding.
 *
 * Use [lib0/encoding] with [lib0/decoding]. Every encoding function has a corresponding decoding function.
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
 * const buf = encoding.toUint8Array(encoder)
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
 * @module encoding
 */

// import * as buffer from './buffer.js'
// import * as math from './math.js'
// import * as number from './number.js'
// import * as binary from './binary.js'

import 'dart:typed_data';
import 'dart:math' as math;
import 'binary.dart' as binary;
import 'decoding.dart' show isNegativeZero, rightShift;

/**
 * A BinaryEncoder handles the encoding to an Uint8Array.
 */
class Encoder {
  Encoder();
  int cpos = 0;
  Uint8List cbuf = Uint8List(100);
  /**
     * @type {Array<Uint8Array>}
     */
  final List<Uint8List> bufs = [];
}

/**
 * @function
 * @return {Encoder}
 */
Encoder createEncoder() => Encoder();

/**
 * The current length of the encoded data.
 *
 * @function
 * @param {Encoder} encoder
 * @return {number}
 */
int length(Encoder encoder) {
  var len = encoder.cpos;
  for (var i = 0; i < encoder.bufs.length; i++) {
    len += encoder.bufs[i].length;
  }
  return len;
}

/**
 * Transform to Uint8Array.
 *
 * @function
 * @param {Encoder} encoder
 * @return {Uint8Array} The created ArrayBuffer.
 */
Uint8List _toUint8Array(Encoder encoder) {
  final uint8arr = Uint8List(length(encoder));
  var curPos = 0;
  for (var i = 0; i < encoder.bufs.length; i++) {
    final d = encoder.bufs[i];
    uint8arr.setAll(curPos, d);
    curPos += d.length;
  }
  uint8arr.setAll(
    curPos,
    Uint8List.view(encoder.cbuf.buffer, 0, encoder.cpos),
  );
  return uint8arr;
}

const toUint8Array = _toUint8Array;

/**
 * Verify that it is possible to write `len` bytes wtihout checking. If
 * necessary, a new Buffer with the required length is attached.
 *
 * @param {Encoder} encoder
 * @param {number} len
 */
void verifyLen(Encoder encoder, int len) {
  final bufferLen = encoder.cbuf.length;
  if (bufferLen - encoder.cpos < len) {
    encoder.bufs.add(Uint8List.view(encoder.cbuf.buffer, 0, encoder.cpos));
    encoder.cbuf = Uint8List(math.max(bufferLen, len) * 2);
    encoder.cpos = 0;
  }
}

/**
 * Write one byte to the encoder.
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} num The byte that is to be encoded.
 */
void write(Encoder encoder, int number) {
  final bufferLen = encoder.cbuf.length;
  if (encoder.cpos == bufferLen) {
    encoder.bufs.add(encoder.cbuf);
    encoder.cbuf = Uint8List(bufferLen * 2);
    encoder.cpos = 0;
  }
  encoder.cbuf[encoder.cpos++] = number;
}

/**
 * Write one byte at a specific position.
 * Position must already be written (i.e. encoder.length > pos)
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} pos Position to which to write data
 * @param {number} num Unsigned 8-bit integer
 */
void set(Encoder encoder, int pos, int number) {
  Uint8List? buffer;
  // iterate all buffers and adjust position
  for (var i = 0; i < encoder.bufs.length && buffer == null; i++) {
    final b = encoder.bufs[i];
    if (pos < b.length) {
      buffer = b; // found buffer
    } else {
      pos -= b.length;
    }
  }
  if (buffer == null) {
    // use current buffer
    buffer = encoder.cbuf;
  }
  buffer[pos] = number;
}

/**
 * Write one byte as an unsigned integer.
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} num The number that is to be encoded.
 */
const writeUint8 = write;

/**
 * Write one byte as an unsigned Integer at a specific location.
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} pos The location where the data will be written.
 * @param {number} num The number that is to be encoded.
 */
const setUint8 = set;

/**
 * Write two bytes as an unsigned integer.
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} num The number that is to be encoded.
 */
void writeUint16(Encoder encoder, int number) {
  write(encoder, number & binary.BITS8);
  write(encoder, rightShift(number, 8) & binary.BITS8);
}

/**
 * Write two bytes as an unsigned integer at a specific location.
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} pos The location where the data will be written.
 * @param {number} num The number that is to be encoded.
 */
void setUint16(Encoder encoder, int pos, int number) {
  set(encoder, pos, number & binary.BITS8);
  set(encoder, pos + 1, rightShift(number, 8) & binary.BITS8);
}

/**
 * Write two bytes as an unsigned integer
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} num The number that is to be encoded.
 */
void writeUint32(Encoder encoder, int number) {
  for (var i = 0; i < 4; i++) {
    write(encoder, number & binary.BITS8);
    number = rightShift(number, 8);
  }
}

/**
 * Write two bytes as an unsigned integer in big endian order.
 * (most significant byte first)
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} num The number that is to be encoded.
 */
void writeUint32BigEndian(Encoder encoder, int number) {
  for (var i = 3; i >= 0; i--) {
    write(encoder, rightShift(number, (8 * i)) & binary.BITS8);
  }
}

/**
 * Write two bytes as an unsigned integer at a specific location.
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} pos The location where the data will be written.
 * @param {number} num The number that is to be encoded.
 */
void setUint32(Encoder encoder, int pos, int number) {
  for (var i = 0; i < 4; i++) {
    set(encoder, pos + i, number & binary.BITS8);
    number = rightShift(number, 8);
  }
}

/**
 * Write a variable length unsigned integer.
 *
 * Encodes integers in the range from [0, 4294967295] / [0, 0xffffffff]. (max 32 bit unsigned integer)
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} num The number that is to be encoded.
 */
void writeVarUint(Encoder encoder, int number) {
  while (number > binary.BITS7) {
    write(encoder, binary.BIT8 | (binary.BITS7 & number));
    number = rightShift(number, 7);
  }
  write(encoder, binary.BITS7 & number);
}

/**
 * Write a variable length integer.
 *
 * Encodes integers in the range from [-2147483648, -2147483647].
 *
 * We don't use zig-zag encoding because we want to keep the option open
 * to use the same function for BigInt and 53bit integers (doubles).
 *
 * We use the 7th bit instead for signaling that this is a negative number.
 *
 * @function
 * @param {Encoder} encoder
 * @param {number} num The number that is to be encoded.
 */
void writeVarInt(Encoder encoder, int number) {
  final isNegative = isNegativeZero(number);
  if (isNegative) {
    number = -number;
  }
  //             |- whether to continue reading         |- whether is negative     |- number
  write(
      encoder,
      (number > binary.BITS6 ? binary.BIT8 : 0) |
          (isNegative ? binary.BIT7 : 0) |
          (binary.BITS6 & number));
  number = rightShift(number, 6);
  // We don't need to consider the case of num === 0 so we can use a different
  // pattern here than above.
  while (number > 0) {
    write(encoder,
        (number > binary.BITS7 ? binary.BIT8 : 0) | (binary.BITS7 & number));
    number = rightShift(number, 7);
  }
}

/**
 * Write a variable length string.
 *
 * @function
 * @param {Encoder} encoder
 * @param {String} str The string that is to be encoded.
 */
void writeVarString(Encoder encoder, String str) {
  // TODO:
  // final encodedString = unescape(encodeURIComponent(str));
  final encodedString = Uri.encodeComponent(str);
  final len = encodedString.length;
  writeVarUint(encoder, len);
  for (var i = 0; i < len; i++) {
    write(encoder, /** @type {number} */ (encodedString.codeUnitAt(i)));
  }
}

/**
 * Write the content of another Encoder.
 *
 * @TODO: can be improved!
 *        - Note: Should consider that when appending a lot of small Encoders, we should rather clone than referencing the old structure.
 *                Encoders start with a rather big initial buffer.
 *
 * @function
 * @param {Encoder} encoder The enUint8Arr
 * @param {Encoder} append The BinaryEncoder to be written.
 */
void writeBinaryEncoder(Encoder encoder, Encoder append) =>
    writeUint8Array(encoder, _toUint8Array(append));

/**
 * Append fixed-length Uint8Array to the encoder.
 *
 * @function
 * @param {Encoder} encoder
 * @param {Uint8Array} uint8Array
 */
void writeUint8Array(Encoder encoder, Uint8List uint8Array) {
  final bufferLen = encoder.cbuf.length;
  final cpos = encoder.cpos;
  final leftCopyLen = math.min(bufferLen - cpos, uint8Array.length);
  final rightCopyLen = uint8Array.length - leftCopyLen;
  encoder.cbuf.setAll(cpos, uint8Array.sublist(0, leftCopyLen));
  encoder.cpos += leftCopyLen;
  if (rightCopyLen > 0) {
    // Still something to write, write right half..
    // Append new buffer
    encoder.bufs.add(encoder.cbuf);
    // must have at least size of remaining buffer
    encoder.cbuf = Uint8List(math.max(bufferLen * 2, rightCopyLen));
    // copy array
    encoder.cbuf.setAll(0, uint8Array.sublist(leftCopyLen));
    encoder.cpos = rightCopyLen;
  }
}

/**
 * Append an Uint8Array to Encoder.
 *
 * @function
 * @param {Encoder} encoder
 * @param {Uint8Array} uint8Array
 */
void writeVarUint8Array(Encoder encoder, Uint8List uint8Array) {
  writeVarUint(encoder, uint8Array.lengthInBytes);
  writeUint8Array(encoder, uint8Array);
}

/**
 * Create an DataView of the next `len` bytes. Use it to write data after
 * calling this function.
 *
 * ```js
 * // write float32 using DataView
 * const dv = writeOnDataView(encoder, 4)
 * dv.setFloat32(0, 1.1)
 * // read float32 using DataView
 * const dv = readFromDataView(encoder, 4)
 * dv.getFloat32(0) // => 1.100000023841858 (leaving it to the reader to find out why this is the correct result)
 * ```
 *
 * @param {Encoder} encoder
 * @param {number} len
 * @return {DataView}
 */
ByteData writeOnDataView(Encoder encoder, int len) {
  verifyLen(encoder, len);
  final dview = ByteData.view(encoder.cbuf.buffer, encoder.cpos, len);
  encoder.cpos += len;
  return dview;
}

/**
 * @param {Encoder} encoder
 * @param {number} num
 */
void writeFloat32(Encoder encoder, double number) =>
    writeOnDataView(encoder, 4).setFloat32(0, number);

/**
 * @param {Encoder} encoder
 * @param {number} num
 */
void writeFloat64(Encoder encoder, double number) =>
    writeOnDataView(encoder, 8).setFloat64(0, number);

/**
 * @param {Encoder} encoder
 * @param {bigint} num
 */
void writeBigInt64(
    Encoder encoder, BigInt number) => /** @type {any} */ (writeOnDataView(
        encoder, 8))
    .setInt64(0, number.toInt());

/**
 * @param {Encoder} encoder
 * @param {bigint} num
 */
void writeBigUint64(
    Encoder encoder, BigInt number) => /** @type {any} */ (writeOnDataView(
        encoder, 8))
    .setUint64(0, number.toInt());

final floatTestBed = ByteData(4);
/**
 * Check if a number can be encoded as a 32 bit float.
 *
 * @param {number} num
 * @return {boolean}
 */
bool isFloat32(double number) {
  floatTestBed.setFloat32(0, number);
  return floatTestBed.getFloat32(0) == number;
}

/**
 * Encode data with efficient binary format.
 *
 * Differences to JSON:
 * • Transforms data to a binary format (not to a string)
 * • Encodes undefined, NaN, and ArrayBuffer (these can't be represented in JSON)
 * • Numbers are efficiently encoded either as a variable length integer, as a
 *   32 bit float, as a 64 bit float, or as a 64 bit bigint.
 *
 * Encoding table:
 *
 * | Data Type           | Prefix   | Encoding Method    | Comment |
 * | ------------------- | -------- | ------------------ | ------- |
 * | undefined           | 127      |                    | Functions, symbol, and everything that cannot be identified is encoded as undefined |
 * | null                | 126      |                    | |
 * | integer             | 125      | writeVarInt        | Only encodes 32 bit signed integers |
 * | float32             | 124      | writeFloat32       | |
 * | float64             | 123      | writeFloat64       | |
 * | bigint              | 122      | writeBigInt64      | |
 * | boolean (false)     | 121      |                    | True and false are different data types so we save the following byte |
 * | boolean (true)      | 120      |                    | - 0b01111000 so the last bit determines whether true or false |
 * | string              | 119      | writeVarString     | |
 * | object<string,any>  | 118      | custom             | Writes {length} then {length} key-value pairs |
 * | array<any>          | 117      | custom             | Writes {length} then {length} json values |
 * | Uint8Array          | 116      | writeVarUint8Array | We use Uint8Array for any kind of binary data |
 *
 * Reasons for the decreasing prefix:
 * We need the first bit for extendability (later we may want to encode the
 * prefix with writeVarUint). The remaining 7 bits are divided as follows:
 * [0-30]   the beginning of the data range is used for custom purposes
 *          (defined by the function that uses this library)
 * [31-127] the end of the data range is used for data encoding by
 *          lib0/encoding.js
 *
 * @param {Encoder} encoder
 * @param {undefined|null|number|bigint|boolean|string|Object<string,any>|Array<any>|Uint8Array} data
 */
void writeAny(Encoder encoder, dynamic _data) {
  final data = _data;
  if (data is String) {
    // TYPE 119: STRING
    write(encoder, 119);
    writeVarString(encoder, data);
  } else if (data is int) {
    // TODO: && data <= binary.BITS31
    // TYPE 125: INTEGER
    write(encoder, 125);
    writeVarInt(encoder, data);
  } else if (data is double) {
    if (isFloat32(data)) {
      // TYPE 124: FLOAT32
      write(encoder, 124);
      writeFloat32(encoder, data);
    } else {
      // TYPE 123: FLOAT64
      write(encoder, 123);
      writeFloat64(encoder, data);
    }
  } else if (data is BigInt) {
    // TYPE 122: BigInt
    write(encoder, 122);
    writeBigInt64(encoder, data);
  } else if (data == null) {
    // TYPE 126: null
    write(encoder, 126);
  } else if (data is List) {
    // TYPE 117: Array
    write(encoder, 117);
    writeVarUint(encoder, data.length);
    for (var i = 0; i < data.length; i++) {
      writeAny(encoder, data[i]);
    }
  } else if (data is Uint8List) {
    // TYPE 116: ArrayBuffer
    write(encoder, 116);
    writeVarUint8Array(encoder, data);
  } else if (data is Map) {
    // TYPE 118: Object
    write(encoder, 118);
    final keys = data.keys.toList().cast<String>();
    writeVarUint(encoder, keys.length);
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      writeVarString(encoder, key);
      writeAny(encoder, data[key]);
    }
  } else if (data is bool) {
    // TYPE 120/121: boolean (true/false)
    write(encoder, data ? 120 : 121);
  } else {
    // TYPE 127: undefined
    write(encoder, 127);
  }
}

/**
 * Now come a few stateful encoder that have their own classes.
 */

/**
 * Basic Run Length Encoder - a basic compression implementation.
 *
 * Encodes [1,1,1,7] to [1,3,7,1] (3 times 1, 1 time 7). This encoder might do more harm than good if there are a lot of values that are not repeated.
 *
 * It was originally used for image compression. Cool .. article http://csbruce.com/cbm/transactor/pdfs/trans_v7_i06.pdf
 *
 * @note T must not be null!
 *
 * @template T
 */
class RleEncoder<T> extends Encoder {
  /**
   * @param {function(Encoder, T):void} writer
   */
  RleEncoder(this.w);
  /**
     * Current state
     * @type {T|null}
     */
  T? s;
  int count = 0;

  /**
     * The writer
     */
  void Function(Encoder, T) w;

  /**
   * @param {T} v
   */
  void write(T v) {
    if (this.s == v) {
      this.count++;
    } else {
      if (this.count > 0) {
        // flush counter, unless this is the first value (count = 0)
        writeVarUint(
            this,
            this.count -
                1); // since count is always > 0, we can decrement by one. non-standard encoding ftw
      }
      this.count = 1;
      // write first value
      this.w(this, v);
      this.s = v;
    }
  }
}

/**
 * Basic diff decoder using variable length encoding.
 *
 * Encodes the values [3, 1100, 1101, 1050, 0] to [3, 1097, 1, -51, -1050] using writeVarInt.
 */
class IntDiffEncoder extends Encoder {
  /**
   * @param {number} start
   */
  IntDiffEncoder(this.s);
  /**
     * Current state
     * @type {number}
     */
  int s;

  /**
   * @param {number} v
   */
  void write(int v) {
    writeVarInt(this, v - this.s);
    this.s = v;
  }
}

/**
 * A combination of IntDiffEncoder and RleEncoder.
 *
 * Basically first writes the IntDiffEncoder and then counts duplicate diffs using RleEncoding.
 *
 * Encodes the values [1,1,1,2,3,4,5,6] as [1,1,0,2,1,5] (RLE([1,0,0,1,1,1,1,1]) ⇒ RleIntDiff[1,1,0,2,1,5])
 */
class RleIntDiffEncoder extends Encoder {
  /**
   * @param {number} start
   */
  RleIntDiffEncoder(this.s);
  /**
     * Current state
     * @type {number}
     */
  int s;
  int count = 0;

  /**
   * @param {number} v
   */
  void write(int v) {
    if (this.s == v && this.count > 0) {
      this.count++;
    } else {
      if (this.count > 0) {
        // flush counter, unless this is the first value (count = 0)
        writeVarUint(
            this,
            this.count -
                1); // since count is always > 0, we can decrement by one. non-standard encoding ftw
      }
      this.count = 1;
      // write first value
      writeVarInt(this, v - this.s);
      this.s = v;
    }
  }
}

/**
 * @param {UintOptRleEncoder} encoder
 */
void flushUintOptRleEncoder(UintOptRleEncoder encoder) {
  if (encoder.count > 0) {
    // flush counter, unless this is the first value (count = 0)
    // case 1: just a single value. set sign to positive
    // case 2: write several values. set sign to negative to indicate that there is a length coming
    writeVarInt(encoder.encoder, encoder.count == 1 ? encoder.s : -encoder.s);
    if (encoder.count > 1) {
      writeVarUint(
          encoder.encoder,
          encoder.count -
              2); // since count is always > 1, we can decrement by one. non-standard encoding ftw
    }
  }
}

/**
 * Optimized Rle encoder that does not suffer from the mentioned problem of the basic Rle encoder.
 *
 * Internally uses VarInt encoder to write unsigned integers. If the input occurs multiple times, we write
 * write it as a negative number. The UintOptRleDecoder then understands that it needs to read a count.
 *
 * Encodes [1,2,3,3,3] as [1,2,-3,3] (once 1, once 2, three times 3)
 */
class UintOptRleEncoder {
  UintOptRleEncoder();
  final encoder = Encoder();
  /**
     * @type {number}
     */
  int s = 0;
  int count = 0;

  /**
   * @param {number} v
   */
  void write(int v) {
    if (this.s == v) {
      this.count++;
    } else {
      flushUintOptRleEncoder(this);
      this.count = 1;
      this.s = v;
    }
  }

  Uint8List toUint8Array() {
    flushUintOptRleEncoder(this);
    return _toUint8Array(this.encoder);
  }
}

/**
 * Increasing Uint Optimized RLE Encoder
 *
 * The RLE encoder counts the number of same occurences of the same value.
 * The IncUintOptRle encoder counts if the value increases.
 * I.e. 7, 8, 9, 10 will be encoded as [-7, 4]. 1, 3, 5 will be encoded
 * as [1, 3, 5].
 */
class IncUintOptRleEncoder implements UintOptRleEncoder {
  IncUintOptRleEncoder();
  final encoder = Encoder();
  /**
     * @type {number}
     */
  int s = 0;
  int count = 0;

  /**
   * @param {number} v
   */
  void write(int v) {
    if (this.s + this.count == v) {
      this.count++;
    } else {
      flushUintOptRleEncoder(this);
      this.count = 1;
      this.s = v;
    }
  }

  Uint8List toUint8Array() {
    flushUintOptRleEncoder(this);
    return _toUint8Array(this.encoder);
  }
}

/**
 * @param {IntDiffOptRleEncoder} encoder
 */
void flushIntDiffOptRleEncoder(IntDiffOptRleEncoder encoder) {
  if (encoder.count > 0) {
    //          31 bit making up the diff | wether to write the counter
    final encodedDiff = encoder.diff << 1 | (encoder.count == 1 ? 0 : 1);
    // flush counter, unless this is the first value (count = 0)
    // case 1: just a single value. set first bit to positive
    // case 2: write several values. set first bit to negative to indicate that there is a length coming
    writeVarInt(encoder.encoder, encodedDiff);
    if (encoder.count > 1) {
      writeVarUint(
          encoder.encoder,
          encoder.count -
              2); // since count is always > 1, we can decrement by one. non-standard encoding ftw
    }
  }
}

/**
 * A combination of the IntDiffEncoder and the UintOptRleEncoder.
 *
 * The count approach is similar to the UintDiffOptRleEncoder, but instead of using the negative bitflag, it encodes
 * in the LSB whether a count is to be read. Therefore this Encoder only supports 31 bit integers!
 *
 * Encodes [1, 2, 3, 2] as [3, 1, 6, -1] (more specifically [(1 << 1) | 1, (3 << 0) | 0, -1])
 *
 * Internally uses variable length encoding. Contrary to normal UintVar encoding, the first byte contains:
 * * 1 bit that denotes whether the next value is a count (LSB)
 * * 1 bit that denotes whether this value is negative (MSB - 1)
 * * 1 bit that denotes whether to continue reading the variable length integer (MSB)
 *
 * Therefore, only five bits remain to encode diff ranges.
 *
 * Use this Encoder only when appropriate. In most cases, this is probably a bad idea.
 */
class IntDiffOptRleEncoder {
  IntDiffOptRleEncoder();
  final encoder = Encoder();
  /**
     * @type {number}
     */
  int s = 0;
  int count = 0;
  int diff = 0;

  /**
   * @param {number} v
   */
  void write(int v) {
    if (this.diff == v - this.s) {
      this.s = v;
      this.count++;
    } else {
      flushIntDiffOptRleEncoder(this);
      this.count = 1;
      this.diff = v - this.s;
      this.s = v;
    }
  }

  Uint8List toUint8Array() {
    flushIntDiffOptRleEncoder(this);
    return _toUint8Array(this.encoder);
  }
}

/**
 * Optimized String Encoder.
 *
 * Encoding many small strings in a simple Encoder is not very efficient. The function call to decode a string takes some time and creates references that must be eventually deleted.
 * In practice, when decoding several million small strings, the GC will kick in more and more often to collect orphaned string objects (or maybe there is another reason?).
 *
 * This string encoder solves the above problem. All strings are concatenated and written as a single string using a single encoding call.
 *
 * The lengths are encoded using a UintOptRleEncoder.
 */
class StringEncoder {
  StringEncoder();
  /**
     * @type {Array<string>}
     */
  final sarr = <String>[];
  var s = '';
  final lensE = UintOptRleEncoder();

  /**
   * @param {string} string
   */
  void write(String string) {
    this.s += string;
    if (this.s.length > 19) {
      this.sarr.add(this.s);
      this.s = '';
    }
    this.lensE.write(string.length);
  }

  Uint8List toUint8Array() {
    final encoder = Encoder();
    this.sarr.add(this.s);
    this.s = '';
    writeVarString(encoder, this.sarr.join(''));
    writeUint8Array(encoder, this.lensE.toUint8Array());
    return _toUint8Array(encoder);
  }
}
