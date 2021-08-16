import 'dart:async';
import 'package:flutter/material.dart';
import 'package:test/test.dart';
import 'package:y_crdt/src/external/webrtc_signaling.dart';
import 'package:y_crdt/src/external/webrtc_signaling_server.dart';
import 'package:y_crdt/y_crdt.dart';

Future<void> _spawnIsolate(String url) async {
  final ydoc1 = Doc();
  final provider1 = WebrtcProvider(
    'your-room-name',
    ydoc1,
    signaling: [url],
  );
  provider1.on('synced', (args) {
    final synched = (args.first as Map<String, dynamic>)['synced'] as bool;
    print('1 synched $args');
  });
  provider1.on('peers', (args) {
    print('1 peers $args');
  });

  final arr = ydoc1.getArray('bi');
  arr.push(['a']);
  await Future.delayed(Duration(seconds: 4));
  return null;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  late WebRtcSignalingServer server;
  setUp(() async {
    server = await runServer();
  });

  tearDown(() async {
    await server.inner.close(force: true);
  });

  test(
    'initial',
    () async {
      final url = 'ws://localhost:${server.inner.port}';
      final ydoc2 = Doc();
      final provider2 = WebrtcProvider(
        'your-room-name',
        ydoc2,
        signaling: [url],
        signalingContext: SignalingContext(),
      );

      provider2.on('synced', (args) {
        final synched = (args.first as Map<String, dynamic>)['synced'] as bool;
        print('2 synched $args');
      });
      provider2.on('peers', (args) {
        print('2 peers $args');
      });

      final c = Completer();
      final arr2 = ydoc2.getArray('bi');
      arr2.observe((e, t) {
        final added = e.changes.added;
        expect(added.length, 1);
        expect(added.first.content, TypeMatcher<ContentString>());
        expect((added.first.content as ContentString).str, 'a');
        c.complete();
      });

      await _spawnIsolate(url);

      await c.future;
    },
    timeout: const Timeout(Duration(seconds: 9)),
  );
}
