// commit: 465d64b5439c422daed18390ce9b59f474162e8b v10.1.8

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// const ws = require("ws");
// const http = require("http");
// const map = require("lib0/dist/map.cjs");

const wsReadyStateConnecting = 0;
const wsReadyStateOpen = 1;
const wsReadyStateClosing = 2; // eslint-disable-line
const wsReadyStateClosed = 3; // eslint-disable-line

// @ts-ignore
// const wss = new ws.Server({ noServer: true });

// const server = http.createServer((request, response) => {
//   response.writeHead(200, { "Content-Type": "text/plain" });
//   response.end("okay");
// });

// wss.on("connection", onconnection);

// server.on("upgrade", (request, socket, head) => {
//   // You may check auth of request here..
//   /**
//    * @param {any} ws
//    */
//   const handleAuth = (ws) => {
//     wss.emit("connection", ws, request);
//   };
//   wss.handleUpgrade(request, socket, head, handleAuth);
// });

// server.listen(port);

Future<WebRtcSignalingServer> runServer({int? port, int? pingTimeout}) async {
  final _port = port ?? int.parse(Platform.environment['PORT'] ?? '4444');
  final server = await WebRtcSignalingServer.make(
    port: _port,
    pingTimeout: pingTimeout,
  );
  print("Signaling server running on localhost:${server.inner.port}");

  return server;
}

class WebRtcSignalingServer {
  final HttpServer inner;
  final int pingTimeout;
  // ignore: cancel_subscriptions
  late final StreamSubscription<WebSocket> connectionsSubs;

  static const defaultPingTimeout = 30000;

  WebRtcSignalingServer._({
    required this.inner,
    required this.pingTimeout,
  }) {
    connectionsSubs = inner.transform(WebSocketTransformer()).listen(
          _onConnection,
        );
  }

  Future<void> close({bool force = false}) async {
    await inner.close(force: force);
  }

  static Future<WebRtcSignalingServer> make({
    required int port,
    int? pingTimeout,
  }) async {
    final innerServer = await HttpServer.bind('localhost', port);
    final _pingTimeout = pingTimeout ?? defaultPingTimeout;
    return WebRtcSignalingServer._(
      inner: innerServer,
      pingTimeout: _pingTimeout,
    );
  }

  /**
   * Map froms topic-name to set of subscribed clients.
   * @type {Map<string, Set<any>>}
   */
  final topics = <String, Set<WebSocket>>{};

  /**
   * @param {any} conn
   * @param {object} message
   */
  void _send(WebSocket conn, Map<String, Object?> message) {
    if (conn.readyState != WebSocket.connecting &&
        conn.readyState != WebSocket.open) {
      conn.close();
    }
    try {
      final strMsg = jsonEncode(message);
      print('send $strMsg');
      conn.add(strMsg);
    } catch (e) {
      conn.close();
    }
  }

  /**
   * Setup a new client
   * @param {any} conn
   */
  void _onConnection(WebSocket conn) {
    print('onConnection $conn');
    conn.pingInterval = Duration(milliseconds: pingTimeout);
    /**
   * @type {Set<string>}
   */
    final subscribedTopics = <String>{};
    bool closed = false;
    // Check if connection is still alive
    // bool pongReceived = true;

    // Timer.periodic(
    //   const Duration(milliseconds: pingTimeout),
    //   (pingInterval) {
    //     if (!pongReceived) {
    //       conn.close();
    //       pingInterval.cancel();
    //     } else {
    //       pongReceived = false;
    //       try {
    //         conn.add('ping');
    //       } catch (e) {
    //         conn.close();
    //       }
    //     }
    //   },
    // );
    conn.listen(
      (_message) {
        print('onmessage $_message');
        final message = jsonDecode(_message as String) as Map<String, Object?>?;

        if (message != null && message['type'] is String && !closed) {
          final List<String?> _topics =
              (message['topics'] as List?)?.cast() ?? [];

          switch (message['type'] as String) {
            case "subscribe":
              /** @type {Array<string>} */ _topics.forEach((topicName) {
                if (topicName != null) {
                  // add conn to topic
                  final topic = topics.putIfAbsent(topicName, () => {});
                  topic.add(conn);
                  // add topic to conn
                  subscribedTopics.add(topicName);
                }
              });
              break;
            case "unsubscribe":
              /** @type {Array<string>} */ _topics.forEach((topicName) {
                final subs = topics[topicName];
                if (subs != null) {
                  subs.remove(conn);
                }
              });
              break;
            case "publish":
              if (message['topic'] is String) {
                final receivers = topics[message['topic']];
                if (receivers != null) {
                  receivers.forEach((receiver) => _send(receiver, message));
                }
              }
              break;
            case "ping":
              _send(conn, {"type": "pong"});
          }
        }
      },
      cancelOnError: true,
      onError: (error, stackTrace) {
        print('$error $stackTrace');
      },
      onDone: () {
        print('onDone');
        subscribedTopics.forEach((topicName) {
          final subs = topics[topicName] ?? {};
          subs.remove(conn);
          if (subs.isEmpty) {
            topics.remove(topicName);
          }
        });
        subscribedTopics.clear();
        closed = true;
      },
    );
  }
}
