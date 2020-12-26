// import {
//   AbstractType, // eslint-disable-line
// } from "../internals.js";

import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';

/**
 * Convenient helper to log type information.
 *
 * Do not use in productive systems as the output can be immense!
 *
 * @param {AbstractType<any>} type
 */
void logType(AbstractType type) {
  final res = <Item>[];
  var n = type.innerStart;
  while (n != null) {
    res.add(n);
    n = n.right;
  }
  print("Children: $res");
  print(
      "Children content: ${res.where((m) => !m.deleted).map((m) => m.content)}");
}
