import 'package:flutter_test/flutter_test.dart';

import 'package:fd/main.dart';

void main() {
  testWidgets('app shows startup screen', (tester) async {
    await tester.pumpWidget(const FaceLockApp());
    expect(find.text('Starting face lock'), findsOneWidget);
  });
}
