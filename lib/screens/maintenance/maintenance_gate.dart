import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MaintenanceGate extends StatefulWidget {
  final Widget child;

  const MaintenanceGate({super.key, required this.child});

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  final _client = Supabase.instance.client;
  String? _maintenanceMessage;
  String? _errorMessage;
  bool _checking = true;
  bool _refreshInProgress = false;
  bool _refreshAgain = false;
  Timer? _refreshTimer;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _refreshMaintenanceState();
    _authSubscription = _client.auth.onAuthStateChange.listen((_) {
      _refreshMaintenanceState();
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshMaintenanceState(),
    );
  }

  Future<void> _refreshMaintenanceState() async {
    if (_refreshInProgress) {
      _refreshAgain = true;
      return;
    }
    _refreshInProgress = true;
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _maintenanceMessage = null;
            _errorMessage = null;
            _checking = false;
          });
        }
        return;
      }
      final settings = await _client
          .from('app_settings')
          .select('maintenance_enabled, maintenance_message')
          .eq('id', 1)
          .maybeSingle();
      if (settings == null || settings['maintenance_enabled'] != true) {
        if (mounted) {
          setState(() {
            _maintenanceMessage = null;
            _errorMessage = null;
            _checking = false;
          });
        }
        return;
      }

      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _maintenanceMessage = profile?['role'] == 'super_admin'
            ? null
            : settings['maintenance_message'] as String? ??
                  'FasoFoot Pass est temporairement en maintenance. Merci de revenir bientôt.';
        _errorMessage = null;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Impossible de vérifier l’état du service. Vérifiez votre connexion puis réessayez.';
        _checking = false;
      });
    } finally {
      _refreshInProgress = false;
      if (_refreshAgain && mounted) {
        _refreshAgain = false;
        unawaited(_refreshMaintenanceState());
      }
    }
  }

  void _retry() => _refreshMaintenanceState();

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF101820),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF008751)),
        ),
      );
    }
    final message = _errorMessage ?? _maintenanceMessage;
    if (message == null) return widget.child;
    return _MaintenanceScreen(message: message, onRetry: _retry);
  }
}

class _MaintenanceScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _MaintenanceScreen({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101820),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFF008751).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.build_circle_outlined,
                  size: 48,
                  color: Color(0xFFFCD116),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Maintenance en cours',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Vérifier à nouveau'),
              ),
              const SizedBox(height: 16),
              const Text(
                'FasoFoot Pass · Le football burkinabè dans votre poche',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
