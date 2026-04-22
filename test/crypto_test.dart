import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:cryptography/dart.dart';

void main() {
  test('crypto init', () {
    print('DartCryptography: ${DartCryptography.defaultInstance.aesGcm(secretKeyLength: 32)}');
    print('FlutterCryptography: ${FlutterCryptography.defaultInstance.aesGcm(secretKeyLength: 32)}');
  });
}
