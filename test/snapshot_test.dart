// import { createDocFromSnapshot, Doc, snapshot, YMap } from "../src/internals";
// import * as t from "lib0/testing.js";
// import { init } from "./testHelper";

import 'package:y_crdt/src/y_crdt_base.dart';
import 'package:y_crdt/y_crdt.dart'
    show Doc, snapshot, YMap, createDocFromSnapshot;
import 'package:y_crdt/src/lib0/testing.dart' as t;
import 'test_helper.dart' show init;

void main() async {
  await t.runTests(
    {
      "snapchot": {
        "testBasicRestoreSnapshot": testBasicRestoreSnapshot,
        "testEmptyRestoreSnapshot": testEmptyRestoreSnapshot,
        "testRestoreSnapshotWithSubType": testRestoreSnapshotWithSubType,
        "testRestoreDeletedItem1": testRestoreDeletedItem1,
        "testRestoreLeftItem": testRestoreLeftItem,
        "testDeletedItemsBase": testDeletedItemsBase,
        "testDeletedItems2": testDeletedItems2,
        "testDependentChanges": testDependentChanges,
      }
    },
  );
}

/**
 * @param {t.TestCase} tc
 */
void testBasicRestoreSnapshot(t.TestCase tc) {
  final doc = Doc(gc: false);
  doc.getArray("array").insert(0, ["hello"]);
  final snap = snapshot(doc);
  doc.getArray("array").insert(1, ["world"]);

  final docRestored = createDocFromSnapshot(doc, snap);

  t.compare(docRestored.getArray("array").toArray(), ["hello"]);
  t.compare(doc.getArray("array").toArray(), ["hello", "world"]);
}

/**
 * @param {t.TestCase} tc
 */
void testEmptyRestoreSnapshot(t.TestCase tc) {
  final doc = Doc(gc: false);
  final snap = snapshot(doc);
  snap.sv.set(9999, 0);
  doc.getArray().insert(0, ["world"]);

  final docRestored = createDocFromSnapshot(doc, snap);

  t.compare(docRestored.getArray().toArray(), []);
  t.compare(doc.getArray().toArray(), ["world"]);

  // now this snapshot reflects the latest state. It shoult still work.
  final snap2 = snapshot(doc);
  final docRestored2 = createDocFromSnapshot(doc, snap2);
  t.compare(docRestored2.getArray().toArray(), ["world"]);
}

/**
 * @param {t.TestCase} tc
 */
void testRestoreSnapshotWithSubType(t.TestCase tc) {
  final doc = Doc(gc: false);
  doc.getArray("array").insert(0, [YMap()]);
  final subMap = doc.getArray("array").get(0);
  subMap.set("key1", "value1");

  final snap = snapshot(doc);
  subMap.set("key2", "value2");

  final docRestored = createDocFromSnapshot(doc, snap);

  t.compare(docRestored.getArray("array").toJSON(), [
    {
      "key1": "value1",
    },
  ]);
  t.compare(doc.getArray("array").toJSON(), [
    {
      "key1": "value1",
      "key2": "value2",
    },
  ]);
}

/**
 * @param {t.TestCase} tc
 */
void testRestoreDeletedItem1(t.TestCase tc) {
  final doc = Doc(gc: false);
  doc.getArray("array").insert(0, ["item1", "item2"]);

  final snap = snapshot(doc);
  doc.getArray("array").delete(0);

  final docRestored = createDocFromSnapshot(doc, snap);

  t.compare(docRestored.getArray("array").toArray(), ["item1", "item2"]);
  t.compare(doc.getArray("array").toArray(), ["item2"]);
}

/**
 * @param {t.TestCase} tc
 */
void testRestoreLeftItem(t.TestCase tc) {
  final doc = Doc(gc: false);
  doc.getArray("array").insert(0, ["item1"]);
  doc.getMap("map").set("test", 1);
  doc.getArray("array").insert(0, ["item0"]);

  final snap = snapshot(doc);
  doc.getArray("array").delete(1);

  final docRestored = createDocFromSnapshot(doc, snap);

  t.compare(docRestored.getArray("array").toArray(), ["item0", "item1"]);
  t.compare(doc.getArray("array").toArray(), ["item0"]);
}

/**
 * @param {t.TestCase} tc
 */
void testDeletedItemsBase(t.TestCase tc) {
  final doc = Doc(gc: false);
  doc.getArray("array").insert(0, ["item1"]);
  doc.getArray("array").delete(0);
  final snap = snapshot(doc);
  doc.getArray("array").insert(0, ["item0"]);

  final docRestored = createDocFromSnapshot(doc, snap);

  t.compare(docRestored.getArray("array").toArray(), []);
  t.compare(doc.getArray("array").toArray(), ["item0"]);
}

/**
 * @param {t.TestCase} tc
 */
void testDeletedItems2(t.TestCase tc) {
  final doc = Doc(gc: false);
  doc.getArray("array").insert(0, ["item1", "item2", "item3"]);
  doc.getArray("array").delete(1);
  final snap = snapshot(doc);
  doc.getArray("array").insert(0, ["item0"]);

  final docRestored = createDocFromSnapshot(doc, snap);

  t.compare(docRestored.getArray("array").toArray(), ["item1", "item3"]);
  t.compare(doc.getArray("array").toArray(), ["item0", "item1", "item3"]);
}

/**
 * @param {t.TestCase} tc
 */
void testDependentChanges(t.TestCase tc) {
  final _data = init(tc, users: 2, gc: false);
  final array0 = _data.users[0].array;
  final array1 = _data.users[1].array;
  final testConnector = _data.testConnector;
  /**
   * @type Doc
   */
  final doc0 = array0.doc;
  /**
   * @type Doc
   */
  final doc1 = array1.doc;

  if (doc0 == null) {
    throw Exception("no document 0");
  }
  if (doc1 == null) {
    throw Exception("no document 1");
  }

  // doc0.gc = false;
  // doc1.gc = false;

  array0.insert(0, ["user1item1"]);
  testConnector.syncAll();
  array1.insert(1, ["user2item1"]);
  testConnector.syncAll();

  final snap = snapshot(array0.doc!);

  array0.insert(2, ["user1item2"]);
  testConnector.syncAll();
  array1.insert(3, ["user2item2"]);
  testConnector.syncAll();

  final docRestored0 = createDocFromSnapshot(array0.doc!, snap);
  t.compare(docRestored0.getArray("array").toArray(), [
    "user1item1",
    "user2item1",
  ]);

  final docRestored1 = createDocFromSnapshot(array1.doc!, snap);
  t.compare(docRestored1.getArray("array").toArray(), [
    "user1item1",
    "user2item1",
  ]);
}
