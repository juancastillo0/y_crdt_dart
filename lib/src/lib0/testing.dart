// /**
//  * Testing framework with support for generating tests.
//  *
//  * ```js
//  * // test.js template for creating a test executable
//  * import { runTests } from 'lib0/testing.js'
//  * import * as log from 'lib0/logging.js'
//  * import * as mod1 from './mod1.test.js'
//  * import * as mod2 from './mod2.test.js'
//  * import { isBrowser, isNode } from 'lib0/environment.js'
//  *
//  * if (isBrowser) {
//  *   // optional: if this is ran in the browser, attach a virtual console to the dom
//  *   log.createVConsole(document.body)
//  * }
//  *
//  * runTests({
//  *  mod1,
//  *  mod2,
//  * }).then(success => {
//  *   if (isNode) {
//  *     process.exit(success ? 0 : 1)
//  *   }
//  * })
//  * ```
//  *
//  * ```js
//  * // mod1.test.js
//  * /**
//  *  * runTests automatically tests all exported functions that start with "test".
//  *  * The name of the function should be in camelCase and is used for the logging output.
//  *  *
//  *  * @param {t.TestCase} tc
//  *  *\/
//  * void testMyFirstTest = tc => {
//  *   t.compare({ a: 4 }, { a: 4 }, 'objects are equal')
//  * }
//  * ```
//  *
//  * Now you can simply run `node test.js` to run your test or run test.js in the browser.
//  *
//  * @module testing
//  */

import 'dart:async' show FutureOr;
// import * as log from "./logging.js";
// import { simpleDiff } from "./diff.js";
// import * as object from "./object.js";
// import * as string from "./string.js";
// import * as math from "./math.js";
// import * as random from "./random.js";
// import * as prng from "./prng.js";
// import * as statistics from "./statistics.js";
// import * as array from "./array.js";
// import * as env from "./environment.js";
// import * as json from "./json.js";
// import * as time from "./time.js";
// import * as promise from "./promise.js";

import 'dart:convert' show jsonEncode;
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:y_crdt/src/y_crdt_base.dart';
import 'package:test/test.dart' as test;
import 'prng.dart' as global_prng;

// import { performance } from "./isomorphic.js";

// export { production } from "./environment.js";

class _Performance {
  const _Performance();

  int now() => DateTime.now().millisecondsSinceEpoch;

  void mark(String name) {}
}

const performance = _Performance();

class _Time {
  const _Time();

  String humanizeDuration(int duration) {
    if (duration < 1e3) {
      return "$duration milliseconds";
    } else if (duration < 60e3) {
      return "${duration / 1000.0} seconds";
    } else {
      return "${duration / (1000.0 * 60)} minutes";
    }
  }
}

const time = _Time();

class _Log {
  const _Log();

  void group(String name) {
    logger.i("group: $name");
  }

  void groupEnd() {
    logger.i("groupEnd");
  }

  void groupCollapsed(String name) {
    logger.i("groupCollapsed: $name");
  }
}

const log = _Log();

class _StringDiff {
  final int index;
  final int remove;
  final String insert;

  _StringDiff(
      {required this.index, required this.remove, required this.insert});
}

_StringDiff simpleDiffString(String a, String b) {
  var left = 0; // number of same characters counting from left
  var right = 0; // number of same characters counting from right
  while (left < a.length && left < b.length && a[left] == b[left]) {
    left++;
  }
  if (left != a.length || left != b.length) {
    // Only check right if a !== b
    while (right + left < a.length &&
        right + left < b.length &&
        a[a.length - right - 1] == b[b.length - right - 1]) {
      right++;
    }
  }
  return _StringDiff(
      index: left,
      remove: a.length - left - right,
      insert: b.substring(left, b.length - right));
}

class _Env {
  bool hasConf(String conf) => hasParam('--' + conf);
  bool hasParam(String param) =>
      kIsWeb ? false : Platform.environment.containsKey(param);
  String getParam(String param, String def) =>
      kIsWeb ? def : Platform.environment.get(param) ?? def;
}

final env = _Env();

final extensive = env.hasConf("extensive");

/* istanbul ignore next */
final envSeed =
    env.hasParam("--seed") ? int.parse(env.getParam("--seed", "0")) : null;

class TestCase {
  /**
   * @param {string} moduleName
   * @param {string} testName
   */
  TestCase(this.moduleName, this.testName);

  int? _seed;
  Random? _prng;

  /**
     * @type {string}
     */
  final String moduleName;
  /**
     * @type {string}
     */
  final String testName;

  void resetSeed() {
    this._seed = null;
    this._prng = null;
  }

  /**
   * @type {number}
   */
  /* istanbul ignore next */
  int get seed {
    /* istanbul ignore else */
    if (this._seed == null) {
      /* istanbul ignore next */
      this._seed = envSeed ?? Random().nextInt(3000000);
    }
    return this._seed!;
  }

  /**
   * A PRNG for this test case. Use only this PRNG for randomness to make the test case reproducible.
   *
   * @type {prng.PRNG}
   */
  Random get prng {
    /* istanbul ignore else */
    if (this._prng == null) {
      this._prng = global_prng.create(this.seed);
    }
    return this._prng!;
  }
}

final repititionTime = int.parse(env.getParam("--repitition-time", "50"));
/* istanbul ignore next */
final testFilter =
    env.hasParam("--filter") ? env.getParam("--filter", "") : null;

/* istanbul ignore next */
final testFilterRegExp =
    testFilter != null ? RegExp(testFilter!) : RegExp(".*");

final repeatTestRegex = RegExp("^(repeat|repeating)s");

/**
 * @param {string} moduleName
 * @param {string} name
 * @param {function(TestCase):void|Promise<any>} f
 * @param {number} i
 * @param {number} numberOfTests
 */
Future<bool> run(String moduleName, String name,
    FutureOr<void> Function(TestCase) f, int i, int numberOfTests) async {
  final uncamelized = name.substring(4);
  final filtered = !testFilterRegExp
      .hasMatch("[${i + 1}/${numberOfTests}] ${moduleName}: ${uncamelized}");
  /* istanbul ignore if */
  if (filtered) {
    return true;
  }
  final tc = TestCase(moduleName, name);
  final repeat = repeatTestRegex.hasMatch(uncamelized);
  final groupLog = "[${i + 1}/${numberOfTests}] ${moduleName}: $uncamelized";
  /* istanbul ignore next */
  if (testFilter == null) {
    log.groupCollapsed(groupLog);
  } else {
    log.group(groupLog);
  }
  final times = <int>[];
  final start = performance.now();
  var lastTime = start;
  Object? err;
  StackTrace? errStack;
  performance.mark("${name}-start");
  do {
    try {
      final p = f(tc);
      // if (promise.isPromise(p)) {
      await p;
      // }
    } catch (_err, _stack) {
      err = _err;
      errStack = _stack;
    }
    final currTime = performance.now();
    times.add(currTime - lastTime);
    lastTime = currTime;
    if (repeat && err == null && lastTime - start < repititionTime) {
      tc.resetSeed();
    } else {
      break;
    }
  } while (err == null && lastTime - start < repititionTime);
  performance.mark("${name}-end");
  /* istanbul ignore if */
  if (err != null && err is! SkipError) {
    logger.e("Error: ", err, errStack);
  }
  // TODO:
  // performance.measure(name, "${name}-start", "${name}-end");
  log.groupEnd();
  final duration = lastTime - start;
  var success = true;
  times.sort((a, b) => a - b);
  /* istanbul ignore next */
  // TODO:
  // final againMessage = env.isBrowser
  //   ? "     - ${window.location.href}?filter=\\[${i + 1}/${
  //       tc._seed == null ? "" : "&seed=${tc._seed}"
  //     }"
  //   : "\nrepeat: npm run test -- --filter "\\[${i + 1}/" ${
  //       tc._seed == null ? "" : "--seed ${tc._seed}"
  //     }";

  final againMessage =
      "\nrepeat: npm run test -- --filter '\\[${i + 1}/' ${tc._seed == null ? '' : '--seed ${tc._seed}'}";
  final avgDuration =
      times.reduce((value, element) => value + element) / times.length;
  final medianDuration = times[(times.length / 2).floor()];

  final timeInfo = repeat && err == null
      ? " - ${times.length} repititions in ${time.humanizeDuration(duration)} (best: ${time.humanizeDuration(times.first)}, worst: ${time.humanizeDuration(times.last)}, median: ${time.humanizeDuration(medianDuration)}, average: ${time.humanizeDuration(avgDuration.round())})"
      : " in ${time.humanizeDuration(duration)}";
  if (err != null) {
    /* istanbul ignore else */
    if (err is SkipError) {
      logger.i("Skipped: $uncamelized");
    } else {
      success = false;
      logger.e("Failure: $uncamelized $timeInfo\n $againMessage");
    }
  } else {
    logger.i(
      "Success: $uncamelized\n $againMessage",
    );
  }
  return success;
}

/**
 * Describe what you are currently testing. The message will be logged.
 *
 * ```js
 * void testMyFirstTest = tc => {
 *   t.describe('crunching numbers', 'already crunched 4 numbers!') // the optional second argument can describe the state.
 * }
 * ```
 *
 * @param {string} description
 * @param {string} info
 */
void describe(String description, [String info = ""]) =>
    logger.i("$description $info");

/**
 * Describe the state of the current computation.
 * ```js
 * void testMyFirstTest = tc => {
 *   t.info(already crunched 4 numbers!') // the optional second argument can describe the state.
 * }
 * ```
 *
 * @param {string} info
 */
void info(String info) => describe("", info);

// final printDom = log.printDom;

// final printCanvas = log.printCanvas;

/**
 * Group outputs in a collapsible category.
 *
 * ```js
 * void testMyFirstTest = tc => {
 *   t.group('subtest 1', () => {
 *     t.describe('this message is part of a collapsible section')
 *   })
 *   await t.groupAsync('subtest async 2', async () => {
 *     await someaction()
 *     t.describe('this message is part of a collapsible section')
 *   })
 * }
 * ```
 *
 * @param {string} description
 * @param {function(void):void} f
 */
void group(String description, void Function() f) {
  log.group(description);
  try {
    f();
  } finally {
    log.groupEnd();
  }
}

/**
 * Group outputs in a collapsible category.
 *
 * ```js
 * void testMyFirstTest = async tc => {
 *   t.group('subtest 1', () => {
 *     t.describe('this message is part of a collapsible section')
 *   })
 *   await t.groupAsync('subtest async 2', async () => {
 *     await someaction()
 *     t.describe('this message is part of a collapsible section')
 *   })
 * }
 * ```
 *
 * @param {string} description
 * @param {function(void):Promise<any>} f
 */
void groupAsync(String description, Future Function() f) async {
  log.group(description);
  try {
    await f();
  } finally {
    log.groupEnd();
  }
}

/**
 * Measure the time that it takes to calculate something.
 *
 * ```js
 * void testMyFirstTest = async tc => {
 *   t.measureTime('measurement', () => {
 *     heavyCalculation()
 *   })
 *   await t.groupAsync('async measurement', async () => {
 *     await heavyAsyncCalculation()
 *   })
 * }
 * ```
 *
 * @param {string} message
 * @param {function():void} f
 * @return {number} Returns a promise that resolves the measured duration to apply f
 */
int measureTime(String message, void Function() f) {
  int duration;
  final start = performance.now();
  try {
    f();
  } finally {
    duration = performance.now() - start;
    logger.i(message);
    logger.i(time.humanizeDuration(duration));
  }
  return duration;
}

/**
 * Measure the time that it takes to calculate something.
 *
 * ```js
 * void testMyFirstTest = async tc => {
 *   t.measureTimeAsync('measurement', async () => {
 *     await heavyCalculation()
 *   })
 *   await t.groupAsync('async measurement', async () => {
 *     await heavyAsyncCalculation()
 *   })
 * }
 * ```
 *
 * @param {string} message
 * @param {function():Promise<any>} f
 * @return {Promise<number>} Returns a promise that resolves the measured duration to apply f
 */
Future<int> measureTimeAsync(String message, Future<void> Function() f) async {
  int duration;
  final start = performance.now();
  try {
    await f();
  } finally {
    duration = performance.now() - start;
    logger.i(message);
    logger.i(time.humanizeDuration(duration));
  }
  return duration;
}

/**
 * @template T
 * @param {Array<T>} as
 * @param {Array<T>} bs
 * @param {string} [m]
 * @return {boolean}
 */
bool compareArrays<T>(List<T> left, List<T> right,
    [String m = "Arrays match"]) {
  if (left.length != right.length) {
    fail(m);
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      fail(m);
    }
  }
  return true;
}

/**
 * @param {string} a
 * @param {string} b
 * @param {string} [m]
 * @throws {TestError} Throws if tests fails
 */
void compareStrings(String a, String b, [String m = "Strings match"]) {
  if (a != b) {
    final diff = simpleDiffString(a, b);
    logger.i(a.substring(0, diff.index));
    logger.i(a.substring(diff.index, diff.remove));
    logger.i(diff.insert);

    a.substring(diff.index + diff.remove);
    fail(m);
  }
}

/**
 * @template K,V
 * @param {Object<K,V>} a
 * @param {Object<K,V>} b
 * @param {string} [m]
 * @throws {TestError} Throws if test fails
 */
void compareObjects<K, V>(Map<K, V> a, Map<K, V> b,
    [String m = "Objects match"]) {
  if (a.length != b.length) {
    fail(m);
  } else {
    if (!a.entries.every(
        (entry) => b.containsKey(entry.key) && b[entry.key] == entry.value)) {
      fail(m);
    }
  }
}

/**
 * @param {any} constructor
 * @param {any} a
 * @param {any} b
 * @param {string} path
 * @throws {TestError}
 */
bool compareValues(
    dynamic constructor, dynamic a, dynamic b, String path, dynamic _) {
  if (a != b) {
    fail(
        "Values $a (${jsonEncode(a)}) and $b (${jsonEncode(b)}) don't match (${path})");
  }
  return true;
}

/**
 * @param {string?} message
 * @param {string} reason
 * @param {string} path
 * @throws {TestError}
 */
void _failMessage(String? message, String reason, String path) => fail(
    message == null ? "${reason} ${path}" : "${message} (${reason}) ${path}");

/**
 * @param {any} a
 * @param {any} b
 * @param {string} path
 * @param {string?} message
 * @param {function(any,any,any,string,any):boolean} customCompare
 */
bool _compare(Object? a, Object? b, String path, String? message,
    bool Function(dynamic, dynamic, dynamic, String, dynamic) customCompare) {
  // we don't use assert here because we want to test all branches (istanbul errors if one branch is not tested)
  if (a == null || b == null) {
    return compareValues(null, a, b, path, null);
  }
  // TODO:
  // if (a.runtimeType!= b.runtimeType) {
  //   _failMessage(message, "Constructors don't match", path);
  // }
  var success = true;
  if (a is ByteBuffer && b is ByteBuffer) {
    final _a = Uint8List.view(a);
    final _b = Uint8List.view(b);
    if (a.lengthInBytes != b.lengthInBytes) {
      _failMessage(message, "ArrayBuffer lengths match", path);
    }
    for (var i = 0; success && i < _a.length; i++) {
      success = success && _a[i] == _b[i];
    }
  } else if (a is Uint8List && b is Uint8List) {
    if (a.lengthInBytes != b.lengthInBytes) {
      _failMessage(message, "ArrayBuffer lengths match", path);
    }
    for (var i = 0; success && i < a.length; i++) {
      success = success && a[i] == b[i];
    }
  } else if (a is Set && b is Set) {
    if (a.length != b.length) {
      _failMessage(message, "Sets have different number of attributes", path);
    }
    a.forEach((value) {
      if (!b.contains(value)) {
        _failMessage(message, "b.${path} does have ${value}", path);
      }
    });
  } else if (a is Map && b is Map) {
    if (a.length != b.length) {
      _failMessage(message, "Maps have different number of attributes", path);
    }
    // @ts-ignore
    a.forEach((key, value) {
      if (!b.containsKey(key)) {
        _failMessage(
            message,
            "Property ${path}['${key}'] does not exist on second argument",
            path);
      }
      _compare(value, b.get(key), "${path}['${key}']", message, customCompare);
    });
  } else if (a is List && b is List) {
    if (a.length != b.length) {
      _failMessage(
          message, "Arrays have a different number of attributes $a $b", path);
    }
    // @ts-ignore
    a.mapIndex((value, i) =>
        _compare(value, b[i], "${path}[${i}]", message, customCompare));
  } else {
    if (!customCompare(a.runtimeType, a, b, path, compareValues)) {
      _failMessage(message,
          "Values ${jsonEncode(a)} and ${jsonEncode(b)} don't match", path);
    }
  }

  assert(success, message);
  return true;
}

/**
 * @template T
 * @param {T} a
 * @param {T} b
 * @param {string?} [message]
 * @param {function(any,T,T,string,any):boolean} [customCompare]
 */
void compare<T>(
  T a,
  T b, [
  String? message,
  bool Function(dynamic, T, T, String, dynamic) customCompare = compareValues,
]) =>
    _compare(
      a,
      b,
      "obj",
      message,
      customCompare as bool Function(
          dynamic, dynamic, dynamic, String, dynamic),
    );

/* istanbul ignore next */
/**
 * @param {boolean} condition
 * @param {string?} [message]
 * @throws {TestError}
 */
void check(bool condition, [String? message]) {
  if (!condition) {
    fail("Assertion failed${message != null ? ': ${message}' : ''}");
  }
}

/**
 * @param {function():void} f
 * @throws {TestError}
 */
void fails(void Function() f) {
  Object? err;
  try {
    f();
  } catch (_err) {
    err = _err;
    logger.i("⇖ This Error was expected");
  }
  /* istanbul ignore if */
  if (err == null) {
    fail("Expected this to fail");
  }
}

/**
 * @param {Object<string, Object<string, function(TestCase):void|Promise<any>>>} tests
 */
Future<bool> runTests(
    Map<String, Map<String, FutureOr<void> Function(TestCase)?>> tests) async {
  final numberOfTests = tests.values
      .expand<int>((mod) =>
          mod.values.map((f) => /* istanbul ignore next */ f != null ? 1 : 0))
      .reduce((l, r) => l + r);
  var successfulTests = 0;
  var testnumber = 0;
  final start = performance.now();
  for (final modName in tests.keys) {
    final mod = tests[modName]!;
    for (final fname in mod.keys) {
      final f = mod[fname];
      /* istanbul ignore else */
      if (f != null) {
        const repeatEachTest = 1;
        var success = true;
        test.test(fname, () async {
          for (var i = 0; success && i < repeatEachTest; i++) {
            success = await run(modName, fname, f, testnumber, numberOfTests);
          }
        });
        testnumber++;
        /* istanbul ignore else */
        if (success) {
          successfulTests++;
        }
      }
    }
  }
  final end = performance.now();
  logger.i("");
  final success = successfulTests == numberOfTests;
  /* istanbul ignore next */
  if (success) {
    /* istanbul ignore next */
    logger.i("All tests successful! in ${time.humanizeDuration(end - start)}");
    /* istanbul ignore next */
    // TODO:
    // log.printImgBase64(nyanCatImage, 50);
  } else {
    final failedTests = numberOfTests - successfulTests;
    logger.e("> ${failedTests} test${failedTests > 1 ? "s" : ""} failed");
  }
  return success;
}

class TestError implements Exception {
  final String message;
  const TestError(this.message);

  @override
  String toString() {
    return "TestError: $message";
  }
}

/**
 * @param {string} reason
 * @throws {TestError}
 */
void fail(String reason) {
  logger.e("X $reason");
  throw TestError("Test Failed");
}

class SkipError implements Exception {
  final String message;
  const SkipError(this.message);

  @override
  String toString() {
    return "SkipError: $message";
  }
}

/**
 * @param {boolean} cond If true, this tests will be skipped
 * @throws {SkipError}
 */
void skip([bool cond = true]) {
  if (cond) {
    throw SkipError("skipping..");
  }
}

// eslint-disable-next-line
const nyanCatImage =
    "R0lGODlhjABMAPcAAMiSE0xMTEzMzUKJzjQ0NFsoKPc7//FM/9mH/z9x0HIiIoKCgmBHN+frGSkZLdDQ0LCwsDk71g0KCUzDdrQQEOFz/8yYdelmBdTiHFxcXDU2erR/mLrTHCgoKK5szBQUFNgSCTk6ymfpCB9VZS2Bl+cGBt2N8kWm0uDcGXhZRUvGq94NCFPhDiwsLGVlZTgqIPMDA1g3aEzS5D6xAURERDtG9JmBjJsZGWs2AD1W6Hp6eswyDeJ4CFNTU1LcEoJRmTMzSd14CTg5ser2GmDzBd17/xkZGUzMvoSMDiEhIfKruCwNAJaWlvRzA8kNDXDrCfi0pe1U/+GS6SZrAB4eHpZwVhoabsx9oiYmJt/TGHFxcYyMjOid0+Zl/0rF6j09PeRr/0zU9DxO6j+z0lXtBtp8qJhMAEssLGhoaPL/GVn/AAsWJ/9/AE3Z/zs9/3cAAOlf/+aa2RIyADo85uhh/0i84WtrazQ0UyMlmDMzPwUFBe16BTMmHau0E03X+g8pMEAoS1MBAf++kkzO8pBaqSZoe9uB/zE0BUQ3Sv///4WFheuiyzo880gzNDIyNissBNqF/8RiAOF2qG5ubj0vL1z6Avl5ASsgGkgUSy8vL/8n/z4zJy8lOv96uEssV1csAN5ZCDQ0Wz1a3tbEGHLeDdYKCg4PATE7PiMVFSoqU83eHEi43gUPAOZ8reGogeKU5dBBC8faHEez2lHYF4bQFMukFtl4CzY3kkzBVJfMGZkAAMfSFf27mP0t//g4/9R6Dfsy/1DRIUnSAPRD/0fMAFQ0Q+l7rnbaD0vEntCDD6rSGtO8GNpUCU/MK07LPNEfC7RaABUWWkgtOst+71v9AfD7GfDw8P19ATtA/NJpAONgB9yL+fm6jzIxMdnNGJxht1/2A9x//9jHGOSX3+5tBP27l35+fk5OTvZ9AhYgTjo0PUhGSDs9+LZjCFf2Aw0IDwcVAA8PD5lwg9+Q7YaChC0kJP8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh/wtYTVAgRGF0YVhNUDw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuMC1jMDYwIDYxLjEzNDc3NywgMjAxMC8wMi8xMi0xNzozMjowMCAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0UmVmPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VSZWYjIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtcE1NOk9yaWdpbmFsRG9jdW1lbnRJRD0ieG1wLmRpZDpGNEM2MUEyMzE0QTRFMTExOUQzRkE3QTBCRDNBMjdBQyIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDpERjQ0NEY0QkI2MTcxMUUxOUJEQkUzNUNGQTkwRTU2MiIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDpERjQ0NEY0QUI2MTcxMUUxOUJEQkUzNUNGQTkwRTU2MiIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgQ1M1IFdpbmRvd3MiPiA8eG1wTU06RGVyaXZlZEZyb20gc3RSZWY6aW5zdGFuY2VJRD0ieG1wLmlpZDo1OEE3RTIwRjcyQTlFMTExOTQ1QkY2QTU5QzVCQjJBOSIgc3RSZWY6ZG9jdW1lbnRJRD0ieG1wLmRpZDpGNEM2MUEyMzE0QTRFMTExOUQzRkE3QTBCRDNBMjdBQyIvPiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gPD94cGFja2V0IGVuZD0iciI/PgH//v38+/r5+Pf29fTz8vHw7+7t7Ovq6ejn5uXk4+Lh4N/e3dzb2tnY19bV1NPS0dDPzs3My8rJyMfGxcTDwsHAv769vLu6ubi3trW0s7KxsK+urayrqqmop6alpKOioaCfnp2cm5qZmJeWlZSTkpGQj46NjIuKiYiHhoWEg4KBgH9+fXx7enl4d3Z1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";
