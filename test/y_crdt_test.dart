import 'package:test/test.dart';
import 'package:y_crdt/y_crdt.dart';

void main() {
  group('A group of tests', () {
    Awesome? awesome;

    setUp(() {
      awesome = Awesome();
    });

    test('First Test', () {
      expect(awesome!.isAwesome, isTrue);
    });
  });
}
