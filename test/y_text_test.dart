// import * as Y from "./testHelper.js";
// import * as t from "lib0/testing.js";
// import * as prng from "lib0/prng.js";
// import * as math from "lib0/math.js";

// const { init, compare } = Y;

import 'dart:math' show Random;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:y_crdt/src/lib0/prng.dart' as prng;
import 'package:y_crdt/src/types/y_text.dart';
// import 'package:y_crdt/y_crdt.dart' as Y;
import 'package:y_crdt/src/lib0/testing.dart' as t;
import 'package:y_crdt/y_crdt.dart' as Y;
import 'test_helper.dart';

void main() async {
  await t.runTests(
    {
      "text": {
        "testBasicInsertAndDelete": testBasicInsertAndDelete,
        "testBasicFormat": testBasicFormat,
        "testGetDeltaWithEmbeds": testGetDeltaWithEmbeds,
        "testSnapshot": testSnapshot,
        "testSnapshotDeleteAfter": testSnapshotDeleteAfter,
        "testToJson": testToJson,
        "testToDeltaEmbedAttributes": testToDeltaEmbedAttributes,
        "testToDeltaEmbedNoAttributes": testToDeltaEmbedNoAttributes,
        "testFormattingRemoved": testFormattingRemoved,
        "testFormattingRemovedInMidText": testFormattingRemovedInMidText,
        "testInsertAndDeleteAtRandomPositions":
            testInsertAndDeleteAtRandomPositions,
        "testAppendChars": testAppendChars,
        "testBestCase": testBestCase,
        "testLargeFragmentedDocument": testLargeFragmentedDocument,
        "testSplitSurrogateCharacter": testSplitSurrogateCharacter,
        "testRepeatGenerateTextChanges5": testRepeatGenerateTextChanges5,
        "testRepeatGenerateTextChanges30": testRepeatGenerateTextChanges30,
        "testRepeatGenerateTextChanges40": testRepeatGenerateTextChanges40,
        "testRepeatGenerateTextChanges50": testRepeatGenerateTextChanges50,
        "testRepeatGenerateTextChanges70": testRepeatGenerateTextChanges70,
        "testRepeatGenerateQuillChanges1": testRepeatGenerateQuillChanges1,
        "testRepeatGenerateQuillChanges2": testRepeatGenerateQuillChanges2,
        "testRepeatGenerateQuillChanges2Repeat":
            testRepeatGenerateQuillChanges2Repeat,
        "testRepeatGenerateQuillChanges3": testRepeatGenerateQuillChanges3,
        "testRepeatGenerateQuillChanges30": testRepeatGenerateQuillChanges30,
        "testRepeatGenerateQuillChanges40": testRepeatGenerateQuillChanges40,
      }
    },
  );
}

/**
 * @param {t.TestCase} tc
 */
void testBasicInsertAndDelete(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final text0 = _data.users[0].text;
  var delta;

  text0.observe((event, _) {
    delta = event.delta;
  });

  text0.delete(0, 0);
  t.check(true, "Does not throw when deleting zero elements with position 0");

  text0.insert(0, "abc");
  t.check(text0.toString() == "abc", "Basic insert works");
  t.compare(delta, [
    {"insert": "abc"}
  ]);

  text0.delete(0, 1);
  t.check(text0.toString() == "bc", "Basic delete works (position 0)");
  t.compare(delta, [
    {"delete": 1}
  ]);

  text0.delete(1, 1);
  t.check(text0.toString() == "b", "Basic delete works (position 1)");
  t.compare(delta, [
    {"retain": 1},
    {"delete": 1}
  ]);

  _data.users[0].instance.transact((_) {
    text0.insert(0, "1");
    text0.delete(0, 1);
  });
  t.compare(delta, []);

  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testBasicFormat(t.TestCase tc) {
  final _data = init(tc, users: 2);
  final text0 = _data.users[0].text;
  List<Map<String, Object?>>? delta;
  text0.observe((event, _) {
    delta = event.delta.map((d) => d.toMap()).toList();
  });
  text0.insert(0, "abc", {"bold": true});
  t.check(text0.toString() == "abc", "Basic insert with attributes works");
  t.compare(text0.toDelta(), [
    {
      "insert": "abc",
      "attributes": {"bold": true}
    }
  ]);
  t.compare(delta, [
    {
      "insert": "abc",
      "attributes": {"bold": true}
    }
  ]);
  text0.delete(0, 1);
  t.check(
      text0.toString() == "bc", "Basic delete on formatted works (position 0)");
  t.compare(text0.toDelta(), [
    {
      "insert": "bc",
      "attributes": {"bold": true}
    }
  ]);
  t.compare(delta, [
    {"delete": 1}
  ]);
  text0.delete(1, 1);
  t.check(text0.toString() == "b", "Basic delete works (position 1)");
  t.compare(text0.toDelta(), [
    {
      "insert": "b",
      "attributes": {"bold": true}
    }
  ]);
  t.compare(delta, [
    {"retain": 1},
    {"delete": 1}
  ]);
  text0.insert(0, "z", {"bold": true});
  t.check(text0.toString() == "zb");
  t.compare(text0.toDelta(), [
    {
      "insert": "zb",
      "attributes": {"bold": true}
    }
  ]);
  t.compare(delta, [
    {
      "insert": "z",
      "attributes": {"bold": true}
    }
  ]);
  // @ts-ignore
  t.check(
      (text0.innerStart!.right!.right!.right!.content as Y.ContentString).str ==
          "b",
      "Does not insert duplicate attribute marker");
  text0.insert(0, "y");
  t.check(text0.toString() == "yzb");
  t.compare(text0.toDelta(), [
    {"insert": "y"},
    {
      "insert": "zb",
      "attributes": {"bold": true}
    },
  ]);
  t.compare(delta, [
    {"insert": "y"}
  ]);
  text0.format(0, 2, {"bold": null});
  t.check(text0.toString() == "yzb");
  t.compare(text0.toDelta(), [
    {"insert": "yz"},
    {
      "insert": "b",
      "attributes": {"bold": true}
    },
  ]);
  t.compare(delta, [
    {"retain": 1},
    {
      "retain": 1,
      "attributes": {"bold": null}
    }
  ]);
  compare(_data.userInstances);
}

/**
 * @param {t.TestCase} tc
 */
void testGetDeltaWithEmbeds(t.TestCase tc) {
  final _data = init(tc, users: 1);
  final text0 = _data.users[0].text;
  text0.applyDelta([
    {
      "insert": {"linebreak": "s"},
    },
  ]);
  t.compare(text0.toDelta(), [
    {
      "insert": {"linebreak": "s"},
    },
  ]);
}

/**
 * @param {t.TestCase} tc
 */
void testSnapshot(t.TestCase tc) {
  final _data = init(tc, users: 1, gc: false);
  final text0 = _data.users[0].text;

  final doc0 = /** @type {Y.Doc} */ (text0.doc!);
  // doc0.gc = false;
  text0.applyDelta([
    {
      "insert": "abcd",
    },
  ]);
  final snapshot1 = Y.snapshot(doc0);
  text0.applyDelta([
    {
      "retain": 1,
    },
    {
      "insert": "x",
    },
    {
      "delete": 1,
    },
  ]);
  final snapshot2 = Y.snapshot(doc0);
  text0.applyDelta([
    {
      "retain": 2,
    },
    {
      "delete": 3,
    },
    {
      "insert": "x",
    },
    {
      "delete": 1,
    },
  ]);
  final state1 = text0.toDelta(snapshot1);
  t.compare(state1, [
    {"insert": "abcd"}
  ]);
  final state2 = text0.toDelta(snapshot2);
  t.compare(state2, [
    {"insert": "axcd"}
  ]);
  final state2Diff = text0.toDelta(snapshot2, snapshot1);
  // @ts-ignore Remove userid info
  state2Diff.forEach((v) {
    final _attr = v["attributes"] as Map<String, Object?>?;
    if (_attr != null && _attr["ychange"] is Map<String, Object?>) {
      (_attr["ychange"] as Map<String, Object?>).remove("user");
    }
  });
  t.compare(state2Diff, [
    {"insert": "a"},
    {
      "insert": "x",
      "attributes": {
        "ychange": {"type": "added"}
      }
    },
    {
      "insert": "b",
      "attributes": {
        "ychange": {"type": "removed"}
      }
    },
    {"insert": "cd"},
  ]);
}

/**
 * @param {t.TestCase} tc
 */
void testSnapshotDeleteAfter(t.TestCase tc) {
  final _data = init(tc, users: 1, gc: false);
  final text0 = _data.users[0].text;

  final doc0 = /** @type {Y.Doc} */ (text0.doc!);
  // doc0.gc = false;
  text0.applyDelta([
    {
      "insert": "abcd",
    },
  ]);
  final snapshot1 = Y.snapshot(doc0);
  text0.applyDelta([
    {
      "retain": 4,
    },
    {
      "insert": "e",
    }
  ]);
  final state1 = text0.toDelta(snapshot1);
  t.compare(state1, [
    {"insert": "abcd"}
  ]);
}

/**
 * @param {t.TestCase} tc
 */
void testToJson(t.TestCase tc) {
  final _data = init(tc, users: 1);
  final text0 = _data.users[0].text;

  text0.insert(0, "abc", {"bold": true});
  t.check(text0.toJSON() == "abc", "toJSON returns the unformatted text");
}

/**
 * @param {t.TestCase} tc
 */
void testToDeltaEmbedAttributes(t.TestCase tc) {
  final _data = init(tc, users: 1);
  final text0 = _data.users[0].text;

  text0.insert(0, "ab", {"bold": true});
  text0.insertEmbed(1, {"image": "imageSrc.png"}, {"width": 100});
  final delta0 = text0.toDelta();
  t.compare(delta0, [
    {
      "insert": "a",
      "attributes": {"bold": true}
    },
    {
      "insert": {"image": "imageSrc.png"},
      "attributes": {"width": 100}
    },
    {
      "insert": "b",
      "attributes": {"bold": true}
    },
  ]);
}

/**
 * @param {t.TestCase} tc
 */
void testToDeltaEmbedNoAttributes(t.TestCase tc) {
  final _data = init(tc, users: 1);
  final text0 = _data.users[0].text;

  text0.insert(0, "ab", {"bold": true});
  text0.insertEmbed(1, {"image": "imageSrc.png"});
  final delta0 = text0.toDelta();
  t.compare(
      delta0,
      [
        {
          "insert": "a",
          "attributes": {"bold": true}
        },
        {
          "insert": {"image": "imageSrc.png"}
        },
        {
          "insert": "b",
          "attributes": {"bold": true}
        },
      ],
      "toDelta does not set attributes key when no attributes are present");
}

/**
 * @param {t.TestCase} tc
 */
void testFormattingRemoved(t.TestCase tc) {
  final _data = init(tc, users: 1);
  final text0 = _data.users[0].text;

  text0.insert(0, "ab", {"bold": true});
  text0.delete(0, 2);
  t.check(Y.getTypeChildren(text0).length == 1);
}

/**
 * @param {t.TestCase} tc
 */
void testFormattingRemovedInMidText(t.TestCase tc) {
  final _data = init(tc, users: 1);
  final text0 = _data.users[0].text;

  text0.insert(0, "1234");
  text0.insert(2, "ab", {"bold": true});
  text0.delete(2, 2);
  t.check(Y.getTypeChildren(text0).length == 3);
}

/**
 * @param {t.TestCase} tc
 */
void testInsertAndDeleteAtRandomPositions(t.TestCase tc) {
  final N = 100000;
  final _data = init(tc, users: 1);
  final text0 = _data.users[0].text;
  final gen = tc.prng;

  // create initial content
  // let expectedResult = init
  text0.insert(0, prng.word(gen, (N / 2).round(), (N / 2).round()));

  // apply changes
  for (var i = 0; i < N; i++) {
    final pos = prng.uint32(gen, 0, text0.length);
    if (gen.nextBool()) {
      final len = prng.uint32(gen, 1, 5);
      final word = prng.word(gen, 0, len);
      text0.insert(pos, word);
      // expectedResult = expectedResult.slice(0, pos) + word + expectedResult.slice(pos)
    } else {
      final len = prng.uint32(gen, 0, math.min(3, text0.length - pos));
      text0.delete(pos, len);
      // expectedResult = expectedResult.slice(0, pos) + expectedResult.slice(pos + len)
    }
  }
  // t.compareStrings(text0.toString(), expectedResult)
  t.describe("final length", text0.length.toString());
}

/**
 * @param {t.TestCase} tc
 */
void testAppendChars(t.TestCase tc) {
  final N = 10000;
  final _data = init(tc, users: 1);
  final text0 = _data.users[0].text;

  // apply changes
  for (var i = 0; i < N; i++) {
    text0.insert(text0.length, "a");
  }
  t.check(text0.length == N);
}

const largeDocumentSize = 100000;

final id = Y.createID(0, 0);
final c = Y.ContentString("a");

/**
 * @param {t.TestCase} tc
 */
void testBestCase(t.TestCase tc) {
  final N = largeDocumentSize;
  final items = List<Y.Item?>.filled(N, null);
  t.measureTime("time to create two million items in the best case", () {
    final parent = /** @type {any} */ ({});
    Y.Item? prevItem;
    for (var i = 0; i < N; i++) {
      /**
       * @type {Y.Item}
       */
      final n = Y.Item(Y.createID(0, 0), null, null, null, null, null, null, c);
      // items.push(n)
      items[i] = n;
      n.right = prevItem;
      n.rightOrigin = prevItem != null ? id : null;
      n.content = c;
      n.parent = parent;
      prevItem = n;
    }
  });
  final newArray = List<Y.Item?>.filled(N, null);
  t.measureTime("time to copy two million items to new Array", () {
    for (var i = 0; i < N; i++) {
      newArray[i] = items[i];
    }
  });
}

void tryGc() {
  // TODO:
  // if (typeof global != "undefined" && global.gc) {
  //   global.gc();
  // }
}

/**
 * @param {t.TestCase} tc
 */
void testLargeFragmentedDocument(t.TestCase tc) {
  final itemsToInsert = largeDocumentSize;
  Uint8List? update;
  (() {
    final doc1 = Y.Doc();
    final text0 = doc1.getText("txt");
    tryGc();
    t.measureTime("time to insert ${itemsToInsert} items", () {
      doc1.transact((_) {
        for (var i = 0; i < itemsToInsert; i++) {
          text0.insert(0, "0");
        }
      });
    });
    tryGc();
    t.measureTime("time to encode document", () {
      update = Y.encodeStateAsUpdateV2(doc1, null);
    });
    t.describe("Document size:", update!.lengthInBytes.toString());
  })();
  (() {
    final doc2 = Y.Doc();
    tryGc();
    t.measureTime("time to apply ${itemsToInsert} updates", () {
      Y.applyUpdateV2(doc2, update!, null);
    });
  })();
}

/**
 * Splitting surrogates can lead to invalid encoded documents.
 *
 * https://github.com/yjs/yjs/issues/248
 *
 * @param {t.TestCase} tc
 */
void testSplitSurrogateCharacter(t.TestCase tc) {
  {
    final _data = init(tc, users: 2);
    final users = _data.userInstances;
    final text0 = _data.users[0].text;
    users[1]
        .disconnect(); // disconnecting forces the user to encode the split surrogate
    text0.insert(0, "👾"); // insert surrogate character
    // split surrogate, which should not lead to an encoding error
    text0.insert(1, "hi!");
    compare(users);
  }
  {
    final _data = init(tc, users: 2);
    final users = _data.userInstances;
    final text0 = _data.users[0].text;
    users[1]
        .disconnect(); // disconnecting forces the user to encode the split surrogate
    text0.insert(0, "👾👾"); // insert surrogate character
    // partially delete surrogate
    text0.delete(1, 2);
    compare(users);
  }
  {
    final _data = init(tc, users: 2);
    final users = _data.userInstances;
    final text0 = _data.users[0].text;
    users[1]
        .disconnect(); // disconnecting forces the user to encode the split surrogate
    text0.insert(0, "👾👾"); // insert surrogate character
    // formatting will also split surrogates
    text0.format(1, 2, {"bold": true});
    compare(users);
  }
}

// RANDOM TESTS

var charCounter = 0;

/**
 * Random tests for pure text operations without formatting.
 *
 * @type Array<function(any,prng.PRNG):void>
 */
final textChanges = <void Function(Y.Doc, Random, dynamic)>[
  /**
   * @param {Y.Doc} y
   * @param {prng.PRNG} gen
   */
  (y, gen, _) {
    // insert text
    final ytext = y.getText("text");
    final insertPos = prng.int32(gen, 0, ytext.length);
    final text = (charCounter++).toString() + prng.word(gen);
    final prevText = ytext.toString();
    ytext.insert(insertPos, text);
    t.compareStrings(
        ytext.toString(),
        prevText.substring(0, insertPos) +
            text +
            prevText.substring(insertPos));
  },
  /**
   * @param {Y.Doc} y
   * @param {prng.PRNG} gen
   */
  (y, gen, _) {
    // delete text
    final ytext = y.getText("text");
    final contentLen = ytext.toString().length;
    final insertPos = prng.int32(gen, 0, contentLen);
    final overwrite = math.min(prng.int32(gen, 0, contentLen - insertPos), 2);
    final prevText = ytext.toString();
    ytext.delete(insertPos, overwrite);
    t.compareStrings(
        ytext.toString(),
        prevText.substring(0, insertPos) +
            prevText.substring(insertPos + overwrite));
  },
];

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateTextChanges5(t.TestCase tc) {
  final _data = checkResult(applyRandomTests(tc, textChanges, 5));
  final cleanups =
      cleanupYTextFormatting(_data.users[0].instance.getText("text"));
  t.check(cleanups == 0);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateTextChanges30(t.TestCase tc) {
  final _data = checkResult(applyRandomTests(tc, textChanges, 30));
  final cleanups =
      cleanupYTextFormatting(_data.users[0].instance.getText("text"));
  t.check(cleanups == 0);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateTextChanges40(t.TestCase tc) {
  final _data = checkResult(applyRandomTests(tc, textChanges, 40));
  final cleanups =
      cleanupYTextFormatting(_data.users[0].instance.getText("text"));
  t.check(cleanups == 0);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateTextChanges50(t.TestCase tc) {
  final _data = checkResult(applyRandomTests(tc, textChanges, 50));
  final cleanups =
      cleanupYTextFormatting(_data.users[0].instance.getText("text"));
  t.check(cleanups == 0);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateTextChanges70(t.TestCase tc) {
  final _data = checkResult(applyRandomTests(tc, textChanges, 70));
  final cleanups =
      cleanupYTextFormatting(_data.users[0].instance.getText("text"));
  t.check(cleanups == 0);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateTextChanges90(t.TestCase tc) {
  final _data = checkResult(applyRandomTests(tc, textChanges, 90));
  final cleanups =
      cleanupYTextFormatting(_data.users[0].instance.getText("text"));
  t.check(cleanups == 0);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateTextChanges300(t.TestCase tc) {
  final _data = checkResult(applyRandomTests(tc, textChanges, 300));
  final cleanups =
      cleanupYTextFormatting(_data.users[0].instance.getText("text"));
  t.check(cleanups == 0);
}

const marks = [
  {"bold": true},
  {"italic": true},
  {"italic": true, "color": "#888"},
];

const marksChoices = [null, ...marks];

/**
 * Random tests for all features of y-text (formatting, embeds, ..).
 *
 * @type Array<function(any,prng.PRNG):void>
 */
final qChanges = <void Function(Y.Doc, Random, dynamic)>[
  /**
   * @param {Y.Doc} y
   * @param {prng.PRNG} gen
   */
  (y, gen, _) {
    // insert text
    final ytext = y.getText("text");
    final insertPos = prng.int32(gen, 0, ytext.length);
    final attrs = prng.oneOf(gen, marksChoices);
    final text = (charCounter++).toString() + prng.word(gen);
    ytext.insert(insertPos, text, attrs);
  },
  /**
   * @param {Y.Doc} y
   * @param {prng.PRNG} gen
   */
  (y, gen, _) {
    // insert embed
    final ytext = y.getText("text");
    final insertPos = prng.int32(gen, 0, ytext.length);
    ytext.insertEmbed(insertPos, {
      "image":
          "https://user-images.githubusercontent.com/5553757/48975307-61efb100-f06d-11e8-9177-ee895e5916e5.png",
    });
  },
  /**
   * @param {Y.Doc} y
   * @param {prng.PRNG} gen
   */
  (y, gen, _) {
    // delete text
    final ytext = y.getText("text");
    final contentLen = ytext.toString().length;
    final insertPos = prng.int32(gen, 0, contentLen);
    final overwrite = math.min(prng.int32(gen, 0, contentLen - insertPos), 2);
    ytext.delete(insertPos, overwrite);
  },
  /**
   * @param {Y.Doc} y
   * @param {prng.PRNG} gen
   */
  (y, gen, _) {
    // format text
    final ytext = y.getText("text");
    final contentLen = ytext.toString().length;
    final insertPos = prng.int32(gen, 0, contentLen);
    final overwrite = math.min(prng.int32(gen, 0, contentLen - insertPos), 2);
    final format = prng.oneOf(gen, marks);
    ytext.format(insertPos, overwrite, format);
  },
  /**
   * @param {Y.Doc} y
   * @param {prng.PRNG} gen
   */
  (y, gen, _) {
    // insert codeblock
    final ytext = y.getText("text");
    final insertPos = prng.int32(gen, 0, ytext.toString().length);
    final text = (charCounter++).toString() + prng.word(gen);
    final ops = <Map<String, Object>>[];
    if (insertPos > 0) {
      ops.add({"retain": insertPos});
    }
    ops.addAll([
      {"insert": text},
      {
        "insert": "\n",
        "format": {"code-block": true}
      }
    ]);
    ytext.applyDelta(ops);
  },
];

/**
 * @param {any} result
 */
TestData checkResult(TestData result) {
  for (var i = 1; i < result.testObjects.length; i++) {
    final p1 = result.users[i].instance.getText("text").toDelta();
    final p2 = result.users[i].instance.getText("text").toDelta();
    t.compare(p1, p2);
  }
  // Uncomment this to find formatting-cleanup issues
  // const cleanups = Y.cleanupYTextFormatting(result.users[0].getText('text'))
  // t.check(cleanups == 0)
  return result;
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateQuillChanges1(t.TestCase tc) {
  final _data = checkResult(applyRandomTests(tc, qChanges, 1));
  final cleanups =
      cleanupYTextFormatting(_data.users[0].instance.getText("text"));
  t.check(cleanups == 0);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateQuillChanges2(t.TestCase tc) {
  final _data = checkResult(applyRandomTests(tc, qChanges, 2));
  final cleanups =
      cleanupYTextFormatting(_data.users[0].instance.getText("text"));
  t.check(cleanups == 0);
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateQuillChanges2Repeat(t.TestCase tc) {
  for (var i = 0; i < 1000; i++) {
    final _data = checkResult(applyRandomTests(tc, qChanges, 2));
    final cleanups =
        cleanupYTextFormatting(_data.users[0].instance.getText("text"));
    t.check(cleanups == 0);
  }
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateQuillChanges3(t.TestCase tc) {
  checkResult(applyRandomTests(tc, qChanges, 3));
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateQuillChanges30(t.TestCase tc) {
  checkResult(applyRandomTests(tc, qChanges, 30));
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateQuillChanges40(t.TestCase tc) {
  checkResult(applyRandomTests(tc, qChanges, 40));
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateQuillChanges70(t.TestCase tc) {
  checkResult(applyRandomTests(tc, qChanges, 70));
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateQuillChanges100(t.TestCase tc) {
  checkResult(applyRandomTests(tc, qChanges, 100));
}

/**
 * @param {t.TestCase} tc
 */
void testRepeatGenerateQuillChanges300(t.TestCase tc) {
  checkResult(applyRandomTests(tc, qChanges, 300));
}
