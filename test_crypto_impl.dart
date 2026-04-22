import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

void main() async {
  print('Available: ${AesGcm.with256bits().runtimeType}');
}
