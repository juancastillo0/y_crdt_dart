import 'package:y_crdt/src/y_crdt_base.dart';

/**
 * Handles named events.
 *
 * @template N
 */
class Observable<N> {
  Observable();
  /**
     * Some desc.
     * @type {Map<N, any>}
     */
  var innerObservers = <N, Set<void Function(List<dynamic>)>>{};

  /**
   * @param {N} name
   * @param {function} f
   */
  void on(N name, void Function(List<dynamic>) f) {
    this.innerObservers.putIfAbsent(name, () => {}).add(f);
  }

  /**
   * @param {N} name
   * @param {function} f
   */
  void once(N name, void Function() f) {
    /**
     * @param  {...any} args
     */
    void _f(List<dynamic> args) {
      this.off(name, _f);
      f();
    }

    this.on(name, _f);
  }

  /**
   * @param {N} name
   * @param {function} f
   */
  void off(N name, void Function(List<dynamic>) f) {
    final observers = this.innerObservers.get(name);
    if (observers != null) {
      observers.remove(f);
      if (observers.length == 0) {
        this.innerObservers.remove(name);
      }
    }
  }

  /**
   * Emit a named event. All registered event listeners that listen to the
   * specified name will receive the event.
   *
   * @todo This should catch exceptions
   *
   * @param {N} name The event name.
   * @param {Array<any>} args The arguments that are applied to the event listener.
   */
  void emit(N name, List<dynamic> args) {
    // copy all listeners to an array first to make sure that no event is emitted to listeners that are subscribed while the event handler is called.
    return (this.innerObservers.get(name) ?? {})
        .toList()
        .forEach((f) => f(args));
  }

  void destroy() {
    this.innerObservers = {};
  }
}
