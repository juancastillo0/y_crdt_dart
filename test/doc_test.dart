// import * as Y from "../src/index.js";
// import * as t from "lib0/testing.js";
import 'package:y_crdt/y_crdt.dart' as Y;
import 'package:y_crdt/src/lib0/testing.dart' as t;

void main() async {
  await t.runTests(
    {
      "doc": {
        "testClientIdDuplicateChange": testClientIdDuplicateChange,
        "testGetTypeEmptyId": testGetTypeEmptyId,
        "testToJSON": testToJSON,
        "testSubdoc": testSubdoc,
      }
    },
  );
}

/**
 * Client id should be changed when an instance receives updates from another client using the same client id.
 *
 * @param {t.TestCase} tc
 */
void testClientIdDuplicateChange(t.TestCase tc) {
  final doc1 = Y.Doc();
  doc1.clientID = 0;
  final doc2 = Y.Doc();
  doc2.clientID = 0;
  t.check(doc2.clientID == doc1.clientID);
  doc1.getArray("a").insert(0, [1, 2]);
  Y.applyUpdate(doc2, Y.encodeStateAsUpdate(doc1, null), null);
  t.check(doc2.clientID != doc1.clientID);
}

/**
 * @param {t.TestCase} tc
 */
void testGetTypeEmptyId(t.TestCase tc) {
  final doc1 = Y.Doc();
  doc1.getText("").insert(0, "h");
  doc1.getText().insert(1, "i");
  final doc2 = Y.Doc();
  Y.applyUpdate(doc2, Y.encodeStateAsUpdate(doc1, null), null);
  t.check(doc2.getText().toString() == "hi");
  t.check(doc2.getText("").toString() == "hi");
}

/**
 * @param {t.TestCase} tc
 */
void testToJSON(t.TestCase tc) {
  final doc = Y.Doc();
  t.compare(doc.toJSON(), {}, "doc.toJSON yields empty object");

  final arr = doc.getArray("array");
  arr.push(["test1"]);

  final map = doc.getMap("map");
  map.set("k1", "v1");
  final map2 = Y.YMap();
  map.set("k2", map2);
  map2.set("m2k1", "m2v1");

  t.compare(
      doc.toJSON(),
      {
        "array": ["test1"],
        "map": {
          "k1": "v1",
          "k2": {
            "m2k1": "m2v1",
          },
        },
      },
      "doc.toJSON has array and recursive map");
}

/**
 * @param {t.TestCase} tc
 */
void testSubdoc(t.TestCase tc) {
  final doc = Y.Doc();
  doc.load(); // doesn't do anything
  {
    /**
     * @type {Array<any>|null}
     */
    List<List<String>>? event;
    doc.on("subdocs", (params) {
      final subdocs = params[0] as Map<String, Set<Y.Doc>>;
      event = [
        subdocs["added"]!.map((d) => d.guid).toList(),
        subdocs["removed"]!.map((d) => d.guid).toList(),
        subdocs["loaded"]!.map((d) => d.guid).toList(),
      ];
    });
    final subdocs = doc.getMap("mysubdocs");
    final docA = Y.Doc(guid: "a");
    docA.load();
    subdocs.set("a", docA);
    t.compare(event, [
      ["a"],
      [],
      ["a"]
    ]);

    event = null;
    subdocs.get("a").load();
    t.check(event == null);

    event = null;
    subdocs.get("a").destroy();
    t.compare(event, [
      ["a"],
      ["a"],
      []
    ]);
    subdocs.get("a").load();
    t.compare(event, [
      [],
      [],
      ["a"]
    ]);

    subdocs.set("b", Y.Doc(guid: "a"));
    t.compare(event, [
      ["a"],
      [],
      []
    ]);
    subdocs.get("b").load();
    t.compare(event, [
      [],
      [],
      ["a"]
    ]);

    final docC = Y.Doc(guid: "c");
    docC.load();
    subdocs.set("c", docC);
    t.compare(event, [
      ["c"],
      [],
      ["c"]
    ]);

    t.compare(doc.getSubdocGuids().toList(), ["a", "c"]);
  }

  final doc2 = Y.Doc();
  {
    t.compare(doc2.getSubdocs().toList(), []);
    /**
     * @type {Array<any>|null}
     */
    List<List<String>>? event;
    doc2.on("subdocs", (params) {
      final subdocs = params[0] as Map<String, Set<Y.Doc>>;
      event = [
        subdocs["added"]!.map((d) => d.guid).toList(),
        subdocs["removed"]!.map((d) => d.guid).toList(),
        subdocs["loaded"]!.map((d) => d.guid).toList(),
      ];
    });
    Y.applyUpdate(doc2, Y.encodeStateAsUpdate(doc, null), null);
    t.compare(event, [
      ["a", "a", "c"],
      [],
      []
    ]);

    doc2.getMap("mysubdocs").get("a").load();
    t.compare(event, [
      [],
      [],
      ["a"]
    ]);

    t.compare(doc2.getSubdocGuids().toList(), ["a", "c"]);

    doc2.getMap("mysubdocs").delete("a");
    t.compare(event, [
      [],
      ["a"],
      []
    ]);
    t.compare(doc2.getSubdocGuids().toList(), ["a", "c"]);
  }
}
