import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';

void main() {
  test('crypto init', () {
    FlutterCryptography.defaultInstance.setUp();
    print('Done');
  });
}
