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

const pingTimeout = 30000;

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

void main() async {
  final subs = await runServer();
  await subs.asFuture();
}

Future<StreamSubscription<WebSocket>> runServer({int? port}) async {
  final _port = port ?? int.parse(Platform.environment['PORT'] ?? '4444');
  final server = await HttpServer.bind('localhost', _port);
  final subs = server.transform(WebSocketTransformer()).listen(onconnection);
  print("Signaling server running on localhost:$_port");

  return subs;
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
void send(WebSocket conn, Map<String, Object?> message) {
  if (conn.readyState != WebSocket.connecting &&
      conn.readyState != WebSocket.open) {
    conn.close();
  }
  try {
    conn.add(jsonEncode(message));
  } catch (e) {
    conn.close();
  }
}

/**
 * Setup a new client
 * @param {any} conn
 */
void onconnection(WebSocket conn) {
  conn.pingInterval = const Duration(milliseconds: pingTimeout);
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
      print(_message);
      final message = jsonDecode(_message as String) as Map<String, Object?>?;

      if (message != null && message['type'] is String && !closed) {
        final _topics = message['topics'] as List<String?>? ?? [];

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
                receivers.forEach((receiver) => send(receiver, message));
              }
            }
            break;
          case "ping":
            send(conn, {"type": "pong"});
        }
      }
    },
    cancelOnError: true,
    onError: (error, stackTrace) {
      print('$error $stackTrace');
    },
    onDone: () {
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
