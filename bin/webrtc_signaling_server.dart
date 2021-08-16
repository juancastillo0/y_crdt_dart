import 'package:y_crdt/src/external/webrtc_signaling_server.dart';

Future<void> main() async {
  final subs = await runServer();
  await subs.connectionsSubs.asFuture();
}
