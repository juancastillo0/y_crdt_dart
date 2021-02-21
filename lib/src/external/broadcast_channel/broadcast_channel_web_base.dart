typedef BroadcastMessageCallback = void Function(Object? data);

const broadcastChannelWeb = BroadcastChannelWeb._();

class BroadcastChannelWeb {
  const BroadcastChannelWeb._();

/**
 * Subscribe to global `publish` events.
 *
 * @function
 * @param {string} room
 * @param {function(any):any} f
 */
  void subscribe(String room, BroadcastMessageCallback f) {}

/**
 * Unsubscribe from `publish` global events.
 *
 * @function
 * @param {string} room
 * @param {function(any):any} f
 */
  void unsubscribe(String room, BroadcastMessageCallback f) {}

/**
 * Publish data to all subscribers (including subscribers on this tab)
 *
 * @function
 * @param {string} room
 * @param {any} data
 */
  void publish(String room, Object data) {}
}
