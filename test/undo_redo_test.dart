// import { init, compare, applyRandomTests, Doc } from './testHelper.js' // eslint-disable-line

// import {
//   UndoManager
// } from '../src/internals.js'

// import * as Y from '../src/index.js'
// import * as t from 'lib0/testing.js'

import 'package:y_crdt/src/utils/undo_manager.dart';
import 'package:y_crdt/y_crdt.dart' as Y;
import 'package:y_crdt/src/lib0/testing.dart' as t;
import 'test_helper.dart';

/**
 * @param {t.TestCase} tc
 */
void testUndoText(t.TestCase tc) {
  final _data = init(tc, users: 3);
  final testConnector = _data.testConnector;
  final text0 = _data.users[0].text;
  final text1 = _data.users[1].text;
  final undoManager = UndoManager([text0]);

  // items that are added & deleted in the same transaction won't be undo
  text0.insert(0, 'test');
  text0.delete(0, 4);
  undoManager.undo();
  t.check(text0.toString() == '');

  // follow redone items
  text0.insert(0, 'a');
  undoManager.stopCapturing();
  text0.delete(0, 1);
  undoManager.stopCapturing();
  undoManager.undo();
  t.check(text0.toString() == 'a');
  undoManager.undo();
  t.check(text0.toString() == '');

  text0.insert(0, 'abc');
  text1.insert(0, 'xyz');
  testConnector.syncAll();
  undoManager.undo();
  t.check(text0.toString() == 'xyz');
  undoManager.redo();
  t.check(text0.toString() == 'abcxyz');
  testConnector.syncAll();
  text1.delete(0, 1);
  testConnector.syncAll();
  undoManager.undo();
  t.check(text0.toString() == 'xyz');
  undoManager.redo();
  t.check(text0.toString() == 'bcxyz');
  // test marks
  text0.format(1, 3, {'bold': true});
  t.compare(text0.toDelta(), [
    {'insert': 'b'},
    {
      'insert': 'cxy',
      'attributes': {'bold': true}
    },
    {'insert': 'z'}
  ]);
  undoManager.undo();
  t.compare(text0.toDelta(), [
    {'insert': 'bcxyz'}
  ]);
  undoManager.redo();
  t.compare(text0.toDelta(), [
    {'insert': 'b'},
    {
      'insert': 'cxy',
      'attributes': {'bold': true}
    },
    {'insert': 'z'}
  ]);
}

/**
 * Test case to fix #241
 * @param {t.TestCase} tc
 */
void testDoubleUndo(t.TestCase tc) {
  final doc = Y.Doc();
  final text = doc.getText();
  text.insert(0, '1221');

  final manager = Y.UndoManager([text]);

  text.insert(2, '3');
  text.insert(3, '3');

  manager.undo();
  manager.undo();

  text.insert(2, '3');

  t.compareStrings(text.toString(), '12321');
}

/**
 * @param {t.TestCase} tc
 */
void testUndoMap(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final testConnector = _data.testConnector;
  final map0 = _data.users[0].map;
  final map1 = _data.users[1].map;
  map0.set('a', 0);
  final undoManager = UndoManager([map0]);
  map0.set('a', 1);
  undoManager.undo();
  t.check(map0.get('a') == 0);
  undoManager.redo();
  t.check(map0.get('a') == 1);
  // testing sub-types and if it can restore a whole type
  final subType = Y.YMap();
  map0.set('a', subType);
  subType.set('x', 42);
  t.compare(
      map0.toJSON(),
      /** @type {any} */ ({
        'a': {'x': 42}
      }));
  undoManager.undo();
  t.check(map0.get('a') == 1);
  undoManager.redo();
  t.compare(
      map0.toJSON(),
      /** @type {any} */ ({
        'a': {'x': 42}
      }));
  testConnector.syncAll();
  // if content is overwritten by another user, undo operations should be skipped
  map1.set('a', 44);
  testConnector.syncAll();
  undoManager.undo();
  t.check(map0.get('a') == 44);
  undoManager.redo();
  t.check(map0.get('a') == 44);

  // test setting value multiple times
  map0.set('b', 'initial');
  undoManager.stopCapturing();
  map0.set('b', 'val1');
  map0.set('b', 'val2');
  undoManager.stopCapturing();
  undoManager.undo();
  t.check(map0.get('b') == 'initial');
}

/**
 * @param {t.TestCase} tc
 */
void testUndoArray(t.TestCase tc) {
  final _data = init(tc, users: 3);
  final testConnector = _data.testConnector;
  final array0 = _data.users[0].array;
  final array1 = _data.users[1].array;
  final undoManager = UndoManager([array0]);
  array0.insert(0, [1, 2, 3]);
  array1.insert(0, [4, 5, 6]);
  testConnector.syncAll();
  t.compare(array0.toArray(), [1, 2, 3, 4, 5, 6]);
  undoManager.undo();
  t.compare(array0.toArray(), [4, 5, 6]);
  undoManager.redo();
  t.compare(array0.toArray(), [1, 2, 3, 4, 5, 6]);
  testConnector.syncAll();
  array1.delete(0, 1); // user1 deletes [1]
  testConnector.syncAll();
  undoManager.undo();
  t.compare(array0.toArray(), [4, 5, 6]);
  undoManager.redo();
  t.compare(array0.toArray(), [2, 3, 4, 5, 6]);
  array0.delete(0, 5);
  // test nested structure
  final ymap = Y.YMap();
  array0.insert(0, [ymap]);
  t.compare(array0.toJSON(), [{}]);
  undoManager.stopCapturing();
  ymap.set('a', 1);
  t.compare(array0.toJSON(), [
    {'a': 1}
  ]);
  undoManager.undo();
  t.compare(array0.toJSON(), [{}]);
  undoManager.undo();
  t.compare(array0.toJSON(), [2, 3, 4, 5, 6]);
  undoManager.redo();
  t.compare(array0.toJSON(), [{}]);
  undoManager.redo();
  t.compare(array0.toJSON(), [
    {'a': 1}
  ]);
  testConnector.syncAll();
  array1.get(0).set('b', 2);
  testConnector.syncAll();
  t.compare(array0.toJSON(), [
    {'a': 1, 'b': 2}
  ]);
  undoManager.undo();
  t.compare(array0.toJSON(), [
    {'b': 2}
  ]);
  undoManager.undo();
  t.compare(array0.toJSON(), [2, 3, 4, 5, 6]);
  undoManager.redo();
  t.compare(array0.toJSON(), [
    {'b': 2}
  ]);
  undoManager.redo();
  t.compare(array0.toJSON(), [
    {'a': 1, 'b': 2}
  ]);
}

/**
 * @param {t.TestCase} tc
 */
// TODO:
// void testUndoXml (t.TestCase tc) {
//   final { xml0 } = init(tc, { users: 3 });
//   final undoManager =  UndoManager(xml0);
//   final child =  Y.XmlElement('p');
//   xml0.insert(0, [child]);
//   final textchild =  Y.XmlText('content');
//   child.insert(0, [textchild]);
//   t.check(xml0.toString() == '<undefined><p>content</p></undefined>');
//   // format textchild and revert that change
//   undoManager.stopCapturing();
//   textchild.format(3, 4, { 'bold': {} });
//   t.check(xml0.toString() == '<undefined><p>con<bold>tent</bold></p></undefined>');
//   undoManager.undo();
//   t.check(xml0.toString() == '<undefined><p>content</p></undefined>');
//   undoManager.redo();
//   t.check(xml0.toString() == '<undefined><p>con<bold>tent</bold></p></undefined>');
//   xml0.delete(0, 1);
//   t.check(xml0.toString() == '<undefined></undefined>');
//   undoManager.undo();
//   t.check(xml0.toString() == '<undefined><p>con<bold>tent</bold></p></undefined>');
// }

/**
 * @param {t.TestCase} tc
 */
void testUndoEvents(t.TestCase tc) {
  final _data = init(tc, users: 3);
  final text0 = _data.users[0].text;
  final undoManager = UndoManager([text0]);
  int counter = 0;
  int receivedMetadata = -1;
  undoManager.on('stack-item-added', /** @param {any} event */ (event) {
    final params = event.first as Map<String, dynamic>;
    t.check(params['type'] != null);
    (params['stackItem'].meta as Map).set('test', counter++);
  });
  undoManager.on('stack-item-popped', /** @param {any} event */ (event) {
    final params = event.first as Map<String, dynamic>;
    t.check(params['type'] != null);
    receivedMetadata = (params['stackItem'].meta as Map).get('test') as int;
  });
  text0.insert(0, 'abc');
  undoManager.undo();
  t.check(receivedMetadata == 0);
  undoManager.redo();
  t.check(receivedMetadata == 1);
}

/**
 * @param {t.TestCase} tc
 */
void testTrackClass(t.TestCase tc) {
  final _data = init(tc, users: 3);
  final users = _data.users;
  final text0 = _data.users[0].text;
  // only track origins that are numbers
  final undoManager = UndoManager(
    [text0],
    trackedOrigins: const {TypeMatch<num>()},
  );
  users[0].instance.transact((_) {
    text0.insert(0, 'abc');
  }, 42);
  t.check(text0.toString() == 'abc');
  undoManager.undo();
  t.check(text0.toString() == '');
}

/**
 * @param {t.TestCase} tc
 */
void testTypeScope(t.TestCase tc) {
  final _data = init(tc, users: 3);
  final array0 = _data.users[0].array;
  // only track origins that are numbers
  final text0 = Y.YText();
  final text1 = Y.YText();
  array0.insert(0, [text0, text1]);
  final undoManager = UndoManager([text0]);
  final undoManagerBoth = UndoManager([text0, text1]);
  text1.insert(0, 'abc');
  t.check(undoManager.undoStack.length == 0);
  t.check(undoManagerBoth.undoStack.length == 1);
  t.check(text1.toString() == 'abc');
  undoManager.undo();
  t.check(text1.toString() == 'abc');
  undoManagerBoth.undo();
  t.check(text1.toString() == '');
}

/**
 * @param {t.TestCase} tc
 */
void testUndoDeleteFilter(t.TestCase tc) {
  /**
   * @type {Array<Y.Map<any>>}
   */
  final _data = init(tc, users: 3);
  final array0 = _data.users[0].array;
  final undoManager = UndoManager([array0],
      deleteFilter: (item) =>
          !(item is Y.Item) ||
          (item.content is Y.ContentType &&
              (item.content as Y.ContentType).type.innerMap.length == 0));
  final map0 = Y.YMap();
  map0.set('hi', 1);
  final map1 = Y.YMap();
  array0.insert(0, [map0, map1]);
  undoManager.undo();
  t.check(array0.length == 1);
  array0.get(0);
  t.check(array0.get(0).keys().length == 1);
}
