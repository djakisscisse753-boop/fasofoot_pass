import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isRegistering = false;
  bool _isLoading = false;
  bool _passwordVisible = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (_isRegistering) {
        final response = await _authService.signUpWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
          fullName: _nameController.text,
        );
        if (response.session == null && mounted) {
          _showMessage(
            'Compte créé. Consulte ta boîte e-mail et confirme ton adresse avant de te connecter.',
          );
          setState(() {
            _isRegistering = false;
            _passwordController.clear();
            _confirmationController.clear();
          });
        }
      } else {
        await _authService.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWith(OAuthProvider provider) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final launched = await _authService.signInWithProvider(provider);
      if (!launched && mounted) {
        setState(() => _error = 'La fenêtre de connexion n’a pas pu s’ouvrir.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestPasswordReset() async {
    final email = _emailController.text.trim();
    if (!_validEmail(email)) {
      setState(() => _error = 'Saisis d’abord une adresse e-mail valide.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _authService.sendPasswordReset(email);
      if (mounted) {
        _showMessage(
          'Si un compte correspond à cette adresse, un lien de réinitialisation vient d’être envoyé.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    return _validEmail(email) ? null : 'Saisis une adresse e-mail valide.';
  }

  bool _validEmail(String email) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 10) return '10 caractères minimum.';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Ajoute au moins une lettre et un chiffre.';
    }
    return null;
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Adresse e-mail ou mot de passe incorrect.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirme ton adresse e-mail depuis le message reçu.';
    }
    if (message.contains('user already registered')) {
      return 'Un compte utilise déjà cette adresse. Connecte-toi plutôt.';
    }
    if (message.contains('password should be') ||
        message.contains('weak password')) {
      return 'Choisis un mot de passe plus robuste.';
    }
    if (message.contains('provider is not enabled') ||
        message.contains('unsupported provider')) {
      return 'Ce fournisseur doit d’abord être activé dans la configuration Auth de Supabase.';
    }
    if (message.contains('rate limit') ||
        message.contains('too many requests')) {
      return 'Trop de tentatives. Attends quelques minutes avant de réessayer.';
    }
    if (error is AuthException) {
      return 'La connexion n’a pas abouti. Vérifie tes informations et réessaie.';
    }
    return 'Une erreur est survenue. Vérifie ta connexion Internet et réessaie.';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: Colors.white54),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.045),
    labelStyle: const TextStyle(color: Colors.white60),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.white12),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFFCD116), width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0B151D),
      body: Stack(
        children: [
          Positioned(
            top: -size.width * 0.38,
            right: -size.width * 0.26,
            child: Container(
              width: size.width * 0.95,
              height: size.width * 0.95,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF008751).withValues(alpha: 0.18),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF14212B,
                          ).withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white10),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 30,
                              offset: Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isRegistering
                                  ? 'Créer mon compte'
                                  : 'Ravi de te revoir',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isRegistering
                                  ? 'Rejoins les supporters du football burkinabè.'
                                  : 'Connecte-toi pour retrouver tes billets et tes clubs.',
                              style: const TextStyle(
                                color: Colors.white60,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Row(
                              children: [
                                Expanded(
                                  child: _ProviderButton(
                                    label: 'Google',
                                    icon: Icons.g_mobiledata,
                                    onPressed: _isLoading
                                        ? null
                                        : () =>
                                              _signInWith(OAuthProvider.google),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ProviderButton(
                                    label: 'Apple',
                                    icon: Icons.apple,
                                    onPressed: _isLoading
                                        ? null
                                        : () =>
                                              _signInWith(OAuthProvider.apple),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const _OrDivider(),
                            const SizedBox(height: 18),
                            Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  if (_isRegistering) ...[
                                    TextFormField(
                                      controller: _nameController,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      textInputAction: TextInputAction.next,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: _inputDecoration(
                                        label: 'Nom complet',
                                        icon: Icons.person_outline,
                                      ),
                                      validator: (value) =>
                                          (value?.trim().length ?? 0) < 2
                                          ? 'Saisis ton nom complet.'
                                          : null,
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autocorrect: false,
                                    autofillHints: const [AutofillHints.email],
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _inputDecoration(
                                      label: 'Adresse e-mail',
                                      icon: Icons.mail_outline,
                                    ),
                                    validator: _validateEmail,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: !_passwordVisible,
                                    textInputAction: _isRegistering
                                        ? TextInputAction.next
                                        : TextInputAction.done,
                                    autofillHints: _isRegistering
                                        ? const [AutofillHints.newPassword]
                                        : const [AutofillHints.password],
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _inputDecoration(
                                      label: 'Mot de passe',
                                      icon: Icons.lock_outline,
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(
                                          () => _passwordVisible =
                                              !_passwordVisible,
                                        ),
                                        icon: Icon(
                                          _passwordVisible
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ),
                                    validator: _isRegistering
                                        ? _validatePassword
                                        : (value) => (value?.isEmpty ?? true)
                                              ? 'Saisis ton mot de passe.'
                                              : null,
                                    onFieldSubmitted: (_) {
                                      if (!_isRegistering) _submit();
                                    },
                                  ),
                                  if (_isRegistering) ...[
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _confirmationController,
                                      obscureText: !_passwordVisible,
                                      textInputAction: TextInputAction.done,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: _inputDecoration(
                                        label: 'Confirmer le mot de passe',
                                        icon: Icons.lock_reset_outlined,
                                      ),
                                      validator: (value) =>
                                          value != _passwordController.text
                                          ? 'Les mots de passe ne correspondent pas.'
                                          : null,
                                      onFieldSubmitted: (_) => _submit(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (!_isRegistering)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : _requestPasswordReset,
                                  child: const Text('Mot de passe oublié ?'),
                                ),
                              ),
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFFF8C82),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 54,
                              child: FilledButton(
                                onPressed: _isLoading ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF008751),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _isRegistering
                                            ? 'Créer mon compte'
                                            : 'Se connecter',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  _isRegistering
                                      ? 'Tu as déjà un compte ? '
                                      : 'Nouveau sur FasoFoot Pass ? ',
                                  style: const TextStyle(color: Colors.white60),
                                ),
                                TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () => setState(() {
                                          _isRegistering = !_isRegistering;
                                          _error = null;
                                          _formKey.currentState?.reset();
                                        }),
                                  child: Text(
                                    _isRegistering
                                        ? 'Connexion'
                                        : 'Inscription',
                                    style: const TextStyle(
                                      color: Color(0xFFFCD116),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Tes informations sont protégées par Supabase Auth.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: const Color(0xFF008751),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF008751).withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.sports_soccer, color: Colors.white, size: 38),
      ),
      const SizedBox(height: 14),
      const Text(
        'FASOFOOT PASS',
        style: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.1,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Le football burkinabè, tous ensemble.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white60),
      ),
    ],
  );
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 22),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white24),
      minimumSize: const Size.fromHeight(48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
  );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider(color: Colors.white12)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'OU PAR E-MAIL',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.48),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
      const Expanded(child: Divider(color: Colors.white12)),
    ],
  );
}
