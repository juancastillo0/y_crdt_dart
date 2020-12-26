// import * as t from "lib0/testing.js";
// import * as prng from "lib0/prng.js";
// import * as encoding from "lib0/encoding.js";
// import * as decoding from "lib0/decoding.js";
// import * as syncProtocol from "y-protocols/sync.js";
// import * as object from "lib0/object.js";
// import * as Y from "../src/internals.js";
// export * from "../src/internals.js";

// if (typeof window != "undefined") {
//   // @ts-ignore
//   window.Y = Y; // eslint-disable-line
// }

import 'dart:math' show Random;
import 'dart:typed_data';
import 'package:y_crdt/src/lib0/decoding.dart' as decoding;
import 'package:y_crdt/src/lib0/encoding.dart' as encoding;
import 'package:y_crdt/src/lib0/prng.dart' as prng;
import 'package:y_crdt/y_crdt.dart' as Y;
import 'package:y_crdt/src/external/protocol_sync.dart' as syncProtocol;
import 'package:y_crdt/src/lib0/testing.dart' as t;

/**
 * @param {TestYInstance} y // publish message created by `y` to all other online clients
 * @param {Uint8Array} m
 */
void broadcastMessage(TestYInstance y, Uint8List m) {
  if (y.tc.onlineConns.contains(y)) {
    y.tc.onlineConns.forEach((remoteYInstance) {
      if (remoteYInstance != y) {
        remoteYInstance._receive(m, y);
      }
    });
  }
}

class TestYInstance extends Y.Doc {
  /**
   * @param {TestConnector} testConnector
   * @param {number} clientID
   */
  TestYInstance(this.tc, this.userID) {
    tc.allConns.add(this);
    // set up observe on local model
    this.on("update",
        /** @param {Uint8Array} update @param {any} origin */ (params) {
      final update = params[0] as Uint8List;
      final origin = params[1];
      if (origin != tc) {
        final encoder = encoding.createEncoder();
        syncProtocol.writeUpdate(encoder, update);
        broadcastMessage(this, encoding.toUint8Array(encoder));
      }
    });
    this.connect();
  }

  int userID; // overwriting clientID
  /**
   * @type {TestConnector}
   */
  TestConnector tc;
  /**
   * @type {Map<TestYInstance, Array<Uint8Array>>}
   */
  var receiving = <TestYInstance, List<Uint8List>>{};

  /**
   * Disconnect from TestConnector.
   */
  void disconnect() {
    this.receiving = {};
    this.tc.onlineConns.remove(this);
  }

  /**
   * Append yourself to the list of known Y instances in testconnector.
   * Also initiate sync with all clients.
   */
  void connect() {
    if (!this.tc.onlineConns.contains(this)) {
      this.tc.onlineConns.add(this);
      final encoder = encoding.createEncoder();
      syncProtocol.writeSyncStep1(encoder, this);
      // publish SyncStep1
      broadcastMessage(this, encoding.toUint8Array(encoder));
      this.tc.onlineConns.forEach((remoteYInstance) {
        if (remoteYInstance != this) {
          // remote instance sends instance to this instance
          final encoder = encoding.createEncoder();
          syncProtocol.writeSyncStep1(encoder, remoteYInstance);
          this._receive(encoding.toUint8Array(encoder), remoteYInstance);
        }
      });
    }
  }

  /**
   * Receive a message from another client. This message is only appended to the list of receiving messages.
   * TestConnector decides when this client actually reads this message.
   *
   * @param {Uint8Array} message
   * @param {TestYInstance} remoteClient
   */
  void _receive(Uint8List message, TestYInstance remoteClient) {
    var messages = this.receiving.get(remoteClient);
    if (messages == null) {
      messages = [];
      this.receiving.set(remoteClient, messages);
    }
    messages.add(message);
  }
}

/**
 * Keeps track of TestYInstances.
 *
 * The TestYInstances add/remove themselves from the list of connections maiained in this object.
 * I think it makes sense. Deal with it.
 */
class TestConnector {
  /**
   * @param {prng.PRNG} gen
   */
  TestConnector(this.gen);

  /**
   * @type {Set<TestYInstance>}
   */
  final allConns = <TestYInstance>{};
  /**
   * @type {Set<TestYInstance>}
   */
  final onlineConns = <TestYInstance>{};
  /**
   * @type {prng.PRNG}
   */
  Random gen;

  /**
   * Create a new Y instance and add it to the list of connections
   * @param {number} clientID
   */
  TestYInstance createY(int clientID) {
    return TestYInstance(this, clientID);
  }

  /**
   * Choose random connection and flush a random message from a random sender.
   *
   * If this function was unable to flush a message, because there are no more messages to flush, it returns false. true otherwise.
   * @return {boolean}
   */
  bool flushRandomMessage() {
    final conns =
        this.onlineConns.where((conn) => conn.receiving.length > 0).toList();
    if (conns.length > 0) {
      final receiver = prng.oneOf(gen, conns);
      final entry = prng.oneOf(gen, receiver.receiving.entries.toList());
      final sender = entry.key;
      final messages = entry.value;

      final m = messages.removeAt(0);
      if (messages.length == 0) {
        receiver.receiving.remove(sender);
      }
      if (m == null) {
        return this.flushRandomMessage();
      }
      final encoder = encoding.createEncoder();
      // console.log('receive (' + sender.userID + '->' + receiver.userID + '):\n', syncProtocol.stringifySyncMessage(decoding.createDecoder(m), receiver))
      // do not publish data created when this function is executed (could be ss2 or update message)
      syncProtocol.readSyncMessage(
          decoding.createDecoder(m), encoder, receiver, receiver.tc);
      if (encoding.length(encoder) > 0) {
        // send reply message
        sender._receive(encoding.toUint8Array(encoder), receiver);
      }
      return true;
    }
    return false;
  }

  /**
   * @return {boolean} True iff this function actually flushed something
   */
  bool flushAllMessages() {
    var didSomething = false;
    while (this.flushRandomMessage()) {
      didSomething = true;
    }
    return didSomething;
  }

  void reconnectAll() {
    this.allConns.forEach((conn) => conn.connect());
  }

  void disconnectAll() {
    this.allConns.forEach((conn) => conn.disconnect());
  }

  void syncAll() {
    this.reconnectAll();
    this.flushAllMessages();
  }

  /**
   * @return {boolean} Whether it was possible to disconnect a randon connection.
   */
  bool disconnectRandom() {
    if (this.onlineConns.length == 0) {
      return false;
    }
    prng.oneOf(this.gen, this.onlineConns.toList()).disconnect();
    return true;
  }

  /**
   * @return {boolean} Whether it was possible to reconnect a random connection.
   */
  bool reconnectRandom() {
    /**
     * @type {Array<TestYInstance>}
     */
    final reconnectable = [];
    this.allConns.forEach((conn) {
      if (!this.onlineConns.contains(conn)) {
        reconnectable.add(conn);
      }
    });
    if (reconnectable.length == 0) {
      return false;
    }
    prng.oneOf(this.gen, reconnectable).connect();
    return true;
  }
}

/**
 * @template T
 * @param {t.TestCase} tc
 * @param {{users?:number}} conf
 * @param {InitTestObjectCallback<T>} [initTestObject]
 * @return {{testObjects:Array<any>,testConnector:TestConnector,users:Array<TestYInstance>,array0:Y.YArray<any>,array1:Y.YArray<any>,array2:Y.YArray<any>,map0:Y.YMap<any>,map1:Y.YMap<any>,map2:Y.YMap<any>,map3:Y.YMap<any>,text0:Y.YText,text1:Y.YText,text2:Y.YText,xml0:Y.YXmlElement,xml1:Y.YXmlElement,xml2:Y.YXmlElement}}
 */
_TestData<T> init<T>(
  t.TestCase tc, {
  int users = 5,
  T Function(TestYInstance)? initTestObject,
}) {
  final gen = tc.prng;
  // choose an encoding approach at random
  if (gen.nextBool()) {
    Y.useV2Encoding();
  } else {
    Y.useV1Encoding();
  }

  final _testConnector = TestConnector(gen);
  final _users = <_UserTestData>[];

  for (var i = 0; i < users; i++) {
    final y = _testConnector.createY(i);
    y.clientID = i;

    _users.add(_UserTestData(
      array: y.getArray("array"),
      instance: y,
      map: y.getMap("map"),
      text: y.getText("text"),
      // xml: y.get("xml", Y.YXmlElement),
    ));
    // result["array$i"] = y.getArray("array");
    // result["map$i"] = y.getMap("map");
    // result["xml$i"] = y.get("xml", Y.YXmlElement);
    // result["text$i"] = y.getText("text");
  }
  _testConnector.syncAll();
  Y.useV1Encoding();

  return _TestData<T>(
    users: _users,
    testConnector: _testConnector,
    testObjects: _users
        .map((u) => u.instance)
        .map(initTestObject ?? ((_) => null))
        .toList() as List<T>,
  );
}

class _TestData<T> {
  final List<T> testObjects;
  final TestConnector testConnector;
  final List<_UserTestData> users;

  List<TestYInstance> get userInstances =>
      users.map((e) => e.instance).toList();

  _TestData({
    required this.testObjects,
    required this.testConnector,
    required this.users,
  });
}

class _UserTestData {
  final TestYInstance instance;
  final Y.YArray<dynamic> array;
  final Y.YMap<dynamic> map;
  final Y.YText text;
  // final Y.YXmlElement xml;

  const _UserTestData({
    required this.instance,
    required this.array,
    required this.map,
    required this.text,
    // required this.xml,
  });
}

/**
 * 1. reconnect and flush all
 * 2. user 0 gc
 * 3. get type content
 * 4. disconnect & reconnect all (so gc is propagated)
 * 5. compare os, ds, ss
 *
 * @param {Array<TestYInstance>} users
 */
void compare(List<TestYInstance> users) {
  users.forEach((u) => u.connect());
  while (users[0].tc.flushAllMessages()) {}
  final userArrayValues =
      users.map((u) => u.getArray("array").toJSON()).toList();
  final userMapValues = users.map((u) => u.getMap("map").toJSON()).toList();
  // final userXmlValues = users.map((u) =>
  //   u.get("xml", Y.YXmlElement).toString()
  // ).toList();
  final userTextValues = users.map((u) => u.getText("text").toDelta()).toList();
  for (final u in users) {
    t.check(u.store.pendingDeleteReaders.length == 0);
    t.check(u.store.pendingStack.length == 0);
    t.check(u.store.pendingClientsStructRefs.length == 0);
  }
  // Test Array iterator
  t.compare(users[0].getArray("array").toArray(),
      List.from(users[0].getArray("array")));
  // Test Map iterator
  final ymapkeys = users[0].getMap("map").keys().toList();
  t.check(ymapkeys.length == userMapValues[0].length);
  ymapkeys.forEach((key) => t.check(userMapValues[0].containsKey(key)));
  /**
   * @type {Object<string,any>}
   */
  final mapRes = {};
  for (final entry in users[0].getMap("map").entries()) {
    mapRes[entry.key] =
        entry.value is Y.AbstractType ? entry.value.toJSON() : entry.value;
  }
  t.compare(userMapValues[0], mapRes);
  // Compare all users
  for (var i = 0; i < users.length - 1; i++) {
    t.compare(userArrayValues[i].length, users[i].getArray("array").length);
    t.compare(userArrayValues[i], userArrayValues[i + 1]);
    t.compare(userMapValues[i], userMapValues[i + 1]);
    // t.compare(userXmlValues[i], userXmlValues[i + 1]);
    t.compare(
        userTextValues[i]
            .map((a) => a["insert"] is String ? a["insert"] : " ")
            .join("")
            .length,
        users[i].getText("text").length);
    t.compare(userTextValues[i], userTextValues[i + 1]);
    t.compare(
        Y.getStateVector(users[i].store), Y.getStateVector(users[i + 1].store));
    compareDS(Y.createDeleteSetFromStructStore(users[i].store),
        Y.createDeleteSetFromStructStore(users[i + 1].store));
    compareStructStores(users[i].store, users[i + 1].store);
  }
  users.map((u) => u.destroy());
}

/**
 * @param {Y.Item?} a
 * @param {Y.Item?} b
 * @return {boolean}
 */
bool compareItemIDs(Y.Item? a, Y.Item? b) =>
    a == b || (a != null && b != null && Y.compareIDs(a.id, b.id));

/**
 * @param {Y.StructStore} ss1
 * @param {Y.StructStore} ss2
 */
void compareStructStores(Y.StructStore ss1, Y.StructStore ss2) {
  t.check(ss1.clients.length == ss2.clients.length);
  for (final entry in ss1.clients.entries) {
    final structs2 = /** @type {Array<Y.AbstractStruct>} */ (ss2.clients
        .get(entry.key));
    final structs1 = entry.value;
    t.check(structs2 != null && structs1.length == structs2.length);
    for (var i = 0; i < structs1.length; i++) {
      final s1 = structs1[i];
      final s2 = structs2![i];
      // checks for abstract struct
      if (s1.runtimeType != s2.runtimeType ||
          !Y.compareIDs(s1.id, s2.id) ||
          s1.deleted != s2.deleted ||
          // @ts-ignore
          s1.length != s2.length) {
        t.fail("Structs dont match");
      }
      if (s1 is Y.Item) {
        if (!(s2 is Y.Item) ||
            !((s1.left == null && s2.left == null) ||
                (s1.left != null &&
                    s2.left != null &&
                    Y.compareIDs(s1.left!.lastId, s2.left!.lastId))) ||
            !compareItemIDs(s1.right, s2.right) ||
            !Y.compareIDs(s1.origin, s2.origin) ||
            !Y.compareIDs(s1.rightOrigin, s2.rightOrigin) ||
            s1.parentSub != s2.parentSub) {
          return t.fail("Items dont match");
        }
        // make sure that items are connected correctly
        t.check(s1.left == null || s1.left!.right == s1);
        t.check(s1.right == null || s1.right!.left == s1);
        t.check(s2.left == null || s2.left!.right == s2);
        t.check(s2.right == null || s2.right!.left == s2);
      }
    }
  }
}

/**
 * @param {Y.DeleteSet} ds1
 * @param {Y.DeleteSet} ds2
 */
void compareDS(Y.DeleteSet ds1, Y.DeleteSet ds2) {
  t.check(ds1.clients.length == ds2.clients.length);
  ds1.clients.forEach((client, deleteItems1) {
    final deleteItems2 = /** @type {Array<Y.DeleteItem>} */ (ds2.clients
        .get(client));
    t.check(deleteItems2 != null && deleteItems1.length == deleteItems2.length);
    for (var i = 0; i < deleteItems1.length; i++) {
      final di1 = deleteItems1[i];
      final di2 = deleteItems2![i];
      if (di1.clock != di2.clock || di1.len != di2.len) {
        t.fail("DeleteSets dont match");
      }
    }
  });
}

/**
 * @template T
 * @callback InitTestObjectCallback
 * @param {TestYInstance} y
 * @return {T}
 */

/**
 * @template T
 * @param {t.TestCase} tc
 * @param {Array<function(Y.Doc,prng.PRNG,T):void>} mods
 * @param {number} iterations
 * @param {InitTestObjectCallback<T>} [initTestObject]
 */
_TestData applyRandomTests<T>(
  t.TestCase tc,
  List<void Function(Y.Doc, Random, T)> mods,
  int iterations, [
  T Function(TestYInstance)? initTestObject,
]) {
  final gen = tc.prng;
  final result = init<T>(tc, users: 5, initTestObject: initTestObject);
  final testConnector = result.testConnector;
  final users = result.users;
  for (var i = 0; i < iterations; i++) {
    if (prng.int32(gen, 0, 100) <= 2) {
      // 2% chance to disconnect/reconnect a random user
      if (gen.nextBool()) {
        testConnector.disconnectRandom();
      } else {
        testConnector.reconnectRandom();
      }
    } else if (prng.int32(gen, 0, 100) <= 1) {
      // 1% chance to flush all
      testConnector.flushAllMessages();
    } else if (prng.int32(gen, 0, 100) <= 50) {
      // 50% chance to flush a random message
      testConnector.flushRandomMessage();
    }
    final user = prng.int32(gen, 0, users.length - 1);
    final test = prng.oneOf(gen, mods);
    test(users[user].instance, gen, result.testObjects[user]);
  }
  compare(users.map((e) => e.instance).toList());
  return result;
}
