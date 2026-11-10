import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const redirectUri = 'fasofootpass://login-callback';

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
  User? get currentUser => _supabase.auth.currentUser;

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) => _supabase.auth.signInWithPassword(
    email: email.trim().toLowerCase(),
    password: password,
  );

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) => _supabase.auth.signUp(
    email: email.trim().toLowerCase(),
    password: password,
    emailRedirectTo: kIsWeb ? null : redirectUri,
    data: {'full_name': fullName.trim()},
  );

  Future<void> sendPasswordReset(String email) =>
      _supabase.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: kIsWeb ? null : redirectUri,
      );

  Future<bool> signInWithProvider(OAuthProvider provider) => _supabase.auth
      .signInWithOAuth(provider, redirectTo: kIsWeb ? null : redirectUri);

  Future<void> updatePassword(String password) async {
    await _supabase.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> signOut() => _supabase.auth.signOut();
}
