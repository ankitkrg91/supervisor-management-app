import 'package:flutter_test/flutter_test.dart';
import 'package:supervisor_app/main.dart';

void main() {
  testWidgets('Supervisor app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const SupervisorApp());

    expect(find.byType(SupervisorApp), findsOneWidget);
  });
}
