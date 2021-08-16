/// Support for doing something awesome.
///
/// More dartdocs go here.
library y_crdt;

// EXTERNAL

export 'package:y_crdt/src/external/webrtc_signaling.dart';
export 'package:y_crdt/src/structs/abstract_struct.dart' show AbstractStruct;
export 'package:y_crdt/src/structs/content_any.dart' show ContentAny;
export 'package:y_crdt/src/structs/content_binary.dart' show ContentBinary;
export 'package:y_crdt/src/structs/content_deleted.dart' show ContentDeleted;
export 'package:y_crdt/src/structs/content_embed.dart' show ContentEmbed;
export 'package:y_crdt/src/structs/content_format.dart' show ContentFormat;
export 'package:y_crdt/src/structs/content_json.dart' show ContentJSON;
export 'package:y_crdt/src/structs/content_string.dart' show ContentString;
export 'package:y_crdt/src/structs/content_type.dart' show ContentType;
export 'package:y_crdt/src/structs/gc.dart' show GC;
// STRUCTS

export 'package:y_crdt/src/structs/item.dart' show Item;
export 'package:y_crdt/src/types/abstract_type.dart'
    show
        AbstractType,
        typeListToArraySnapshot,
        typeMapGetSnapshot,
        getTypeChildren;
// TYPES

export 'package:y_crdt/src/types/y_array.dart' show YArray, YArrayEvent;
export 'package:y_crdt/src/types/y_map.dart' show YMap, YMapEvent;
export 'package:y_crdt/src/types/y_text.dart' show YText, YTextEvent;
export 'package:y_crdt/src/utils/abstract_connector.dart'
    show AbstractConnector;
export 'package:y_crdt/src/utils/delete_set.dart'
    show
        createDeleteSet,
        createDeleteSetFromStructStore,
        iterateDeletedStructs,
        isDeleted,
        DeleteSet;
export 'package:y_crdt/src/utils/doc.dart' show Doc;
export 'package:y_crdt/src/utils/encoding.dart'
    show
        applyUpdate,
        applyUpdateV2,
        readUpdate,
        readUpdateV2,
        encodeStateAsUpdate,
        encodeStateAsUpdateV2,
        encodeStateVector,
        encodeStateVectorV2,
        decodeStateVector,
        decodeStateVectorV2,
        useV2Encoding,
        useV1Encoding;
export 'package:y_crdt/src/utils/id.dart'
    show ID, compareIDs, createID, findRootTypeKey;
export 'package:y_crdt/src/utils/is_parent_of.dart' show isParentOf;
// UTILS

export 'package:y_crdt/src/utils/logging.dart' show logType;
// TODO experimental
export 'package:y_crdt/src/utils/permanent_user_data.dart'
    show PermanentUserData;
export 'package:y_crdt/src/utils/relative_position.dart'
    show
        RelativePosition,
        compareRelativePositions,
        createRelativePositionFromJSON,
        createRelativePositionFromTypeIndex,
        createAbsolutePositionFromRelativePosition,
        readRelativePosition,
        writeRelativePosition;
export 'package:y_crdt/src/utils/snapshot.dart'
    show
        Snapshot,
        createSnapshot,
        snapshot,
        emptySnapshot,
        createDocFromSnapshot,
        decodeSnapshot,
        encodeSnapshot,
        decodeSnapshotV2,
        encodeSnapshotV2,
        equalSnapshots;
export 'package:y_crdt/src/utils/struct_store.dart'
    show getItem, getState, getStateVector, StructStore;
export 'package:y_crdt/src/utils/transaction.dart'
    show transact, Transaction, tryGc;
export 'package:y_crdt/src/utils/undo_manager.dart' show UndoManager;
export 'package:y_crdt/src/utils/y_event.dart'
    show YEvent, YChanges, YDelta, YChange, YChangeType;
export 'package:y_crdt/src/y_crdt_base.dart';

//   YXmlText as XmlText,
//   YXmlHook as XmlHook,
//   YXmlElement as XmlElement,
//   YXmlFragment as XmlFragment,
//   YXmlEvent,
// } from "./internals.js";

// TODO: Export any libraries intended for clients of this package.
