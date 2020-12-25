/// Support for doing something awesome.
///
/// More dartdocs go here.
library y_crdt;

export 'src/y_crdt_base.dart';

// TYPES

export 'src/types/YArray.dart' show YArray, YArrayEvent;
export 'src/types/YMap.dart' show YMap, YMapEvent;
export 'src/types/YText.dart' show YText, YTextEvent;
export 'src/types/AbstractType.dart'
    show
        AbstractType,
        typeListToArraySnapshot,
        typeMapGetSnapshot,
        getTypeChildren;

// UTILS

export 'src/utils/logging.dart' show logType;
export 'src/utils/AbstractConnector.dart' show AbstractConnector;
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
export 'src/utils/DeleteSet.dart'
    show
        createDeleteSet,
        createDeleteSetFromStructStore,
        iterateDeletedStructs,
        isDeleted,
        DeleteSet;
export 'src/utils/transaction.dart' show transact, Transaction, tryGc;
export 'src/utils/Doc.dart' show Doc;
export 'src/utils/YEvent.dart' show YEvent, YChanges, YDelta;
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

export 'src/structs/Item.dart' show Item;
export 'src/structs/AbstractStruct.dart' show AbstractStruct;
export 'src/structs/GC.dart' show GC;
export 'src/structs/ContentBinary.dart' show ContentBinary;
export 'src/structs/ContentDeleted.dart' show ContentDeleted;
export 'src/structs/ContentEmbed.dart' show ContentEmbed;
export 'src/structs/ContentFormat.dart' show ContentFormat;
export 'src/structs/ContentJSON.dart' show ContentJSON;
export 'src/structs/ContentAny.dart' show ContentAny;
export 'src/structs/ContentString.dart' show ContentString;
export 'src/structs/ContentType.dart' show ContentType;

//   YXmlText as XmlText,
//   YXmlHook as XmlHook,
//   YXmlElement as XmlElement,
//   YXmlFragment as XmlFragment,
//   YXmlEvent,
// } from "./internals.js";

// TODO: Export any libraries intended for clients of this package.
