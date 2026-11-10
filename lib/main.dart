import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Config/constants.dart';
import 'Config/theme.dart';
import 'provider/payment_provider.dart';
import 'screens/home/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/password_recovery_screen.dart';
import 'screens/maintenance/maintenance_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const FasoFootApp());
}

class FasoFootApp extends StatelessWidget {
  const FasoFootApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PaymentProvider()),
        // Ajoute tes autres providers ici s'ils existent :
        // ChangeNotifierProvider(create: (_) => MatchProvider()),
        // ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        builder: (context, navigator) =>
            MaintenanceGate(child: navigator ?? const SizedBox.shrink()),
        theme: AppTheme.dark,
        home: StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
              return const PasswordRecoveryScreen();
            }
            final session =
                snapshot.data?.session ??
                Supabase.instance.client.auth.currentSession;
            return session == null ? const LoginScreen() : const HomeScreen();
          },
        ),
      ),
    );
  }
}
