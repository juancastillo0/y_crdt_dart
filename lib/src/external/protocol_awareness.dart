import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/**
 * @module awareness-protocol
 */
import 'package:y_crdt/src/utils/observable.dart';
import 'package:y_crdt/src/y_crdt_base.dart';
import 'package:y_crdt/y_crdt.dart' as Y;

import "../lib0/decoding.dart" as decoding;
import "../lib0/encoding.dart" as encoding;

const outdatedTimeout = 30000;

/**
 * @typedef {Object} MetaClientState
 * @property {number} MetaClientState.clock
 * @property {number} MetaClientState.lastUpdated unix timestamp
 */
class MetaClientState {
  final int clock;
  final int lastUpdated;

  const MetaClientState({required this.clock, required this.lastUpdated});
}

/**
 * The Awareness class implements a simple shared state protocol that can be used for non-persistent data like awareness information
 * (cursor, username, status, ..). Each client can update its own local state and listen to state changes of
 * remote clients. Every client may set a state of a remote peer to `null` to mark the client as offline.
 *
 * Each client is identified by a unique client id (something we borrow from `doc.clientID`). A client can override
 * its own state by propagating a message with an increasing timestamp (`clock`). If such a message is received, it is
 * applied if the known state of that client is older than the new state (`clock < newClock`). If a client thinks that
 * a remote client is offline, it may propagate a message with
 * `{ clock: currentClientClock, state: null, client: remoteClient }`. If such a
 * message is received, and the known clock of that client equals the received clock, it will override the state with `null`.
 *
 * Before a client disconnects, it should propagate a `null` state with an updated clock.
 *
 * Awareness states must be updated every 30 seconds. Otherwise the Awareness instance will delete the client state.
 *
 * @extends {Observable<string>}
 */
class Awareness extends Observable<String> {
  final Y.Doc doc;
  /**
   * @type {number}
   */
  final int clientID;
  /**
   * Maps from client id to client state
   * @type {Map<number, Object<string, any>>}
   */
  final states = <int, Map<String, Object>>{};
  /**
   * @type {Map<number, MetaClientState>}
   */
  final meta = <int, MetaClientState>{};

  late final Timer _checkInterval;

  /**
   * @param {Y.Doc} doc
   */
  Awareness(this.doc) : clientID = doc.clientID {
    this._checkInterval = Timer.periodic(
        Duration(milliseconds: (outdatedTimeout / 10).floor()), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (this.getLocalState() != null &&
          outdatedTimeout / 2 <=
              now -
                  /** @type {{lastUpdated:number}} */ (this
                          .meta
                          .get(this.clientID)!)
                      .lastUpdated) {
        // renew local clock
        this.setLocalState(this.getLocalState());
      }
      /**
       * @type {Array<number>}
       */
      final remove = <int>[];
      this.meta.entries.forEach((entry) {
        final meta = entry.value;
        final clientid = entry.key;
        if (clientid != this.clientID &&
            outdatedTimeout <= now - meta.lastUpdated &&
            this.states.containsKey(clientid)) {
          remove.add(clientid);
        }
      });
      if (remove.length > 0) {
        removeAwarenessStates(this, remove, "timeout");
      }
    });
    doc.on("destroy", (_) {
      this.destroy();
    });
    this.setLocalState({});
  }

  @override
  void destroy() {
    this.emit("destroy", [this]);
    this.setLocalState(null);
    super.destroy();
    this._checkInterval.cancel();
  }

  /**
   * @return {Object<string,any>|null}
   */
  Map<String, Object>? getLocalState() {
    return this.states.get(this.clientID);
  }

  /**
   * @param {Object<string,any>|null} state
   */
  void setLocalState(Map<String, Object>? state) {
    final clientID = this.clientID;
    final currLocalMeta = this.meta.get(clientID);
    final clock = currLocalMeta == null ? 0 : currLocalMeta.clock + 1;
    final prevState = this.states.get(clientID);
    if (state == null) {
      this.states.remove(clientID);
    } else {
      this.states.set(clientID, state);
    }
    this.meta.set(
        clientID,
        MetaClientState(
          clock: clock,
          lastUpdated: DateTime.now().millisecondsSinceEpoch,
        ));
    final added = <int>[];
    final updated = <int>[];
    final filteredUpdated = <int>[];
    final removed = <int>[];
    if (state == null) {
      removed.add(clientID);
    } else if (prevState == null) {
      if (state != null) {
        added.add(clientID);
      }
    } else {
      updated.add(clientID);
      if (!areEqualDeep(prevState, state)) {
        filteredUpdated.add(clientID);
      }
    }
    if (added.length > 0 || filteredUpdated.length > 0 || removed.length > 0) {
      this.emit("change", [
        {"added": added, "updated": filteredUpdated, "removed": removed},
        "local",
      ]);
    }
    this.emit("update", [
      {"added": added, "updated": updated, "removed": removed},
      "local"
    ]);
  }

  /**
   * @param {string} field
   * @param {any} value
   */
  void setLocalStateField(String field, Object value) {
    final state = this.getLocalState();
    if (state != null) {
      state[field] = value;
      this.setLocalState(state);
    }
  }

  /**
   * @return {Map<number,Object<string,any>>}
   */
  Map<int, Map<String, Object?>> getStates() {
    return this.states;
  }
}

/**
 * Mark (remote) clients as inactive and remove them from the list of active peers.
 * This change will be propagated to remote clients.
 *
 * @param {Awareness} awareness
 * @param {Array<number>} clients
 * @param {any} origin
 */
void removeAwarenessStates(
    Awareness awareness, List<int> clients, dynamic origin) {
  final removed = <int>[];
  for (int i = 0; i < clients.length; i++) {
    final clientID = clients[i];
    if (awareness.states.containsKey(clientID)) {
      awareness.states.remove(clientID);
      if (clientID == awareness.clientID) {
        final curMeta =
            /** @type {MetaClientState} */ awareness.meta.get(clientID)!;
        awareness.meta.set(
            clientID,
            MetaClientState(
              clock: curMeta.clock + 1,
              lastUpdated: DateTime.now().millisecondsSinceEpoch,
            ));
      }
      removed.add(clientID);
    }
  }
  if (removed.length > 0) {
    awareness.emit("change", [
      {"added": [], "updated": [], "removed": removed},
      origin
    ]);
    awareness.emit("update", [
      {"added": [], "updated": [], "removed": removed},
      origin
    ]);
  }
}

/**
 * @param {Awareness} awareness
 * @param {Array<number>} clients
 * @return {Uint8Array}
 */
Uint8List encodeAwarenessUpdate(Awareness awareness, List<int> clients) {
  final states = awareness.states;
  final len = clients.length;
  final encoder = encoding.createEncoder();
  encoding.writeVarUint(encoder, len);
  for (int i = 0; i < len; i++) {
    final clientID = clients[i];
    final state = states.get(clientID);
    final clock =
        /** @type {MetaClientState} */ (awareness.meta.get(clientID)!).clock;
    encoding.writeVarUint(encoder, clientID);
    encoding.writeVarUint(encoder, clock);
    encoding.writeVarString(encoder, jsonEncode(state));
  }
  return encoding.toUint8Array(encoder);
}

/**
 * Modify the content of an awareness update before re-encoding it to an awareness update.
 *
 * This might be useful when you have a central server that wants to ensure that clients
 * cant hijack somebody elses identity.
 *
 * @param {Uint8Array} update
 * @param {function(any):any} modify
 * @return {Uint8Array}
 */
Uint8List modifyAwarenessUpdate(
    Uint8List update, dynamic Function(dynamic) modify) {
  final decoder = decoding.createDecoder(update);
  final encoder = encoding.createEncoder();
  final len = decoding.readVarUint(decoder);
  encoding.writeVarUint(encoder, len);
  for (int i = 0; i < len; i++) {
    final clientID = decoding.readVarUint(decoder);
    final clock = decoding.readVarUint(decoder);
    final state = jsonDecode(decoding.readVarString(decoder));
    final modifiedState = modify(state);
    encoding.writeVarUint(encoder, clientID);
    encoding.writeVarUint(encoder, clock);
    encoding.writeVarString(encoder, jsonEncode(modifiedState));
  }
  return encoding.toUint8Array(encoder);
}

/**
 * @param {Awareness} awareness
 * @param {Uint8Array} update
 * @param {any} origin This will be added to the emitted change event
 */
void applyAwarenessUpdate(
    Awareness awareness, Uint8List update, dynamic origin) {
  final decoder = decoding.createDecoder(update);
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final added = [];
  final updated = [];
  final filteredUpdated = [];
  final removed = [];
  final len = decoding.readVarUint(decoder);
  for (int i = 0; i < len; i++) {
    final clientID = decoding.readVarUint(decoder);
    var clock = decoding.readVarUint(decoder);
    final _s = jsonDecode(decoding.readVarString(decoder));
    final Map<String, Object>? state = (_s as Map?)?.cast();
    final clientMeta = awareness.meta.get(clientID);
    final prevState = awareness.states.get(clientID);
    final currClock = clientMeta == null ? 0 : clientMeta.clock;
    if (currClock < clock ||
        (currClock == clock &&
            state == null &&
            awareness.states.containsKey(clientID))) {
      if (state == null) {
        // never let a remote client remove this local state
        if (clientID == awareness.clientID &&
            awareness.getLocalState() != null) {
          // remote client removed the local state. Do not remote state. Broadcast a message indicating
          // that this client still exists by increasing the clock
          clock++;
        } else {
          awareness.states.remove(clientID);
        }
      } else {
        awareness.states.set(clientID, state);
      }
      awareness.meta.set(
        clientID,
        MetaClientState(
          clock: clock,
          lastUpdated: timestamp,
        ),
      );
      if (clientMeta == null && state != null) {
        added.add(clientID);
      } else if (clientMeta != null && state == null) {
        removed.add(clientID);
      } else if (state != null) {
        if (!areEqualDeep(state, prevState)) {
          filteredUpdated.add(clientID);
        }
        updated.add(clientID);
      }
    }
  }
  if (added.length > 0 || filteredUpdated.length > 0 || removed.length > 0) {
    awareness.emit("change", [
      {
        "added": added,
        "updated": filteredUpdated,
        "removed": removed,
      },
      origin,
    ]);
  }
  if (added.length > 0 || updated.length > 0 || removed.length > 0) {
    awareness.emit("update", [
      {
        "added": added,
        "updated": updated,
        "removed": removed,
      },
      origin,
    ]);
  }
}
