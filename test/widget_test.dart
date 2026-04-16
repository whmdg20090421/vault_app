import 'package:flutter_test/flutter_test.dart';

import 'package:vault/main.dart';

void main() {
  testWidgets('Bottom navigation works', (WidgetTester tester) async {
    await tester.pumpWidget(const TianyanApp());
    await tester.pumpAndSettle();

    expect(find.text('主页'), findsWidgets);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();

    expect(find.text('主题'), findsOneWidget);
    expect(find.text('赛博朋克'), findsOneWidget);
  });
}
