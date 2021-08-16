/* eslint-env browser */

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:y_crdt/src/utils/observable.dart';

/**
 * Tiny websocket connection handler.
 *
 * Implements exponential backoff reconnects, ping/pong, and a nice event system using [lib0/observable].
 *
 * @module websocket
 */

// import { Observable } from "./observable.js";
// import * as time from "./time.js";
// import * as math from "./math.js";

const reconnectTimeoutBase = 1200;
const maxReconnectTimeout = 2500;
// @todo - this should depend on awareness.outdatedTime
const messageReconnectTimeout = 30000;

/**
 * @param {WebsocketClient} wsclient
 */
void setupWS(WebsocketClient wsclient) {
  if (wsclient.shouldConnect && wsclient.ws == null) {
    final websocket = WebSocketChannel.connect(Uri.parse(wsclient.url));
    // const binaryType = wsclient.binaryType;
    /**
     * @type {any}
     */
    Timer? pingTimeout;
    // if (binaryType) {
    //   websocket.binaryType = binaryType;
    // }
    final sendPing = () {
      if (wsclient.ws == websocket) {
        wsclient.send({
          "type": "ping",
        });
      }
    };
    wsclient.ws = websocket;
    wsclient.connecting = true;
    wsclient.connected = false;

    /**
     * @param {any} error
     */
    final onclose = (error) {
      if (wsclient.ws != null) {
        wsclient.ws = null;
        wsclient.connecting = false;
        if (wsclient.connected) {
          wsclient.connected = false;
          wsclient.emit("disconnect", [
            {"type": "disconnect", "error": error},
            wsclient,
          ]);
        } else {
          wsclient.unsuccessfulReconnects++;
        }
        // Start with no reconnect timeout and increase timeout by
        // log10(wsUnsuccessfulReconnects).
        // The idea is to increase reconnect timeout slowly and have no reconnect
        // timeout at the beginning (log(1) = 0)
        Future.delayed(
          Duration(
              milliseconds: math
                  .min(
                      math.log(wsclient.unsuccessfulReconnects + 1) *
                          reconnectTimeoutBase,
                      maxReconnectTimeout)
                  .toInt()),
          () => setupWS(wsclient),
        );
      }
      pingTimeout?.cancel();
    };

    websocket.stream.listen(
      (data) {
        wsclient.lastMessageReceived = DateTime.now().millisecondsSinceEpoch;
        final message = data is String ? jsonDecode(data) : data;
        if (message is Map<String, Object?> && message["type"] == "pong") {
          pingTimeout?.cancel();
          pingTimeout = Timer(
            Duration(milliseconds: messageReconnectTimeout ~/ 2),
            sendPing,
          );
        }
        wsclient.emit("message", [message, wsclient]);
      },
      onDone: () => onclose(null),
      onError: (error) => onclose(error),
    );

    websocket.onOpen = () {
      wsclient.lastMessageReceived = DateTime.now().millisecondsSinceEpoch;
      wsclient.connecting = false;
      wsclient.connected = true;
      wsclient.unsuccessfulReconnects = 0;
      wsclient.emit("connect", [
        {"type": "connect"},
        wsclient
      ]);
      // set ping
      pingTimeout = Timer(
        Duration(milliseconds: messageReconnectTimeout ~/ 2),
        sendPing,
      );
    };
  }
}

/**
 * @extends Observable<string>
 */
class WebsocketClient extends Observable<String> {
  final String url;
  /**
   * @type {WebSocket?}
   */
  WebSocketChannel? ws;
  // bool binaryType = binaryType || null;
  bool connected = false;
  bool connecting = false;
  int unsuccessfulReconnects = 0;
  int lastMessageReceived = 0;
  /**
   * Whether to connect to other peers or not
   * @type {boolean}
   */
  bool shouldConnect = true;

  late final Timer _checkInterval;
  /**
   * @param {string} url
   * @param {object} [opts]
   * @param {'arraybuffer' | 'blob' | null} [opts.binaryType] Set `ws.binaryType`
   */
  WebsocketClient(this.url) {
    this._checkInterval = Timer.periodic(
      Duration(milliseconds: messageReconnectTimeout ~/ 2),
      (_) {
        if (this.connected &&
            messageReconnectTimeout <
                DateTime.now().millisecondsSinceEpoch -
                    this.lastMessageReceived) {
          // no message received in a long time - not even your own awareness
          // updates (which are updated every 15 seconds)
          /** @type {WebSocket} */ (this.ws!).sink.close();
        }
      },
    );

    setupWS(this);
  }

  /**
   * @param {any} message
   */
  void send(message) {
    if (this.ws != null) {
      this.ws!.sink.add(jsonEncode(message));
    }
  }

  @override
  void destroy() {
    this._checkInterval.cancel();
    this.disconnect();
    super.destroy();
  }

  void disconnect() {
    this.shouldConnect = false;
    if (this.ws != null) {
      this.ws!.sink.close();
    }
  }

  void connect() {
    this.shouldConnect = true;
    if (!this.connected && this.ws == null) {
      setupWS(this);
    }
  }
}

// commit: 34444947ddbeca45d93e1420b0b9dc06440919e7
