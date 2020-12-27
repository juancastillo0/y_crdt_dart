// import * as t from "lib0/testing.js";
// import * as promise from "lib0/promise.js";

// import {
//   contentRefs,
//   readContentBinary,
//   readContentDeleted,
//   readContentString,
//   readContentJSON,
//   readContentEmbed,
//   readContentType,
//   readContentFormat,
//   readContentAny,
//   readContentDoc,
//   Doc,
//   PermanentUserData,
//   encodeStateAsUpdate,
//   applyUpdate,
// } from "../src/internals.js";
import 'package:y_crdt/src/lib0/testing.dart' as t;
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/y_crdt.dart';

void main() async {
  await t.runTests(
    {
      "encoding": {
        "testStructReferences": testStructReferences,
        "testPermanentUserData": testPermanentUserData,
      }
    },
  );
}

/**
 * @param {t.TestCase} tc
 */
void testStructReferences(t.TestCase tc) {
  t.check(contentRefs.length == 10);
  t.check(contentRefs[1] == readContentDeleted);
  t.check(contentRefs[2] == readContentJSON); // TODO: deprecate content json?
  t.check(contentRefs[3] == readContentBinary);
  t.check(contentRefs[4] == readContentString);
  t.check(contentRefs[5] == readContentEmbed);
  t.check(contentRefs[6] == readContentFormat);
  t.check(contentRefs[7] == readContentType);
  t.check(contentRefs[8] == readContentAny);
  t.check(contentRefs[9] == readContentDoc);
}

/**
 * There is some custom encoding/decoding happening in PermanentUserData.
 * This is why it landed here.
 *
 * @param {t.TestCase} tc
 */
Future<void> testPermanentUserData(t.TestCase tc) async {
  final ydoc1 = Doc();
  final ydoc2 = Doc();
  final pd1 = PermanentUserData(ydoc1);
  final pd2 = PermanentUserData(ydoc2);
  pd1.setUserMapping(ydoc1, ydoc1.clientID, "user a");
  pd2.setUserMapping(ydoc2, ydoc2.clientID, "user b");
  ydoc1.getText().insert(0, "xhi");
  ydoc1.getText().delete(0, 1);
  ydoc2.getText().insert(0, "hxxi");
  ydoc2.getText().delete(1, 2);
  await Future.delayed(Duration(milliseconds: 10));
  applyUpdate(ydoc2, encodeStateAsUpdate(ydoc1, null), null);
  applyUpdate(ydoc1, encodeStateAsUpdate(ydoc2, null), null);

  // now sync a third doc with same name as doc1 and then create PermanentUserData
  final ydoc3 = Doc();
  applyUpdate(ydoc3, encodeStateAsUpdate(ydoc1, null), null);
  final pd3 = PermanentUserData(ydoc3);
  pd3.setUserMapping(ydoc3, ydoc3.clientID, "user a");
}
