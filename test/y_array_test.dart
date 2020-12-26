// import { init, compare, applyRandomTests, Doc } from "./testHelper.js"; // eslint-disable-line

// import * as Y from "../src/index.js";
// import * as t from "lib0/testing.js";
// import * as prng from "lib0/prng.js";
// import * as math from "lib0/math.js";

// /**
//  * @param {t.TestCase} tc
//  */
// export const testBasicUpdate = (tc) => {
//   const doc1 = new Y.Doc();
//   const doc2 = new Y.Doc();
//   doc1.getArray("array").insert(0, ["hi"]);
//   const update = Y.encodeStateAsUpdate(doc1);
//   Y.applyUpdate(doc2, update);
//   t.compare(doc2.getArray("array").toArray(), ["hi"]);
// };

import 'dart:math' show Random;
import 'dart:math' as math;

import 'package:y_crdt/src/lib0/prng.dart' as prng;
import 'package:y_crdt/y_crdt.dart' as Y;
import 'package:y_crdt/src/lib0/testing.dart' as t;
import 'test_helper.dart';

void main() async {
  await t.runTests(
    {
      "array": {
        "testSlice": testSlice,
        "testDeleteInsert": testDeleteInsert,
        "testInsertThreeElementsTryRegetProperty":
            testInsertThreeElementsTryRegetProperty,
        "testConcurrentInsertWithThreeConflicts":
            testConcurrentInsertWithThreeConflicts,
        "testConcurrentInsertDeleteWithThreeConflicts":
            testConcurrentInsertDeleteWithThreeConflicts,
        "testInsertionsInLateSync": testInsertionsInLateSync,
        "testDisconnectReallyPreventsSendingMessages":
            testDisconnectReallyPreventsSendingMessages,
        "testDeletionsInLateSync": testDeletionsInLateSync,
        "testInsertThenMergeDeleteOnSync": testInsertThenMergeDeleteOnSync,
        "testInsertAndDeleteEvents": testInsertAndDeleteEvents,
        "testNestedObserverEvents": testNestedObserverEvents,
        "testInsertAndDeleteEventsForTypes": testInsertAndDeleteEventsForTypes,
        "testObserveDeepEventOrder": testObserveDeepEventOrder,
        "testChangeEvent": testChangeEvent,
        "testInsertAndDeleteEventsForTypes2":
            testInsertAndDeleteEventsForTypes2,
        "testNewChildDoesNotEmitEventInTransaction":
            testNewChildDoesNotEmitEventInTransaction,
        "testGarbageCollector": testGarbageCollector,
        "testEventTargetIsSetCorrectlyOnLocal":
            testEventTargetIsSetCorrectlyOnLocal,
        "testEventTargetIsSetCorrectlyOnRemote":
            testEventTargetIsSetCorrectlyOnRemote,
        "testIteratingArrayContainingTypes": testIteratingArrayContainingTypes,
        "testRepeatGeneratingYarrayTests6": testRepeatGeneratingYarrayTests6,
      }
    },
  );
}

/**
 * @param {t.TestCase} tc
 */
void testSlice(t.TestCase tc) {
  final doc1 = Y.Doc();
  final arr = doc1.getArray("array");
  arr.insert(0, [1, 2, 3]);
  t.compareArrays(arr.slice(0), [1, 2, 3]);
  t.compareArrays(arr.slice(1), [2, 3]);
  t.compareArrays(arr.slice(0, -1), [1, 2]);
  arr.insert(0, [0]);
  t.compareArrays(arr.slice(0), [0, 1, 2, 3]);
  t.compareArrays(arr.slice(0, 2), [0, 1]);
}

/**
 * @param {t.TestCase} tc
 */
void testDeleteInsert(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final array0 = _data.users[0].array;
  array0.delete(0, 0);
  t.describe("Does not throw when deleting zero elements with position 0");
  t.fails(() {
    array0.delete(1, 1);
  });
  array0.insert(0, ["A"]);
  array0.delete(1, 0);
  t.describe(
      "Does not throw when deleting zero elements with valid position 1");
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testInsertThreeElementsTryRegetProperty(t.TestCase tc) {
  final _data = init(tc, users: 2);
  _data.users[0].array.insert(0, [1, true, false]);
  t.compare(_data.users[0].array.toJSON(), [1, true, false], ".toJSON() works");
  _data.testConnector.flushAllMessages();
  t.compare(_data.users[1].array.toJSON(), [1, true, false],
      ".toJSON() works after sync");
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testConcurrentInsertWithThreeConflicts(t.TestCase tc) {
  final _data = init(tc, users: 3);
  _data.users[0].array.insert(0, [0]);
  _data.users[1].array.insert(0, [1]);
  _data.users[2].array.insert(0, [2]);
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testConcurrentInsertDeleteWithThreeConflicts(t.TestCase tc) {
  final _data = init(tc, users: 3);
  _data.users[0].array.insert(0, ["x", "y", "z"]);
  _data.testConnector.flushAllMessages();
  _data.users[0].array.insert(1, [0]);
  _data.users[1].array.delete(0);
  _data.users[1].array.delete(1, 1);
  _data.users[2].array.insert(1, [2]);
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testInsertionsInLateSync(t.TestCase tc) {
  final _data = init(tc, users: 3);
  final users = _data.userInstances;
  _data.users[0].array.insert(0, ["x", "y"]);
  _data.testConnector.flushAllMessages();
  users[1].disconnect();
  users[2].disconnect();
  _data.users[0].array.insert(1, ["user0"]);
  _data.users[1].array.insert(1, ["user1"]);
  _data.users[2].array.insert(1, ["user2"]);
  users[1].connect();
  users[2].connect();
  _data.testConnector.flushAllMessages();
  compare(users);
}

/**
 * @param {t.TestCase} tc
 */
void testDisconnectReallyPreventsSendingMessages(t.TestCase tc) {
  final _data = init(tc, users: 3);
  final users = _data.userInstances;
  _data.users[0].array.insert(0, ["x", "y"]);
  _data.testConnector.flushAllMessages();
  users[1].disconnect();
  users[2].disconnect();
  _data.users[0].array.insert(1, ["user0"]);
  _data.users[1].array.insert(1, ["user1"]);
  t.compare(_data.users[0].array.toJSON(), ["x", "user0", "y"]);
  t.compare(_data.users[1].array.toJSON(), ["x", "user1", "y"]);
  users[1].connect();
  users[2].connect();
  compare(users);
}

/**
 * @param {t.TestCase} tc
 */
void testDeletionsInLateSync(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final users = _data.userInstances;
  _data.users[0].array.insert(0, ["x", "y"]);
  _data.testConnector.flushAllMessages();
  users[1].disconnect();
  _data.users[1].array.delete(1, 1);
  _data.users[0].array.delete(0, 2);
  users[1].connect();
  compare(users);
}

/**
 * @param {t.TestCase} tc
 */
void testInsertThenMergeDeleteOnSync(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final users = _data.userInstances;
  _data.users[0].array.insert(0, ["x", "y", "z"]);
  _data.testConnector.flushAllMessages();
  users[0].disconnect();
  _data.users[1].array.delete(0, 3);
  users[0].connect();
  compare(users);
}

/**
 * @param {t.TestCase} tc
 */
void testInsertAndDeleteEvents(t.TestCase tc) {
  final _data = init(tc, users: 2);
  /**
   * @type {Object<string,any>?}
   */
  var event = null;
  _data.users[0].array.observe((e, _) {
    event = e;
  });
  _data.users[0].array.insert(0, [0, 1, 2]);
  t.check(event != null);
  event = null;
  _data.users[0].array.delete(0);
  t.check(event != null);
  event = null;
  _data.users[0].array.delete(0, 2);
  t.check(event != null);
  event = null;
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testNestedObserverEvents(t.TestCase tc) {
  final _data = init(tc, users: 2);
  /**
   * @type {Array<number>}
   */
  final vals = [];
  _data.users[0].array.observe((_, __) {
    if (_data.users[0].array.length == 1) {
      // inserting, will call this observer again
      // we expect that this observer is called after this event handler finishedn
      _data.users[0].array.insert(1, [1]);
      vals.add(0);
    } else {
      // this should be called the second time an element is inserted (above case)
      vals.add(1);
    }
  });
  _data.users[0].array.insert(0, [0]);
  t.compareArrays(vals, [0, 1]);
  t.compareArrays(_data.users[0].array.toArray(), [0, 1]);
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testInsertAndDeleteEventsForTypes(t.TestCase tc) {
  final _data = init(tc, users: 2);
  /**
   * @type {Object<string,any>|null}
   */
  var event = null;
  _data.users[0].array.observe((e, _) {
    event = e;
  });
  _data.users[0].array.insert(0, [new Y.YArray()]);
  t.check(event != null);
  event = null;
  _data.users[0].array.delete(0);
  t.check(event != null);
  event = null;
  compare(_data.userInstances);
}

/**
 * This issue has been reported in https://discuss.yjs.dev/t/order-in-which-events-yielded-by-observedeep-should-be-applied/261/2
 *
 * Deep observers generate multiple events. When an array added at item at, say, position 0,
 * and item 1 changed then the array-add event should fire first so that the change event
 * path is correct. A array binding might lead to an inconsistent state otherwise.
 *
 * @param {t.TestCase} tc
 */
void testObserveDeepEventOrder(t.TestCase tc) {
  final _data = init(tc, users: 2);
  /**
   * @type {Array<any>}
   */
  var events = <Y.YEvent>[];
  _data.users[0].array.observeDeep((e, _) {
    events = e;
  });
  _data.users[0].array.insert(0, [Y.YMap()]);
  _data.users[0].instance.transact((_) {
    _data.users[0].array.get(0).set("a", "a");
    _data.users[0].array.insert(0, [0]);
  });
  for (var i = 1; i < events.length; i++) {
    t.check(events[i - 1].path.length <= events[i].path.length,
        "path size increases, fire top-level events first");
  }
}

/**
 * @param {t.TestCase} tc
 */
void testChangeEvent(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final array0 = _data.users[0].array;
  /**
   * @type {any}
   */
  Y.YChanges? changes;
  array0.observe((e, _) {
    changes = e.changes;
  });
  final newArr = Y.YArray();
  array0.insert(0, [newArr, 4, "dtrn"]);
  t.check(changes != null &&
      changes!.added.length == 2 &&
      changes!.deleted.length == 0);
  t.compare(changes!.delta, [
    Y.YDelta.insert([newArr, 4, "dtrn"])
  ]);

  changes = null;
  array0.delete(0, 2);
  t.check(changes != null &&
      changes!.added.length == 0 &&
      changes!.deleted.length == 2);
  t.compare(changes!.delta, [Y.YDelta.delete(2)]);

  changes = null;
  array0.insert(1, [0.1]);
  t.check(changes != null &&
      changes!.added.length == 1 &&
      changes!.deleted.length == 0);
  t.compare(changes!.delta, [
    Y.YDelta.retain(1),
    Y.YDelta.insert([0.1])
  ]);
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testInsertAndDeleteEventsForTypes2(t.TestCase tc) {
  final _data = init(tc, users: 2);
  /**
   * @type {Array<Object<string,any>>}
   */
  final events = [];
  _data.users[0].array.observe((e, _) {
    events.add(e);
  });
  _data.users[0].array.insert(0, ["hi", new Y.YMap()]);
  t.check(events.length == 1,
      "Event is triggered exactly once for insertion of two elements");
  _data.users[0].array.delete(1);
  t.check(events.length == 2, "Event is triggered exactly once for deletion");
  compare(_data.userInstances);
}

/**
 * This issue has been reported here https://github.com/yjs/yjs/issues/155
 * @param {t.TestCase} tc
 */
void testNewChildDoesNotEmitEventInTransaction(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final users = _data.userInstances;
  var fired = false;
  users[0].transact((_) {
    final newMap = Y.YMap();
    newMap.observe((_, __) {
      fired = true;
    });
    _data.users[0].array.insert(0, [newMap]);
    newMap.set("tst", 42);
  });
  t.check(!fired, "Event does not trigger");
}

/**
 * @param {t.TestCase} tc
 */
void testGarbageCollector(t.TestCase tc) {
  final _data = init(tc, users: 3);
  final users = _data.userInstances;
  _data.users[0].array.insert(0, ["x", "y", "z"]);
  _data.testConnector.flushAllMessages();
  users[0].disconnect();
  _data.users[0].array.delete(0, 3);
  users[0].connect();
  _data.testConnector.flushAllMessages();
  compare(users);
}

/**
 * @param {t.TestCase} tc
 */
void testEventTargetIsSetCorrectlyOnLocal(t.TestCase tc) {
  final _data = init(tc, users: 3);
  /**
   * @type {any}
   */
  var event;
  _data.users[0].array.observe((e, _) {
    event = e;
  });
  _data.users[0].array.insert(0, ["stuff"]);
  t.check(event.target == _data.users[0].array,
      '"target" property is set correctly');
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testEventTargetIsSetCorrectlyOnRemote(t.TestCase tc) {
  final _data = init(tc, users: 3);
  /**
   * @type {any}
   */
  var event;
  _data.users[0].array.observe((e, _) {
    event = e;
  });
  _data.users[1].array.insert(0, ["stuff"]);
  _data.testConnector.flushAllMessages();
  t.check(event.target == _data.users[0].array,
      '"target" property is set correctly');
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testIteratingArrayContainingTypes(t.TestCase tc) {
  final y = Y.Doc();
  final arr = y.getArray<Y.YMap>("arr");
  final numItems = 10;
  for (var i = 0; i < numItems; i++) {
    final map = Y.YMap();
    map.set("value", i);
    arr.push([map]);
  }
  var cnt = 0;
  for (final item in arr) {
    t.check(
      item.get("value") == cnt,
      "value is correct ${item.get('value')} $cnt",
    );
    cnt++;
  }
  y.destroy();
}

var _uniqueNumber = 0;
final getUniqueNumber = () => _uniqueNumber++;

void __insert(Y.Doc user, Random gen, dynamic _) {
  final yarray = user.getArray("array");
  final uniqueNumber = getUniqueNumber();
  final content = <int>[];
  final len = prng.int32(gen, 1, 4);
  for (var i = 0; i < len; i++) {
    content.add(uniqueNumber);
  }
  final pos = prng.int32(gen, 0, yarray.length);
  final oldContent = yarray.toArray();
  yarray.insert(pos, content);
  oldContent.insertAll(pos, content);
  // we want to make sure that fastSearch markers insert at the correct position
  t.compareArrays(yarray.toArray(), oldContent);
}

void __insertTypeArray(Y.Doc user, Random gen, dynamic _) {
  final yarray = user.getArray("array");
  var pos = prng.int32(gen, 0, yarray.length);
  yarray.insert(pos, [Y.YArray()]);
  var array2 = yarray.get(pos);
  array2.insert(0, [1, 2, 3, 4]);
}

void __insertTypeMap(Y.Doc user, Random gen, dynamic _) {
  final yarray = user.getArray("array");
  final pos = prng.int32(gen, 0, yarray.length);
  yarray.insert(pos, [Y.YMap()]);
  final map = yarray.get(pos);
  map.set("someprop", 42);
  map.set("someprop", 43);
  map.set("someprop", 44);
}

void __delete(Y.Doc user, Random gen, dynamic _) {
  final yarray = user.getArray("array");
  final length = yarray.length;
  if (length > 0) {
    var somePos = prng.int32(gen, 0, length - 1);
    var delLength = prng.int32(gen, 1, math.min(2, length - somePos));
    if (gen.nextBool()) {
      var type = yarray.get(somePos);
      final _typeLength = type.length as int;
      if (_typeLength > 0) {
        somePos = prng.int32(gen, 0, _typeLength - 1);
        delLength = prng.int32(gen, 0, math.min(2, _typeLength - somePos));
        type.delete(somePos, delLength);
      }
    } else {
      final oldContent = yarray.toArray();
      yarray.delete(somePos, delLength);
      oldContent.removeRange(somePos, somePos + delLength);
      t.compareArrays(yarray.toArray(), oldContent);
    }
  }
}

/**
 * @type {Array<function(Doc,prng.PRNG,any):void>}
 */
const arrayTransactions = [
  __insert,
  __insertTypeArray,
  __insertTypeMap,
  __delete,
];

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests6(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 6);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests40(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 40);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests42(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 42);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests43(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 43);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests44(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 44);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests45(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 45);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests46(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 46);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests300(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 300);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests400(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 400);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests500(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 500);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests600(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 600);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests1000(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 1000);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests1800(t.TestCase tc) {
  applyRandomTests(tc, arrayTransactions, 1800);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests3000(t.TestCase tc) {
  // TODO:
  // t.skip(!t.production);
  applyRandomTests(tc, arrayTransactions, 3000);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests5000(t.TestCase tc) {
  // TODO:
  // t.skip(!t.production);
  applyRandomTests(tc, arrayTransactions, 5000);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYarrayTests30000(t.TestCase tc) {
  // TODO:
  // t.skip(!t.production);
  applyRandomTests(tc, arrayTransactions, 30000);
}
