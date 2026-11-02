// 基础冒烟测试：验证未同意隐私政策时先展示隐私提示页。

import 'package:flutter_test/flutter_test.dart';

import 'package:fmlink/main.dart';

void main() {
  testWidgets('未同意隐私政策时展示隐私提示', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(initialConsent: false));
    await tester.pump();

    expect(find.text('隐私政策提示'), findsOneWidget);
    expect(find.text('同意'), findsOneWidget);
  });
}
