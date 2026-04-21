import 'dart:convert';
void main() {
  final name = "Novel_21198454_在规则怪谈中跟自己妹妹谈恋爱.txt";
  final bytes = utf8.encode(name);
  print("Plaintext bytes: ${bytes.length}");
  final cipherLength = bytes.length + 16;
  print("Ciphertext bytes: $cipherLength");
  final base64Length = ((cipherLength + 2) ~/ 3) * 4;
  print("Base64 length (with padding): $base64Length");
  print("Base64Url length (no padding): ${(cipherLength * 4 / 3).ceil()}");
}
