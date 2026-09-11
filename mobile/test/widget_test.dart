import 'package:flutter_test/flutter_test.dart';
import 'package:voice_buddy/main.dart';

void main() {
  testWidgets('Voice Buddy app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VoiceBuddyApp());
    expect(find.byType(VoiceBuddyApp), findsOneWidget);
  });
}
