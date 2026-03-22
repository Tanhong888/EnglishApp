import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:englishapp_desktop/app.dart';

void main() {
  testWidgets('app boots to splash entry', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const EnglishApp());
    await tester.pumpAndSettle();

    expect(find.text('英阅通'), findsOneWidget);
    expect(find.text('进入登录'), findsOneWidget);
  });
}
