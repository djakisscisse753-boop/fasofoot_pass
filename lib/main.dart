import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Config/constants.dart';
import 'provider/payment_provider.dart';
import 'screens/home/home_screen.dart';
import 'screens/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabaseAnonKey,
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
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF008751),
            primary: const Color(0xFF008751),
            secondary: const Color(0xFFDA121A),
          ),
          useMaterial3: true,
        ),
        home: StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
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
