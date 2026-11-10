import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _auth = AuthService();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _auth.updatePassword(_passwordController.text);
      await _auth.signOut();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Le mot de passe n’a pas pu être modifié. Demande un nouveau lien de réinitialisation.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _passwordValidator(String? value) {
    final password = value ?? '';
    if (password.length < 10) return '10 caractères minimum.';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Ajoute au moins une lettre et un chiffre.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0B151D),
    appBar: AppBar(
      title: const Text('Nouveau mot de passe'),
      backgroundColor: const Color(0xFF0B151D),
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.lock_reset,
                  color: Color(0xFFFCD116),
                  size: 56,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Choisis un nouveau mot de passe',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Utilise au moins 10 caractères, avec une lettre et un chiffre.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nouveau mot de passe',
                    border: OutlineInputBorder(),
                  ),
                  validator: _passwordValidator,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmationController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Confirmer le mot de passe',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value != _passwordController.text
                      ? 'Les mots de passe ne correspondent pas.'
                      : null,
                  onFieldSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF008751),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer le nouveau mot de passe'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
