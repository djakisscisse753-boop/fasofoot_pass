import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fasofoot_pass/main.dart';

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });

  testWidgets('shows phone sign-in when there is no session', (tester) async {
    await tester.pumpWidget(const FasoFootApp());
    await tester.pumpAndSettle();

    expect(find.text('FASOFOOT PASS'), findsOneWidget);
    expect(find.text('Recevoir un code par SMS'), findsOneWidget);
  });
}
