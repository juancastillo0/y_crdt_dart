import 'dart:math';
import 'package:y_crdt/src/lib0/decoding.dart' show rightShift;

/**
 * Fast Pseudo Random Number Generators.
 *
 * Given a seed a PRNG generates a sequence of numbers that cannot be reasonably predicted.
 * Two PRNGs must generate the same random sequence of numbers if  given the same seed.
 *
 * @module prng
 */

// import * as binary from "./binary.js";
// import { fromCharCode, fromCodePoint } from "./string.js";
// import * as math from "./math.js";
// import { Xoroshiro128plus } from "./prng/Xoroshiro128plus.js";
// import * as buffer from "./buffer.js";

// /**
//  * Description of the function
//  *  @callback generatorNext
//  *  @return {number} A 32bit integer
//  */

// /**
//  * A random type generator.
//  *
//  * @typedef {Object} PRNG
//  * @property {generatorNext} next Generate new number
//  */

// void DefaultPRNG = Xoroshiro128plus;

// /**
//  * Create a Xoroshiro128plus Pseudo-Random-Number-Generator.
//  * This is the fastest full-period generator passing BigCrush without systematic failures.
//  * But there are more PRNGs available in ./PRNG/.
//  *
//  * @param {number} seed A positive 32bit integer. Do not use negative numbers.
//  * @return {PRNG}
//  */
Random create(int seed) => Random(seed);

// /**
//  * Generates a single random bool.
//  *
//  * @param {PRNG} gen A random number generator.
//  * @return {Boolean} A random boolean
//  */
// void bool = (Random gen) => gen.next() >= 0.5;

// /**
//  * Generates a random integer with 53 bit resolution.
//  *
//  * @param {PRNG} gen A random number generator.
//  * @param {Number} min The lower bound of the allowed return values (inclusive).
//  * @param {Number} max The upper bound of the allowed return values (inclusive).
//  * @return {Number} A random integer on [min, max]
//  */
// void int53 = (gen, min, max) =>
//   math.floor(gen.next() * (max + 1 - min) + min);

// /**
//  * Generates a random integer with 53 bit resolution.
//  *
//  * @param {PRNG} gen A random number generator.
//  * @param {Number} min The lower bound of the allowed return values (inclusive).
//  * @param {Number} max The upper bound of the allowed return values (inclusive).
//  * @return {Number} A random integer on [min, max]
//  */
// void uint53 = (gen, min, max) => math.abs(int53(gen, min, max));

/**
 * Generates a random integer with 32 bit resolution.
 *
 * @param {PRNG} gen A random number generator.
 * @param {Number} min The lower bound of the allowed return values (inclusive).
 * @param {Number} max The upper bound of the allowed return values (inclusive).
 * @return {Number} A random integer on [min, max]
 */
int int32(Random gen, int min, int max) =>
    max == min ? max : gen.nextInt(max - min) + min;

// /**
//  * Generates a random integer with 53 bit resolution.
//  *
//  * @param {PRNG} gen A random number generator.
//  * @param {Number} min The lower bound of the allowed return values (inclusive).
//  * @param {Number} max The upper bound of the allowed return values (inclusive).
//  * @return {Number} A random integer on [min, max]
//  */
int uint32(Random gen, int min, int max) => rightShift(int32(gen, min, max), 0);

// /**
//  * @deprecated
//  * Optimized version of prng.int32. It has the same precision as prng.int32, but should be preferred when
//  * openaring on smaller ranges.
//  *
//  * @param {PRNG} gen A random number generator.
//  * @param {Number} min The lower bound of the allowed return values (inclusive).
//  * @param {Number} max The upper bound of the allowed return values (inclusive). The max inclusive number is `binary.BITS31-1`
//  * @return {Number} A random integer on [min, max]
//  */
// void int31 = (gen, min, max) => int32(gen, min, max);

// /**
//  * Generates a random real on [0, 1) with 53 bit resolution.
//  *
//  * @param {PRNG} gen A random number generator.
//  * @return {Number} A random real number on [0, 1).
//  */
// void real53 = (gen) => gen.next(); // (((gen.next() >>> 5) * binary.BIT26) + (gen.next() >>> 6)) / MAX_SAFE_INTEGER

// /**
//  * Generates a random character from char code 32 - 126. I.e. Characters, Numbers, special characters, and Space:
//  *
//  * @param {PRNG} gen A random number generator.
//  * @return {string}
//  *
//  * (Space)!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[/]^_`abcdefghijklmnopqrstuvwxyz{|}~
//  */
// void char = (gen) => fromCharCode(int31(gen, 32, 126));

/**
 * @param {PRNG} gen
 * @return {string} A single letter (a-z)
 */
String letter(Random gen) => String.fromCharCode(int32(gen, 97, 122));

/**
 * @param {PRNG} gen
 * @param {number} [minLen=0]
 * @param {number} [maxLen=20]
 * @return {string} A random word (0-20 characters) without spaces consisting of letters (a-z)
 */
String word(Random gen, [int minLen = 0, int maxLen = 20]) {
  final len = int32(gen, minLen, maxLen);
  var str = "";
  for (var i = 0; i < len; i++) {
    str += letter(gen);
  }
  return str;
}

/**
 * TODO: this function produces invalid runes. Does not cover all of utf16!!
 *
 * @param {PRNG} gen
 * @return {string}
 */
String utf16Rune(Random gen) {
  final codepoint = int32(gen, 0, 256);
  return String.fromCharCode(codepoint);
}

/**
 * @param {PRNG} gen
 * @param {number} [maxlen = 20]
 */
String utf16String(Random gen, [int maxlen = 20]) {
  final len = int32(gen, 0, maxlen);
  var str = "";
  for (var i = 0; i < len; i++) {
    str += utf16Rune(gen);
  }
  return str;
}

/**
 * Returns one element of a given array.
 *
 * @param {PRNG} gen A random number generator.
 * @param {Array<T>} array Non empty Array of possible values.
 * @return {T} One of the values of the supplied Array.
 * @template T
 */
T oneOf<T>(Random gen, List<T> array) => array[int32(gen, 0, array.length - 1)];

// /**
//  * @param {PRNG} gen
//  * @param {number} len
//  * @return {Uint8Array}
//  */
// void uint8Array = (gen, len) => {
//   const buf = buffer.createUint8ArrayFromLen(len);
//   for (let i = 0; i < buf.length; i++) {
//     buf[i] = int32(gen, 0, binary.BITS8);
//   }
//   return buf;
// };

// /**
//  * @param {PRNG} gen
//  * @param {number} len
//  * @return {Uint16Array}
//  */
// void uint16Array = (gen, len) =>
//   new Uint16Array(uint8Array(gen, len * 2).buffer);

// /**
//  * @param {PRNG} gen
//  * @param {number} len
//  * @return {Uint32Array}
//  */
// void uint32Array = (gen, len) =>
//   new Uint32Array(uint8Array(gen, len * 4).buffer);
