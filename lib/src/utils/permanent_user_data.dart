// import {
//   YArray,
//   YMap,
//   readDeleteSet,
//   writeDeleteSet,
//   createDeleteSet,
//   DSEncoderV1,
//   DSDecoderV1,
//   ID,
//   DeleteSet,
//   YArrayEvent,
//   Transaction,
//   Doc, // eslint-disable-line
// } from "../internals.js";

// import * as decoding from "lib0/decoding.js";

// import { mergeDeleteSets, isDeleted } from "./DeleteSet.js";

import 'dart:typed_data';

import 'package:y_crdt/src/types/y_array.dart';
import 'package:y_crdt/src/types/y_map.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

import '../lib0/decoding.dart' as decoding;

bool _defaultFilter(_, __) => true;

class PermanentUserData {
  /**
   * @param {Doc} doc
   * @param {YMap<any>} [storeType]
   */
  PermanentUserData(this.doc, [YMap<YMap<dynamic>>? storeType]) {
    this.yusers = storeType ?? doc.getMap<YMap<dynamic>>("users");

    /**
     * @param {YMap<any>} user
     * @param {string} userDescription
     */
    void initUser(YMap<dynamic> user, String userDescription, YMap<dynamic> _) {
      /**
       * @type {YList<Uint8Array>}
       */
      final ds = user.get("ds")! as YArray<Uint8List>;
      final ids = user.get("ids")! as YArray<int>;
      final addClientId = /** @param {number} clientid */ (int clientid) =>
          this.clients.set(clientid, userDescription);
      ds.observe(
          /** @param {YArrayEvent<any>} event */ (event, _) {
        event.changes.added.forEach((item) {
          item.content.getContent().forEach((encodedDs) {
            if (encodedDs is Uint8List) {
              this.dss.set(
                    userDescription,
                    mergeDeleteSets([
                      this.dss.get(userDescription) ?? createDeleteSet(),
                      readDeleteSet(
                          DSDecoderV1(decoding.createDecoder(encodedDs))),
                    ]),
                  );
            }
          });
        });
      });
      this.dss.set(
            userDescription,
            mergeDeleteSets(ds
                .map(
                  (encodedDs) => readDeleteSet(DSDecoderV1(
                    decoding.createDecoder(encodedDs),
                  )),
                )
                .toList()),
          );
      ids.observe(
        /** @param {YArrayEvent<any>} event */ (event, _) =>
            event.changes.added.forEach(
          (item) => item.content.getContent().cast<int>().forEach(addClientId),
        ),
      );
      ids.forEach(addClientId);
    }

    // observe users
    this.yusers.observe((event, _) {
      event.keysChanged.forEach((userDescription) => initUser(
            this.yusers.get(userDescription!)!,
            userDescription,
            this.yusers,
          ));
    });
    // add intial data
    this.yusers.forEach(initUser);
  }

  final Doc doc;
  late final YMap<YMap<dynamic>> yusers;
  /**
   * Maps from clientid to userDescription
   *
   * @type {Map<number,string>}
   */
  final clients = <int, String>{};

  /**
     * @type {Map<string,DeleteSet>}
     */
  final dss = <String, DeleteSet>{};

  /**
   * @param {Doc} doc
   * @param {number} clientid
   * @param {string} userDescription
   * @param {Object} [conf]
   * @param {function(Transaction, DeleteSet):boolean} [conf.filter]
   */
  void setUserMapping(
    Doc doc,
    int clientid,
    String userDescription, [
    bool Function(Transaction, DeleteSet) filter = _defaultFilter,
  ]) {
    final users = this.yusers;
    var user = users.get(userDescription);
    if (user == null) {
      user = YMap();
      user.set("ids", YArray<int>());
      user.set("ds", YArray<Uint8List>());
      users.set(userDescription, user);
    }
    user.get("ids").push([clientid]);
    users.observe((event, _) {
      Future.delayed(Duration.zero, () {
        final userOverwrite = users.get(userDescription);
        if (userOverwrite != user) {
          // user was overwritten, port all data over to the next user object
          // @todo Experiment with Y.Sets here
          user = userOverwrite;
          // @todo iterate over old type
          this.clients.forEach((clientid, _userDescription) {
            if (userDescription == _userDescription) {
              user!.get("ids").push([clientid]);
            }
          });
          final encoder = DSEncoderV1();
          final ds = this.dss.get(userDescription);
          if (ds != null) {
            writeDeleteSet(encoder, ds);
            user!.get("ds").push([encoder.toUint8Array()]);
          }
        }
      });
    });
    doc.on("afterTransaction",
        /** @param {Transaction} transaction */ (params) {
      final transaction = params[0] as Transaction;
      Future.delayed(Duration.zero, () {
        final yds = user!.get("ds") as YArray<Uint8List>;
        final ds = transaction.deleteSet;
        if (transaction.local &&
            ds.clients.length > 0 &&
            filter(transaction, ds)) {
          final encoder = DSEncoderV1();
          writeDeleteSet(encoder, ds);
          yds.push([encoder.toUint8Array()]);
        }
      });
    });
  }

  /**
   * @param {number} clientid
   * @return {any}
   */
  String? getUserByClientId(int clientid) {
    return this.clients.get(clientid);
  }

  /**
   * @param {ID} id
   * @return {string | null}
   */
  String? getUserByDeletedId(ID id) {
    for (final entry in this.dss.entries) {
      if (isDeleted(entry.value, id)) {
        return entry.key;
      }
    }
    return null;
  }
}
