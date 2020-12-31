// import { init, compare, applyRandomTests, Doc } from "./testHelper.js"; // eslint-disable-line

// import { compareIDs } from "../src/internals.js";

// import * as Y from "../src/index.js";
// import * as t from "lib0/testing.js";
// import * as prng from "lib0/prng.js";

import 'dart:math' show Random;

import 'package:y_crdt/src/lib0/prng.dart' as prng;
import 'package:y_crdt/src/types/y_map.dart';
import 'package:y_crdt/y_crdt.dart' as Y;
import 'package:y_crdt/src/lib0/testing.dart' as t;
import 'test_helper.dart';

void main() async {
  await t.runTests(
    {
      "map": {
        "testMapHavingIterableAsConstructorParamTests":
            testMapHavingIterableAsConstructorParamTests,
        "testBasicMapTests": testBasicMapTests,
        "testGetAndSetOfMapProperty": testGetAndSetOfMapProperty,
        "testYmapSetsYmap": testYmapSetsYmap,
        "testYmapSetsYarray": testYmapSetsYarray,
        "testGetAndSetOfMapPropertySyncs": testGetAndSetOfMapPropertySyncs,
        "testGetAndSetOfMapPropertyWithConflict":
            testGetAndSetOfMapPropertyWithConflict,
        "testSizeAndDeleteOfMapProperty": testSizeAndDeleteOfMapProperty,
        "testGetAndSetAndDeleteOfMapProperty":
            testGetAndSetAndDeleteOfMapProperty,
        "testGetAndSetOfMapPropertyWithThreeConflicts":
            testGetAndSetOfMapPropertyWithThreeConflicts,
        "testGetAndSetAndDeleteOfMapPropertyWithThreeConflicts":
            testGetAndSetAndDeleteOfMapPropertyWithThreeConflicts,
        "testObserveDeepProperties": testObserveDeepProperties,
        "testObserversUsingObservedeep": testObserversUsingObservedeep,
        "testThrowsAddAndUpdateAndDeleteEvents":
            testThrowsAddAndUpdateAndDeleteEvents,
        "testChangeEvent": testChangeEvent,
        "testYmapEventExceptionsShouldCompleteTransaction":
            testYmapEventExceptionsShouldCompleteTransaction,
        "testRepeatGeneratingYmapTests10": testRepeatGeneratingYmapTests10,
        "testRepeatGeneratingYmapTests40": testRepeatGeneratingYmapTests40,
        "testRepeatGeneratingYmapTests42": testRepeatGeneratingYmapTests42,
        "testRepeatGeneratingYmapTests43": testRepeatGeneratingYmapTests43,
        "testRepeatGeneratingYmapTests44": testRepeatGeneratingYmapTests44,
        "testRepeatGeneratingYmapTests45": testRepeatGeneratingYmapTests45,
        "testRepeatGeneratingYmapTests46": testRepeatGeneratingYmapTests46,
      }
    },
  );
}

/**
 * @param {t.TestCase} tc
 */
void testMapHavingIterableAsConstructorParamTests(t.TestCase tc) {
  final _data = init(tc, users: 1);
  final map0 = _data.users[0].map;

  final m1 = Y.YMap({"number": 1, "string": "hello"}.entries);
  map0.set("m1", m1);
  t.check(m1.get("number") == 1);
  t.check(m1.get("string") == "hello");

  final m2 = Y.YMap([
    MapEntry("object", {"x": 1}),
    MapEntry("boolean", true),
  ]);
  map0.set("m2", m2);
  t.check((m2.get("object") as Map<String, dynamic>)["x"] == 1);
  t.check(m2.get("boolean") == true);

  final m3 = Y.YMap([...m1.entries(), ...m2.entries()]);
  map0.set("m3", m3);
  t.check(m3.get("number") == 1);
  t.check(m3.get("string") == "hello");
  t.check((m3.get("object") as Map<String, dynamic>)["x"] == 1);
  t.check(m3.get("boolean") == true);
}

/**
 * @param {t.TestCase} tc
 */
void testBasicMapTests(t.TestCase tc) {
  final _data = init(tc, users: 3);
  final map0 = _data.users[0].map;
  final map1 = _data.users[1].map;
  final map2 = _data.users[2].map;

  _data.users[2].instance.disconnect();

  map0.set("number", 1);
  map0.set("string", "hello Y");
  map0.set("object", {
    "key": {"key2": "value"}
  });
  map0.set("y-map", Y.YMap());
  map0.set("boolean1", true);
  map0.set("boolean0", false);
  final map = map0.get("y-map");
  map.set("y-array", Y.YArray());
  final array = map.get("y-array");
  array.insert(0, [0]);
  array.insert(0, [-1]);

  t.check(map0.get("number") == 1, "client 0 computed the change (number)");
  t.check(
      map0.get("string") == "hello Y", "client 0 computed the change (string)");
  t.check(
      map0.get("boolean0") == false, "client 0 computed the change (boolean)");
  t.check(
      map0.get("boolean1") == true, "client 0 computed the change (boolean)");
  t.compare(
      map0.get("object"),
      {
        "key": {"key2": "value"}
      },
      "client 0 computed the change (object)");
  t.check(map0.get("y-map").get("y-array").get(0) == -1,
      "client 0 computed the change (type)");
  t.check(map0.size == 6, "client 0 map has correct size");

  _data.users[2].instance.connect();
  _data.testConnector.flushAllMessages();

  t.check(map1.get("number") == 1, "client 1 received the update (number)");
  t.check(
      map1.get("string") == "hello Y", "client 1 received the update (string)");
  t.check(
      map1.get("boolean0") == false, "client 1 computed the change (boolean)");
  t.check(
      map1.get("boolean1") == true, "client 1 computed the change (boolean)");
  t.compare(
      map1.get("object"),
      {
        "key": {"key2": "value"}
      },
      "client 1 received the update (object)");
  t.check(map1.get("y-map").get("y-array").get(0) == -1,
      "client 1 received the update (type)");
  t.check(map1.size == 6, "client 1 map has correct size");

  // compare disconnected user
  t.check(map2.get("number") == 1,
      "client 2 received the update (number) - was disconnected");
  t.check(map2.get("string") == "hello Y",
      "client 2 received the update (string) - was disconnected");
  t.check(
      map2.get("boolean0") == false, "client 2 computed the change (boolean)");
  t.check(
      map2.get("boolean1") == true, "client 2 computed the change (boolean)");
  t.compare(
      map2.get("object"),
      {
        "key": {"key2": "value"}
      },
      "client 2 received the update (object) - was disconnected");
  t.check(map2.get("y-map").get("y-array").get(0) == -1,
      "client 2 received the update (type) - was disconnected");
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testGetAndSetOfMapProperty(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final map0 = _data.users[0].map;
  map0.set("stuff", "stuffy");
  map0.set("undefined", null);
  map0.set("null", null);
  t.compare(map0.get("stuff"), "stuffy");

  _data.testConnector.flushAllMessages();

  for (final user in _data.userInstances) {
    final u = user.getMap("map");
    t.compare(u.get("stuff"), "stuffy");
    t.check(u.get("undefined") == null, "undefined");
    t.compare(u.get("null"), null, "null");
  }
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testYmapSetsYmap(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final map0 = _data.users[0].map;

  final map = map0.set("Map", Y.YMap());
  t.check(map0.get("Map") == map);
  map.set("one", 1);
  t.compare(map.get("one"), 1);
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testYmapSetsYarray(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final map0 = _data.users[0].map;

  final array = map0.set("Array", Y.YArray());
  t.check(array == map0.get("Array"));
  array.insert(0, [1, 2, 3]);
  // @ts-ignore
  t.compare(map0.toJSON(), {
    "Array": [1, 2, 3]
  });
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testGetAndSetOfMapPropertySyncs(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final map0 = _data.users[0].map;

  map0.set("stuff", "stuffy");
  t.compare(map0.get("stuff"), "stuffy");
  _data.testConnector.flushAllMessages();
  for (final user in _data.userInstances) {
    var u = user.getMap("map");
    t.compare(u.get("stuff"), "stuffy");
  }
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testGetAndSetOfMapPropertyWithConflict(t.TestCase tc) {
  final _data = init(tc, users: 3);

  _data.users[0].map.set("stuff", "c0");
  _data.users[1].map.set("stuff", "c1");
  _data.testConnector.flushAllMessages();
  for (final user in _data.userInstances) {
    var u = user.getMap("map");
    t.compare(u.get("stuff"), "c1");
  }
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testSizeAndDeleteOfMapProperty(t.TestCase tc) {
  final _data = init(tc, users: 1);
  final map0 = _data.users[0].map;

  map0.set("stuff", "c0");
  map0.set("otherstuff", "c1");
  t.check(map0.size == 2, "map size is ${map0.size} expected 2");
  map0.delete("stuff");
  t.check(map0.size == 1, "map size after delete is ${map0.size}, expected 1");
  map0.delete("otherstuff");
  t.check(map0.size == 0, "map size after delete is ${map0.size}, expected 0");
}

/**
 * @param {t.TestCase} tc
 */
void testGetAndSetAndDeleteOfMapProperty(t.TestCase tc) {
  final _data = init(tc, users: 3);
  _data.users[0].map.set("stuff", "c0");
  _data.users[1].map.set("stuff", "c1");
  _data.users[1].map.delete("stuff");
  _data.testConnector.flushAllMessages();
  for (final user in _data.userInstances) {
    var u = user.getMap("map");
    t.check(u.get("stuff") == null);
  }
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testGetAndSetOfMapPropertyWithThreeConflicts(t.TestCase tc) {
  final _data = init(tc, users: 3);
  _data.users[0].map.set("stuff", "c0");
  _data.users[1].map.set("stuff", "c1");
  _data.users[1].map.set("stuff", "c2");
  _data.users[2].map.set("stuff", "c3");
  _data.testConnector.flushAllMessages();
  for (final user in _data.userInstances) {
    var u = user.getMap("map");
    t.compare(u.get("stuff"), "c3");
  }
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testGetAndSetAndDeleteOfMapPropertyWithThreeConflicts(t.TestCase tc) {
  final _data = init(tc, users: 4);
  final map0 = _data.users[0].map;
  final map1 = _data.users[1].map;
  final map2 = _data.users[2].map;
  final map3 = _data.users[3].map;

  map0.set("stuff", "c0");
  map1.set("stuff", "c1");
  map1.set("stuff", "c2");
  map2.set("stuff", "c3");
  _data.testConnector.flushAllMessages();
  map0.set("stuff", "deleteme");
  map1.set("stuff", "c1");
  map2.set("stuff", "c2");
  map3.set("stuff", "c3");
  map3.delete("stuff");
  _data.testConnector.flushAllMessages();
  for (final user in _data.userInstances) {
    var u = user.getMap("map");
    t.check(u.get("stuff") == null);
  }
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testObserveDeepProperties(t.TestCase tc) {
  final _data = init(tc, users: 4);
  final _map1 = _data.users[1].map.set("map", Y.YMap());
  var calls = 0;
  Y.ID? dmapid;
  _data.users[1].map.observeDeep((events, _) {
    events.forEach((event) {
      calls++;
      // @ts-ignore
      t.check((event as Y.YMapEvent).keysChanged.contains("deepmap"));
      t.check(event.path.length == 1);
      t.check(event.path[0] == "map");
      // @ts-ignore
      dmapid =
          ((event.target as Y.YMap).get("deepmap") as Y.YMap).innerItem!.id;
    });
  });
  _data.testConnector.flushAllMessages();
  final _map3 = _data.users[3].map.get("map");
  _map3.set("deepmap", Y.YMap());
  _data.testConnector.flushAllMessages();
  final _map2 = _data.users[2].map.get("map");
  _map2.set("deepmap", Y.YMap());
  _data.testConnector.flushAllMessages();
  final dmap1 = _map1.get("deepmap") as Y.YMap;
  final dmap2 = _map2.get("deepmap") as Y.YMap;
  final dmap3 = _map3.get("deepmap") as Y.YMap;
  t.check(calls > 0);
  t.check(Y.compareIDs(dmap1.innerItem!.id, dmap2.innerItem!.id));
  t.check(Y.compareIDs(dmap1.innerItem!.id, dmap3.innerItem!.id));
  // @ts-ignore we want the possibility of dmapid being undefined
  t.check(Y.compareIDs(dmap1.innerItem!.id, dmapid));
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testObserversUsingObservedeep(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final map0 = _data.users[0].map;

  /**
   * @type {Array<Array<string|number>>}
   */
  final pathes = [];
  var calls = 0;
  map0.observeDeep((events, _) {
    events.forEach((event) {
      pathes.add(event.path);
    });
    calls++;
  });
  map0.set("map", Y.YMap());
  map0.get("map").set("array", Y.YArray());
  map0.get("map").get("array").insert(0, ["content"]);
  t.check(calls == 3);
  t.compare(pathes, [
    [],
    ["map"],
    ["map", "array"]
  ]);
  compare(_data.userInstances);
}

// TODO: Test events in Y.YMap
/**
 * @param {Object<string,any>} is
 * @param {Object<string,any>} should
 */
void compareEvent(Map<String, Object?> iss, Map<String, Object?> should) {
  for (var key in should.keys) {
    t.compare(should[key], iss[key]);
  }
}

/**
 * @param {t.TestCase} tc
 */
void testThrowsAddAndUpdateAndDeleteEvents(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final map0 = _data.users[0].map;
  /**
   * @type {Object<string,any>}
   */
  YMapEvent? event;
  Map<String, Object?> _eventAsMap() {
    return {
      "target": event!.target,
      "keysChanged": event!.keysChanged,
    };
  }

  map0.observe((e, _) {
    event = e; // just put it on event, should be thrown synchronously anyway
  });
  map0.set("stuff", 4);
  t.check(event != null);
  compareEvent(_eventAsMap(), {
    "target": map0,
    "keysChanged": {"stuff"},
  });
  event = null;

  // update, oldValue is in contents
  map0.set("stuff", Y.YArray());
  t.check(event != null);
  compareEvent(_eventAsMap(), {
    "target": map0,
    "keysChanged": {"stuff"},
  });
  event = null;

  // update, oldValue is in opContents
  map0.set("stuff", 5);
  t.check(event != null);
  // delete
  map0.delete("stuff");
  compareEvent(_eventAsMap(), {
    "keysChanged": {"stuff"},
    "target": map0,
  });
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testChangeEvent(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final map0 = _data.users[0].map;
  final users = _data.userInstances;
  /**
   * @type {any}
   */
  Y.YChanges? changes;
  /**
   * @type {any}
   */
  Y.YChange? keyChange;
  map0.observe((e, _) {
    changes = e.changes;
  });
  map0.set("a", 1);
  t.check(changes != null);
  keyChange = changes!.keys.get("a");
  t.check(keyChange != null &&
      keyChange.action == Y.YChangeType.add &&
      keyChange.oldValue == null);
  changes = null;

  map0.set("a", 2);
  t.check(changes != null);
  keyChange = changes!.keys.get("a");
  t.check(keyChange != null &&
      keyChange.action == Y.YChangeType.update &&
      keyChange.oldValue == 1);
  changes = null;

  users[0].transact((_) {
    map0.set("a", 3);
    map0.set("a", 4);
  });
  t.check(changes != null);
  keyChange = changes!.keys.get("a");
  t.check(keyChange != null &&
      keyChange.action == Y.YChangeType.update &&
      keyChange.oldValue == 2);
  changes = null;

  users[0].transact((_) {
    map0.set("b", 1);
    map0.set("b", 2);
  });
  t.check(changes != null);
  keyChange = changes!.keys.get("b");
  t.check(keyChange != null &&
      keyChange.action == Y.YChangeType.add &&
      keyChange.oldValue == null);
  changes = null;

  users[0].transact((_) {
    map0.set("c", 1);
    map0.delete("c");
  });
  t.check(changes != null);
  t.check(changes!.keys.length == 0);
  changes = null;

  users[0].transact((_) {
    map0.set("d", 1);
    map0.set("d", 2);
  });
  t.check(changes != null);
  keyChange = changes!.keys.get("d");
  t.check(keyChange != null &&
      keyChange.action == Y.YChangeType.add &&
      keyChange.oldValue == null);
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testYmapEventExceptionsShouldCompleteTransaction(t.TestCase tc) {
  final doc = Y.Doc();
  final map = doc.getMap("map");

  var updateCalled = false;
  var throwingObserverCalled = false;
  var throwingDeepObserverCalled = false;
  doc.on("update", (_) {
    updateCalled = true;
  });

  void throwingObserver(_, __) {
    throwingObserverCalled = true;
    throw Exception("Failure");
  }

  void throwingDeepObserver(_, __) {
    throwingDeepObserverCalled = true;
    throw Exception("Failure");
  }

  map.observe(throwingObserver);
  map.observeDeep(throwingDeepObserver);

  t.fails(() {
    map.set("y", "2");
  });

  t.check(updateCalled);
  t.check(throwingObserverCalled);
  t.check(throwingDeepObserverCalled);

  // check if it works again
  updateCalled = false;
  throwingObserverCalled = false;
  throwingDeepObserverCalled = false;
  t.fails(() {
    map.set("z", "3");
  });

  t.check(updateCalled);
  t.check(throwingObserverCalled);
  t.check(throwingDeepObserverCalled);

  t.check(map.get("z") == "3");
}

// /**
//  * @param {t.TestCase} tc
//  */
// void testYmapEventHasCorrectValueWhenSettingAPrimitive(t.TestCase tc) {
//   final _data = init(tc, users: 3);
//   final map0 = _data.users[0].map;
//   /**
//    * @type {Object<string,any>}
//    */
//   Y.YMapEvent? event;
//   map0.observe((e, _) {
//     event = e;
//   });
//   map0.set("stuff", 2);
//   t.compare(event!.value, (event!.target as Y.YMap).get(event!.name));
//   compare(_data.userInstances);
// }

// /**
//  * @param {t.TestCase} tc
//  */
// void testYmapEventHasCorrectValueWhenSettingAPrimitiveFromOtherUser(
//     t.TestCase tc) {
//   final _data = init(tc, users: 3);
//   /**
//    * @type {Object<string,any>}
//    */
//   YMapEvent? event;
//   _data.users[0].map.observe((e, _) {
//     event = e;
//   });
//   _data.users[1].map.set("stuff", 2);
//   _data.testConnector.flushAllMessages();
//   t.check(event != null);
//   t.compare(event!.value, (event!.target as Y.YMap).get(event.name));
//   compare(_data.userInstances);
// }

/**
 * @type {Array<function(Doc,prng.PRNG):void>}
 */
final mapTransactions = <void Function(Y.Doc, Random, dynamic)>[
  (user, gen, _) {
    final key = prng.oneOf(gen, ["one", "two"]);
    final value = prng.utf16String(gen);
    user.getMap("map").set(key, value);
  },
  (user, gen, _) {
    final key = prng.oneOf(gen, ["one", "two"]);
    final type = prng.oneOf(gen, [Y.YArray(), Y.YMap()]);
    user.getMap("map").set(key, type);
    if (type is Y.YArray) {
      type.insert(0, [1, 2, 3, 4]);
    } else if (type is Y.YMap) {
      type.set("deepkey", "deepvalue");
    }
  },
  (user, gen, _) {
    final key = prng.oneOf(gen, ["one", "two"]);
    user.getMap("map").delete(key);
  },
];

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests10(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 3);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests40(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 40);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests42(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 42);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests43(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 43);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests44(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 44);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests45(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 45);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests46(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 46);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests300(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 300);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests400(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 400);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests500(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 500);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests600(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 600);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests1000(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 1000);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests1800(t.TestCase tc) {
  applyRandomTests(tc, mapTransactions, 1800);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests5000(t.TestCase tc) {
  // TODO:
  // t.skip(!t.production);
  applyRandomTests(tc, mapTransactions, 5000);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests10000(t.TestCase tc) {
  // TODO:
  // t.skip(!t.production);
  applyRandomTests(tc, mapTransactions, 10000);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGeneratingYmapTests100000(t.TestCase tc) {
  // TODO:
  // t.skip(!t.production);
  applyRandomTests(tc, mapTransactions, 100000);
}
