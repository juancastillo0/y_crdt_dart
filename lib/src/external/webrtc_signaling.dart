// import * as ws from "lib0/websocket.js";
// import * as map from "lib0/map.js";
// import * as error from "lib0/error.js";
// import * as random from "lib0/random.js";
// import * as encoding from "lib0/encoding.js";
// import * as decoding from "lib0/decoding.js";
// import { Observable } from "lib0/observable.js";
// import * as logging from "lib0/logging.js";
// import * as promise from "lib0/promise.js";
// import * as bc from "lib0/broadcastchannel.js";
// import * as buffer from "lib0/buffer.js";
// import * as math from "lib0/math.js";
// import { createMutex } from "lib0/mutex.js";

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:y_crdt/src/external/broadcast_channel/broadcast_channel_web.dart';
import 'package:y_crdt/src/external/simple_peer.dart';
import 'package:y_crdt/src/utils/observable.dart';
import 'package:y_crdt/y_crdt.dart' as Y;

import "./protocol_awareness.dart" as awarenessProtocol;
// import * as Y from "yjs"; // eslint-disable-line
// import Peer from "simple-peer/simplepeer.min.js";

import "./protocol_sync.dart" as syncProtocol;
import "../lib0/decoding.dart" as decoding;
import "../lib0/encoding.dart" as encoding;

// import * as cryptoutils from "./crypto.js";

// const log = logging.createModuleLogger("y-webrtc");

void Function(VoidCallback, [VoidCallback?]) createMutex() {
  bool token = true;
  return (f, [g]) {
    if (token) {
      token = false;
      try {
        f();
      } finally {
        token = true;
      }
    } else if (g != null) {
      g();
    }
  };
}

const messageSync = 0;
const messageQueryAwareness = 3;
const messageAwareness = 1;
const messageBcPeerId = 4;

final globalSignalingContext = SignalingContext();

class SignalingContext {
  SignalingContext();

  /**
   * @type {Map<string,Room>}
   */
  final rooms = <String, Room>{};

  /**
   * @type {Map<string, SignalingConn>}
   */
  final signalingConns = <String, SignalingConn>{};
}

/**
 * @param {Room} room
 */
void checkIsSynced(Room room) {
  var synced = true;
  room.webrtcConns.values.forEach((peer) {
    if (!peer.synced) {
      synced = false;
    }
  });
  if ((!synced && room.synced) || (synced && !room.synced)) {
    room.synced = synced;
    room.provider.emit("synced", [
      {'synced': synced}
    ]);
    Y.logger.i("synced with all ${room.name} peers");
  }
}

/**
 * @param {Room} room
 * @param {Uint8Array} buf
 * @param {function} syncedCallback
 * @return {encoding.Encoder?}
 */
encoding.Encoder? readMessage(
    Room room, Uint8List buf, void Function() syncedCallback) {
  final decoder = decoding.createDecoder(buf);
  final encoder = encoding.createEncoder();
  final messageType = decoding.readVarUint(decoder);
  // if (room == null) {
  //   return null;
  // }
  final awareness = room.awareness;
  final doc = room.doc;
  bool sendReply = false;
  switch (messageType) {
    case messageSync:
      {
        encoding.writeVarUint(encoder, messageSync);
        final syncMessageType =
            syncProtocol.readSyncMessage(decoder, encoder, doc, room);
        if (syncMessageType == syncProtocol.messageYjsSyncStep2 &&
            !room.synced) {
          syncedCallback();
        }
        if (syncMessageType == syncProtocol.messageYjsSyncStep1) {
          sendReply = true;
        }
        break;
      }
    case messageQueryAwareness:
      encoding.writeVarUint(encoder, messageAwareness);
      encoding.writeVarUint8Array(
          encoder,
          awarenessProtocol.encodeAwarenessUpdate(
              awareness, awareness.getStates().keys.toList()));
      sendReply = true;
      break;
    case messageAwareness:
      awarenessProtocol.applyAwarenessUpdate(
          awareness, decoding.readVarUint8Array(decoder), room);
      break;
    case messageBcPeerId:
      {
        final add = decoding.readUint8(decoder) == 1;
        final peerName = decoding.readVarString(decoder);
        if (peerName != room.peerId &&
            ((room.bcConns.contains(peerName) && !add) ||
                (!room.bcConns.contains(peerName) && add))) {
          final removed = <String>[];
          final added = <String>[];
          if (add) {
            room.bcConns.add(peerName);
            added.add(peerName);
          } else {
            room.bcConns.remove(peerName);
            removed.add(peerName);
          }
          room.provider.emit("peers", [
            {
              "added": added,
              "removed": removed,
              "webrtcPeers": room.webrtcConns.keys.toList(),
              "bcPeers": room.bcConns.toList(),
            },
          ]);
          broadcastBcPeerId(room);
        }
        break;
      }
    default:
      Y.logger.e("Unable to compute message");
      return encoder;
  }
  if (!sendReply) {
    // nothing has been written, no answer created
    return null;
  }
  return encoder;
}

/**
 * @param {WebrtcConn} peerConn
 * @param {Uint8Array} buf
 * @return {encoding.Encoder?}
 */
encoding.Encoder? readPeerMessage(WebrtcConn peerConn, Uint8List buf) {
  final room = peerConn.room;
  Y.logger.i(
    "received message from ${peerConn.remotePeerId} (${room.name})",
  );
  return readMessage(room, buf, () {
    peerConn.synced = true;
    Y.logger.i("synced  ${room.name} with ${peerConn.remotePeerId}");
    checkIsSynced(room);
  });
}

/**
 * @param {WebrtcConn} webrtcConn
 * @param {encoding.Encoder} encoder
 */
void sendWebrtcConn(WebrtcConn webrtcConn, encoding.Encoder encoder) {
  Y.logger.i(
    "send message to ${webrtcConn.remotePeerId}(${webrtcConn.room.name})",
  );
  try {
    webrtcConn.peer.sendBinary(encoding.toUint8Array(encoder));
  } catch (_) {}
}

/**
 * @param {Room} room
 * @param {Uint8Array} m
 */
void broadcastWebrtcConn(Room room, Uint8List m) {
  Y.logger.i("broadcast message in ${room.name}");
  room.webrtcConns.values.forEach((conn) {
    try {
      conn.peer.sendBinary(m);
    } catch (e) {
      Y.logger.e(e);
    }
  });
}

class WebrtcConn {
  final Room room;
  final String remotePeerId;
  bool closed = false;
  bool connected = false;
  bool synced = false;
  final Peer peer;
  /**
   * @param {SignalingConn} signalingConn
   * @param {boolean} initiator
   * @param {string} remotePeerId
   * @param {Room} room
   */
  WebrtcConn(
    SignalingConn signalingConn,
    bool initiator,
    this.remotePeerId,
    this.room,
  ) : peer = Peer(room.provider.peerOpts.copyWith(initiator: initiator)) {
    Y.logger.i("establishing connection to $remotePeerId");

    /**
     * @type {any}
     */
    this.peer.eventStream.listen((event) {
      event.maybeWhen(
        signal: (signal) {
          publishSignalingMessage(signalingConn, room, {
            "to": remotePeerId,
            "from": room.peerId,
            "type": "signal",
            "signal": signal,
          });
        },
        connect: () {
          Y.logger.i("connected to $remotePeerId");
          this.connected = true;
          // send sync step 1
          final provider = room.provider;
          final doc = provider.doc;
          final awareness = room.awareness;
          final encoder = encoding.createEncoder();
          encoding.writeVarUint(encoder, messageSync);
          syncProtocol.writeSyncStep1(encoder, doc);
          sendWebrtcConn(this, encoder);
          final awarenessStates = awareness.getStates();
          if (awarenessStates.length > 0) {
            final encoder = encoding.createEncoder();
            encoding.writeVarUint(encoder, messageAwareness);
            encoding.writeVarUint8Array(
              encoder,
              awarenessProtocol.encodeAwarenessUpdate(
                awareness,
                awarenessStates.keys.toList(),
              ),
            );
            sendWebrtcConn(this, encoder);
          }
        },
        close: () {
          this.connected = false;
          this.closed = true;
          if (room.webrtcConns.containsKey(this.remotePeerId)) {
            room.webrtcConns.remove(this.remotePeerId);
            room.provider.emit("peers", [
              {
                "removed": [this.remotePeerId],
                "added": [],
                "webrtcPeers": room.webrtcConns.keys.toList(),
                "bcPeers": room.bcConns.toList(),
              },
            ]);
          }
          checkIsSynced(room);
          this.peer.destroy();
          Y.logger.i("closed connection to $remotePeerId");
          announceSignalingInfo(room);
        },
        error: (err) {
          Y.logger.i("Error in connection to $remotePeerId: $err");
          announceSignalingInfo(room);
        },
        orElse: () {},
      );
    });
    this.peer.messageStream.listen((data) {
      final answer = readPeerMessage(this, data.binary);
      if (answer != null) {
        sendWebrtcConn(this, answer);
      }
    });
  }

  void destroy() {
    this.peer.destroy();
  }
}

/**
 * @param {Room} room
 * @param {Uint8Array} m
 */
void broadcastBcMessage(Room room, Uint8List m) =>
// cryptoutils.encrypt(m, room.key).then((data) =>
    room.mux(() => broadcastChannelWeb.publish(room.name, m.buffer));
// );

/**
 * @param {Room} room
 * @param {Uint8Array} m
 */
void broadcastRoomMessage(Room room, Uint8List m) {
  if (room.bcconnected) {
    broadcastBcMessage(room, m);
  }
  broadcastWebrtcConn(room, m);
}

/**
 * @param {Room} room
 */
void announceSignalingInfo(Room room) {
  final signalingConns = room.provider.signalingContext.signalingConns;
  signalingConns.values.forEach((conn) {
    // only subcribe if connection is established, otherwise the conn automatically subscribes to all rooms
    if (conn.connected) {
      conn.send({
        "type": "subscribe",
        "topics": [room.name]
      });
      if (room.webrtcConns.length < room.provider.maxConns) {
        publishSignalingMessage(conn, room, {
          "type": "announce",
          "from": room.peerId,
        });
      }
    }
  });
}

/**
 * @param {Room} room
 */
void broadcastBcPeerId(Room room) {
  if (room.provider.filterBcConns) {
    // broadcast peerId via broadcastchannel
    final encoderPeerIdBc = encoding.createEncoder();
    encoding.writeVarUint(encoderPeerIdBc, messageBcPeerId);
    encoding.writeUint8(encoderPeerIdBc, 1);
    encoding.writeVarString(encoderPeerIdBc, room.peerId);
    broadcastBcMessage(room, encoding.toUint8Array(encoderPeerIdBc));
  }
}

final _uuid = Uuid();

class Room {
  /**
   * Do not assume that peerId is unique. This is only meant for sending signaling messages.
   *
   * @type {string}
   */
  final peerId = _uuid.v4();
  final Y.Doc doc;
  /**
   * @type {awarenessProtocol.Awareness}
   */
  awarenessProtocol.Awareness get awareness => provider.awareness;
  final WebrtcProvider provider;
  bool synced = false;
  final String name;
  // @todo make key secret by scoping
  final /*CryptoKey*/ Object? key;
  /**
   * @type {Map<string, WebrtcConn>}
   */
  final webrtcConns = <String, WebrtcConn>{};
  /**
   * @type {Set<string>}
   */
  final bcConns = <String>{};
  final mux = createMutex();
  bool bcconnected = false;

  /**
   * @param {Y.Doc} doc
   * @param {WebrtcProvider} provider
   * @param {string} name
   * @param {CryptoKey|null} key
   */
  Room(this.doc, this.provider, this.name, this.key) {
    this.doc.on(
          "update",
          this._docUpdateHandlerWrapper,
        );
    this.awareness.on("update", this._awarenessUpdateHandlerWrapped);

    // window.addEventListener("beforeunload", () {
    //   awarenessProtocol.removeAwarenessStates(
    //       this.awareness, [doc.clientID], "window unload");
    //   rooms.values.forEach((room) {
    //     room.disconnect();
    //   });
    // });
  }

  void _awarenessUpdateHandlerWrapped(List<dynamic> params) {
    final map = params[0] as Map<String, dynamic>;
    this._awarenessUpdateHandler(
      added: List.castFrom(map["added"] as List),
      removed: List.castFrom(map["removed"] as List),
      updated: List.castFrom(map["updated"] as List),
      origin: params[1],
    );
  }

  /**
     * @param {ArrayBuffer} data
     */
  void _bcSubscriber(Object? data) =>
      // cryptoutils.decrypt(Uint8List.view(data), key).then((m) =>
      this.mux(() {
        final reply =
            readMessage(this, Uint8List.view(data as ByteBuffer), () {});
        if (reply != null) {
          broadcastBcMessage(this, encoding.toUint8Array(reply));
        }
      });
  // );

  void _docUpdateHandlerWrapper(List<dynamic> params) =>
      this._docUpdateHandler(params[0] as Uint8List, params[1]);
  /**
     * Listens to Yjs updates and sends them to remote peers
     *
     * @param {Uint8Array} update
     * @param {any} origin
     */
  void _docUpdateHandler(Uint8List update, dynamic origin) {
    final encoder = encoding.createEncoder();
    encoding.writeVarUint(encoder, messageSync);
    syncProtocol.writeUpdate(encoder, update);
    broadcastRoomMessage(this, encoding.toUint8Array(encoder));
  }

  /**
     * Listens to Awareness updates and sends them to remote peers
     *
     * @param {any} changed
     * @param {any} origin
     */
  void _awarenessUpdateHandler({
    required List<int> added,
    required List<int> updated,
    required List<int> removed,
    dynamic origin,
  }) {
    final changedClients = [...added, ...updated, ...removed];
    final encoderAwareness = encoding.createEncoder();
    encoding.writeVarUint(encoderAwareness, messageAwareness);
    encoding.writeVarUint8Array(
      encoderAwareness,
      awarenessProtocol.encodeAwarenessUpdate(this.awareness, changedClients),
    );
    broadcastRoomMessage(this, encoding.toUint8Array(encoderAwareness));
  }

  void connect() {
    // signal through all available signaling connections
    announceSignalingInfo(this);
    final roomName = this.name;
    broadcastChannelWeb.subscribe(roomName, this._bcSubscriber);
    this.bcconnected = true;
    // broadcast peerId via broadcastchannel
    broadcastBcPeerId(this);
    // write sync step 1
    final encoderSync = encoding.createEncoder();
    encoding.writeVarUint(encoderSync, messageSync);
    syncProtocol.writeSyncStep1(encoderSync, this.doc);
    broadcastBcMessage(this, encoding.toUint8Array(encoderSync));
    // broadcast local state
    final encoderState = encoding.createEncoder();
    encoding.writeVarUint(encoderState, messageSync);
    syncProtocol.writeSyncStep2(encoderState, this.doc, null);
    broadcastBcMessage(this, encoding.toUint8Array(encoderState));
    // write queryAwareness
    final encoderAwarenessQuery = encoding.createEncoder();
    encoding.writeVarUint(encoderAwarenessQuery, messageQueryAwareness);
    broadcastBcMessage(this, encoding.toUint8Array(encoderAwarenessQuery));
    // broadcast local awareness state
    final encoderAwarenessState = encoding.createEncoder();
    encoding.writeVarUint(encoderAwarenessState, messageAwareness);
    encoding.writeVarUint8Array(
        encoderAwarenessState,
        awarenessProtocol.encodeAwarenessUpdate(this.awareness, [
          this.doc.clientID,
        ]));
    broadcastBcMessage(this, encoding.toUint8Array(encoderAwarenessState));
  }

  void disconnect() {
    // signal through all available signaling connections
    provider.signalingContext.signalingConns.values.forEach((conn) {
      if (conn.connected) {
        conn.send({
          "type": "unsubscribe",
          "topics": [this.name]
        });
      }
    });
    awarenessProtocol.removeAwarenessStates(
      this.awareness,
      [this.doc.clientID],
      "disconnect",
    );
    // broadcast peerId removal via broadcastchannel
    final encoderPeerIdBc = encoding.createEncoder();
    encoding.writeVarUint(encoderPeerIdBc, messageBcPeerId);
    encoding.writeUint8(
        encoderPeerIdBc, 0); // remove peerId from other bc peers
    encoding.writeVarString(encoderPeerIdBc, this.peerId);
    broadcastBcMessage(this, encoding.toUint8Array(encoderPeerIdBc));

    broadcastChannelWeb.unsubscribe(this.name, this._bcSubscriber);
    this.bcconnected = false;
    this.doc.off("update", this._docUpdateHandlerWrapper);
    this.awareness.off("update", this._awarenessUpdateHandlerWrapped);
    this.webrtcConns.values.forEach((conn) => conn.destroy());
  }

  void destroy() {
    this.disconnect();
  }
}

/**
 * @param {Y.Doc} doc
 * @param {WebrtcProvider} provider
 * @param {string} name
 * @param {CryptoKey|null} key
 * @return {Room}
 */
Room openRoom(Y.Doc doc, WebrtcProvider provider, String name, Object? key) {
  // there must only be one room
  final rooms = provider.signalingContext.rooms;
  if (rooms.containsKey(name)) {
    throw Exception("A Yjs Doc connected to room '${name}' already exists!");
  }
  final room = Room(doc, provider, name, key);
  rooms.set(name, /** @type {Room} */ room);
  return room;
}

/**
 * @param {SignalingConn} conn
 * @param {Room} room
 * @param {any} data
 */
void publishSignalingMessage(SignalingConn conn, Room room, Object data) {
  if (room.key != null) {
    // TODO:
    throw Exception("Encription not supported");
    // cryptoutils.encryptJson(data, room.key).then((data) {
    //   conn.send({
    //     "type": "publish",
    //     "topic": room.name,
    //     "data": buffer.toBase64(data),
    //   });
    // });
  } else {
    conn.send({
      "type": "publish",
      "topic": room.name,
      "data": data,
    });
  }
}

class SignalingConn {
  /**
     * @type {Set<WebrtcProvider>}
     */
  final providers = <WebrtcProvider>{};
  final WebSocketChannel _channel;
  final String url;

  bool connected = false;

  void send(Map<String, Object> json) {
    if (this.connected) {
      this._channel.sink.add(jsonEncode(json));
    }
  }

  void destroy() {
    _channel.sink.close();
  }

  SignalingConn(this.url, SignalingContext signalingContext)
      : _channel = WebSocketChannel.connect(Uri.parse(url)) {
    final rooms = signalingContext.rooms;
    _channel.sink.add(jsonEncode({"type": "publish"}));
    _channel.onOpen = () {
      if (!connected) {
        connected = true;
        Y.logger.i("connected (${url})");
        final topics = rooms.keys.toList();
        this.send({"type": "subscribe", "topics": topics});
        rooms.values.forEach(
          (room) => publishSignalingMessage(this, room, {
            "type": "announce",
            "from": room.peerId,
          }),
        );
      }
    };
    _channel.stream.listen(
      (event) {
        final m = jsonDecode(event as String) as Map<String, Object?>;
        switch (m["type"]) {
          case "publish":
            {
              final roomName = m["topic"];
              final room = roomName is String ? rooms.get(roomName) : null;
              if (room == null) {
                return;
              }

              void _execMessage(Map<String, Object?>? _data) {
                if (_data == null) {
                  return;
                }
                final data = SignalingMsg.fromJson(_data);
                final webrtcConns = room.webrtcConns;
                final peerId = room.peerId;
                if (data.from == peerId ||
                    (data.to != null && data.to != peerId) ||
                    room.bcConns.contains(data.from)) {
                  // ignore messages that are not addressed to this conn, or from clients that are connected via broadcastchannel
                  return;
                }
                final emitPeerChange = webrtcConns.containsKey(data.from)
                    ? () => {}
                    : () => room.provider.emit("peers", [
                          {
                            "removed": [],
                            "added": [data.from],
                            "webrtcPeers": room.webrtcConns.keys.toList(),
                            "bcPeers": room.bcConns.toList(),
                          },
                        ]);
                switch (data.type) {
                  case "announce":
                    if (webrtcConns.length < room.provider.maxConns) {
                      webrtcConns.putIfAbsent(
                        data.from,
                        () => WebrtcConn(this, true, data.from, room),
                      );
                      emitPeerChange();
                    }
                    break;
                  case "signal":
                    if (data.to == peerId) {
                      webrtcConns
                          .putIfAbsent(
                            data.from,
                            () => WebrtcConn(this, false, data.from, room),
                          )
                          .peer
                          .signal(data.signal!);
                      emitPeerChange();
                    }
                    break;
                }
              }

              if (room.key != null) {
                // TODO:
                throw Exception("Encription not supported");
                // if (m.data is String) {
                //   cryptoutils
                //       .decryptJson(buffer.fromBase64(m.data), room.key)
                //       .then(execMessage);
                // }
              } else {
                _execMessage(m["data"] as Map<String, Object?>?);
              }
            }
        }
      },
      cancelOnError: true,
      onDone: () {
        Y.logger.i("disconnect onDone (${url})");
        this.connected = false;
      },
      onError: (e, s) {
        Y.logger.i("disconnect onError (${url}) $e - $s");
        this.connected = false;
      },
    );
  }
}

class SignalingMsg {
  final String? to;
  final String from;
  final String type;
  final Map<String, Object?>? signal;

  const SignalingMsg({
    required this.to,
    required this.from,
    required this.type,
    required this.signal,
  });

  static SignalingMsg fromJson(Map<String, Object?> map) {
    return SignalingMsg(
      to: map['to'] as String?,
      from: map['from'] as String,
      type: map['type'] as String,
      signal: (map['signal'] as Map?)?.cast(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      "to": to,
      "from": from,
      "type": type,
      "signal": signal,
    };
  }
}

final random = Random();

/**
 * @extends Observable<string>
 */
class WebrtcProvider extends Observable<String> {
  final String roomName;
  final Y.Doc doc;
  final bool filterBcConns;
  /**
   * @type {awarenessProtocol.Awareness}
   */
  final awarenessProtocol.Awareness awareness;
  bool shouldConnect = false;
  final List<String> signalingUrls;
  final signalingConns = <SignalingConn>[];
  final int maxConns;
  final PeerOptions peerOpts;
  final Future<Object?> key;
  final SignalingContext signalingContext;

  /**
   * @type {Room|null}
   */
  Room? room;

  /**
   * @param {string} roomName
   * @param {Y.Doc} doc
   * @param {Object} [opts]
   * @param {Array<string>} [opts.signaling]
   * @param {string?} [opts.password]
   * @param {awarenessProtocol.Awareness} [opts.awareness]
   * @param {number} [opts.maxConns]
   * @param {boolean} [opts.filterBcConns]
   * @param {any} [opts.peerOpts]
   */
  WebrtcProvider(
    this.roomName,
    this.doc, {
    List<String> signaling = const [
      "wss://signaling.yjs.dev",
      "wss://y-webrtc-signaling-eu.herokuapp.com",
      "wss://y-webrtc-signaling-us.herokuapp.com",
    ],
    String? password,
    awarenessProtocol.Awareness? awareness,
    SignalingContext? signalingContext,
    int?
        maxConns, // the random factor reduces the chance that n clients form a cluster
    this.filterBcConns = true,
    this.peerOpts =
        const PeerOptions(), // simple-peer options. See https://github.com/feross/simple-peer#peer--new-peeropts
  })  : signalingContext = signalingContext ?? globalSignalingContext,
        signalingUrls = signaling,
        maxConns = maxConns ?? 20 + (random.nextDouble() * 15).floor(),
        awareness = awareness ?? awarenessProtocol.Awareness(doc),
        key = Future.value(null) {
    /**
     * @type {PromiseLike<CryptoKey | null>}
     */
    // TODO:
    // this.key = password != null
    //     ? cryptoutils.deriveKey(password, roomName)
    //     : /** @type {PromiseLike<null>} */ (promise.resolve(null));

    this.key.then((key) {
      this.room = openRoom(doc, this, roomName, key);
      if (this.shouldConnect) {
        this.room!.connect();
      } else {
        this.room!.disconnect();
      }
    });
    this.connect();
    doc.on("destroy", this._destroyWrapper);
  }

  /**
   * @type {boolean}
   */
  bool get connected {
    return this.room != null && this.shouldConnect;
  }

  void connect() {
    this.shouldConnect = true;
    this.signalingUrls.forEach((url) {
      final signalingConn = signalingContext.signalingConns
          .putIfAbsent(url, () => SignalingConn(url, signalingContext));
      this.signalingConns.add(signalingConn);
      signalingConn.providers.add(this);
    });
    this.room?.connect();
  }

  void disconnect() {
    this.shouldConnect = false;
    this.signalingConns.forEach((conn) {
      conn.providers.remove(this);
      if (conn.providers.length == 0) {
        conn.destroy();
        signalingContext.signalingConns.remove(conn.url);
      }
    });

    this.room?.disconnect();
  }

  void _destroyWrapper(List<dynamic> _) => this.destroy();

  @override
  void destroy() {
    this.doc.off("destroy", _destroyWrapper);
    // need to wait for key before deleting room
    this.key.then((_) {
      /** @type {Room} */ (this.room!).destroy();
      signalingContext.rooms.remove(this.roomName);
    });
    super.destroy();
  }
}
