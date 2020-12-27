/// Support for doing something awesome.
///
/// More dartdocs go here.
library y_crdt;

export 'src/y_crdt_base.dart';

// TYPES

export 'src/types/y_array.dart' show YArray, YArrayEvent;
export 'src/types/y_map.dart' show YMap, YMapEvent;
export 'src/types/y_text.dart' show YText, YTextEvent;
export 'src/types/abstract_type.dart'
    show
        AbstractType,
        typeListToArraySnapshot,
        typeMapGetSnapshot,
        getTypeChildren;

// UTILS

export 'src/utils/logging.dart' show logType;
export 'src/utils/abstract_connector.dart' show AbstractConnector;
// TODO experimental
export 'src/utils/permanent_user_data.dart' show PermanentUserData;
export 'src/utils/is_parent_of.dart' show isParentOf;
export 'src/utils/undo_manager.dart' show UndoManager;
export 'src/utils/encoding.dart'
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
export 'src/utils/struct_store.dart'
    show getItem, getState, getStateVector, StructStore;
export 'src/utils/relative_position.dart'
    show
        RelativePosition,
        compareRelativePositions,
        createRelativePositionFromJSON,
        createRelativePositionFromTypeIndex,
        createAbsolutePositionFromRelativePosition,
        readRelativePosition,
        writeRelativePosition;
export 'src/utils/delete_set.dart'
    show
        createDeleteSet,
        createDeleteSetFromStructStore,
        iterateDeletedStructs,
        isDeleted,
        DeleteSet;
export 'src/utils/transaction.dart' show transact, Transaction, tryGc;
export 'src/utils/doc.dart' show Doc;
export 'src/utils/y_event.dart'
    show YEvent, YChanges, YDelta, YChange, YChangeType;
export 'src/utils/id.dart' show ID, compareIDs, createID, findRootTypeKey;
export 'src/utils/snapshot.dart'
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

// STRUCTS

export 'src/structs/item.dart' show Item;
export 'src/structs/abstract_struct.dart' show AbstractStruct;
export 'src/structs/gc.dart' show GC;
export 'src/structs/content_binary.dart' show ContentBinary;
export 'src/structs/content_deleted.dart' show ContentDeleted;
export 'src/structs/content_embed.dart' show ContentEmbed;
export 'src/structs/content_format.dart' show ContentFormat;
export 'src/structs/content_json.dart' show ContentJSON;
export 'src/structs/content_any.dart' show ContentAny;
export 'src/structs/content_string.dart' show ContentString;
export 'src/structs/content_type.dart' show ContentType;

//   YXmlText as XmlText,
//   YXmlHook as XmlHook,
//   YXmlElement as XmlElement,
//   YXmlFragment as XmlFragment,
//   YXmlEvent,
// } from "./internals.js";

// TODO: Export any libraries intended for clients of this package.
