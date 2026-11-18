import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fasofoot_pass/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });

  testWidgets('shows email sign-in when there is no session', (tester) async {
    await tester.pumpWidget(const FasoFootApp());
    await tester.pumpAndSettle();

    expect(find.text('FASOFOOT PASS'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
