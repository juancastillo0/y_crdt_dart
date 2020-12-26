// import { Observable } from "lib0/observable.js";

// import {
//   Doc, // eslint-disable-line
// } from "../internals.js";

import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/observable.dart';

/**
 * This is an abstract interface that all Connectors should implement to keep them interchangeable.
 *
 * @note This interface is experimental and it is not advised to actually inherit this class.
 *       It just serves as typing information.
 *
 * @extends {Observable<any>}
 */
class AbstractConnector extends Observable {
  /**
   * @param {Doc} ydoc
   * @param {any} awareness
   */
  AbstractConnector(this.doc, this.awareness);
  final Doc doc;
  final Object awareness;
}
