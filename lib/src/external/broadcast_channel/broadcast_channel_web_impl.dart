import 'dart:html';

import 'broadcast_channel_web_base.dart';

export 'broadcast_channel_web_base.dart' hide broadcastChannelWeb;

/**
 * Helpers for cross-tab communication using broadcastchannel with LocalStorage fallback.
 *
 * ```js
 * // In browser window A:
 * broadcastchannel.subscribe('my events', data => console.log(data))
 * broadcastchannel.publish('my events', 'Hello world!') // => A: 'Hello world!' fires synchronously in same tab
 *
 * // In browser window B:
 * broadcastchannel.publish('my events', 'hello from tab B') // => A: 'hello from tab B'
 * ```
 *
 * @module broadcastchannel
 */

// @todo before next major: use Uint8Array instead as buffer object

// import * as map from "./map.js";
// import * as buffer from "./buffer.js";
// import * as storage from "./storage.js";

/**
 * @typedef {Object} Channel
 * @property {Set<Function>} Channel.subs
 * @property {any} Channel.bc
 */

/**
 * @type {Map<string, Channel>}
 */
final channels = <String, Channel>{};

// class LocalStoragePolyfill {
//   final String room;
//   /**
//    * @param {string} room
//    */
//   LocalStoragePolyfill(this.room) {
//     addEventListener(
//       "storage",
//       (e) =>
//         e.key === room &&
//         this.onmessage !== null &&
//         this.onmessage({ data: buffer.fromBase64(e.newValue || "") })
//     );
//   }

//   void Function(Uint8List message)? onMessage;

//   /**
//    * @param {ArrayBuffer} buf
//    */
//   void postMessage(Uint8List buf) {
//     storage.varStorage.setItem(
//       this.room,
//       buffer.toBase64(buffer.createUint8ArrayFromArrayBuffer(buf))
//     );
//   }
// }

// Use BroadcastChannel or Polyfill
// const BC =
//   typeof BroadcastChannel === "undefined"
//     ? LocalStoragePolyfill
//     : BroadcastChannel;

class Channel {
  final BroadcastChannel bc;
  final Set<BroadcastMessageCallback> subs;

  const Channel(this.bc, this.subs);
}

/**
 * @param {string} room
 * @return {Channel}
 */
Channel getChannel(String room) => channels.putIfAbsent(room, () {
      final subs = <BroadcastMessageCallback>{};
      final bc = BroadcastChannel(room);
      /**
     * @param {{data:ArrayBuffer}} e
     */
      bc.onMessage.listen(
        (e) => subs.forEach((sub) => sub(e.data)),
      );
      return Channel(
        bc,
        subs,
      );
    });

const broadcastChannelWeb = BroadcastChannelWebJs._();

class BroadcastChannelWebJs implements BroadcastChannelWeb {
  const BroadcastChannelWebJs._();

/**
 * Subscribe to global `publish` events.
 *
 * @function
 * @param {string} room
 * @param {function(any):any} f
 */
  @override
  void subscribe(String room, BroadcastMessageCallback f) =>
      getChannel(room).subs.add(f);

/**
 * Unsubscribe from `publish` global events.
 *
 * @function
 * @param {string} room
 * @param {function(any):any} f
 */
  @override
  void unsubscribe(String room, BroadcastMessageCallback f) =>
      getChannel(room).subs.remove(f);

/**
 * Publish data to all subscribers (including subscribers on this tab)
 *
 * @function
 * @param {string} room
 * @param {any} data
 */
  @override
  void publish(String room, Object data) {
    final c = getChannel(room);
    c.bc.postMessage(data);
    c.subs.forEach((sub) => sub(data));
  }
}
