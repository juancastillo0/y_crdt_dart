import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';

// import { AbstractType, Item } from "../internals.js"; // eslint-disable-line

/**
 * Check if `parent` is a parent of `child`.
 *
 * @param {AbstractType<any>} parent
 * @param {Item|null} child
 * @return {Boolean} Whether `parent` is a parent of `child`.
 *
 * @private
 * @function
 */
bool isParentOf(AbstractType parent, Item? child) {
  while (child != null) {
    if (child.parent == parent) {
      return true;
    }
    child = /** @type {AbstractType<any>} */ (child.parent as AbstractType)
        .innerItem;
  }
  return false;
}
