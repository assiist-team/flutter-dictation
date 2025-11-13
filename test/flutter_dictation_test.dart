import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_dictation/flutter_dictation.dart';

void main() {
  test('AudioService is a singleton', () {
    final service1 = AudioService();
    final service2 = AudioService();
    expect(service1, equals(service2));
  });
}
