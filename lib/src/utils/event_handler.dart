// import * as f from "lib0/function.js";

import 'package:y_crdt/src/y_crdt_base.dart';

/**
 * General event handler implementation.
 *
 * @template ARG0, ARG1
 *
 * @private
 */
class EventHandler<ARG0, ARG1> {
  /**
     * @type {List<function(ARG0, ARG1):void>}
     */
  List<void Function(ARG0, ARG1)> l = [];
}

/**
 * @template ARG0,ARG1
 * @returns {EventHandler<ARG0,ARG1>}
 *
 * @private
 * @function
 */
EventHandler<ARG0, ARG1> createEventHandler<ARG0, ARG1>() => EventHandler();

/**
 * Adds an event listener that is called when
 * {@link EventHandler#callEventListeners} is called.
 *
 * @template ARG0,ARG1
 * @param {EventHandler<ARG0,ARG1>} eventHandler
 * @param {function(ARG0,ARG1):void} f The event handler.
 *
 * @private
 * @function
 */
void addEventHandlerListener<ARG0, ARG1>(
        EventHandler<ARG0, ARG1> eventHandler, void Function(ARG0, ARG1) f) =>
    eventHandler.l.add(f);

/**
 * Removes an event listener.
 *
 * @template ARG0,ARG1
 * @param {EventHandler<ARG0,ARG1>} eventHandler
 * @param {function(ARG0,ARG1):void} f The event handler that was added with
 *                     {@link EventHandler#addEventListener}
 *
 * @private
 * @function
 */
void removeEventHandlerListener<ARG0, ARG1>(
    EventHandler<ARG0, ARG1> eventHandler, void Function(ARG0, ARG1) f) {
  final l = eventHandler.l;
  final len = l.length;
  eventHandler.l = l.where((g) => f != g).toList();
  if (len == eventHandler.l.length) {
    logger.e("[yjs] Tried to remove event handler that doesn't exist.");
  }
}

/**
 * Removes all event listeners.
 * @template ARG0,ARG1
 * @param {EventHandler<ARG0,ARG1>} eventHandler
 *
 * @private
 * @function
 */
void removeAllEventHandlerListeners<ARG0, ARG1>(
    EventHandler<ARG0, ARG1> eventHandler) {
  eventHandler.l.length = 0;
}

/**
 * Call all event listeners that were added via
 * {@link EventHandler#addEventListener}.
 *
 * @template ARG0,ARG1
 * @param {EventHandler<ARG0,ARG1>} eventHandler
 * @param {ARG0} arg0
 * @param {ARG1} arg1
 *
 * @private
 * @function
 */
void callEventHandlerListeners<ARG0, ARG1>(
        EventHandler<ARG0, ARG1> eventHandler, ARG0 arg0, ARG1 arg1) =>
    eventHandler.l.forEach((f) => f(arg0, arg1));
