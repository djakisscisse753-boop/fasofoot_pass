import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../admin/admin_dashboard_screen.dart';
import '../tickets/qr_scanner_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _client = Supabase.instance.client;
  final _nameController = TextEditingController();
  late Future<Map<String, dynamic>> _profileFuture;
  String? _favoriteClubId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Session utilisateur absente.');
    final results = await Future.wait([
      _client.from('profiles').select().eq('id', user.id).maybeSingle(),
      _client.from('clubs').select('id, name').order('name'),
    ]);
    final profile = results[0] as Map<String, dynamic>? ?? <String, dynamic>{};
    final clubs = (results[1] as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    _nameController.text = profile['full_name'] as String? ?? '';
    _favoriteClubId = profile['favorite_club_id'] as String?;
    return {
      'profile': profile,
      'clubs': clubs,
      'identity': user.email ?? user.phone ?? 'Compte connecté',
    };
  }

  Future<void> _saveProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await _client
          .from('profiles')
          .update({
            'full_name': _nameController.text.trim(),
            'favorite_club_id': _favoriteClubId,
          })
          .eq('id', user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil mis à jour.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’enregistrer le profil.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101820),
    appBar: AppBar(
      title: const Text('Mon profil'),
      backgroundColor: const Color(0xFF101820),
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          tooltip: 'Se déconnecter',
          onPressed: () => _client.auth.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Impossible de charger le profil.',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }
        final data = snapshot.data!;
        final profile = data['profile'] as Map<String, dynamic>;
        final clubs = data['clubs'] as List<Map<String, dynamic>>;
        final role = profile['role'] as String? ?? 'supporter';
        final canScan = const {'agent_stade', 'super_admin'}.contains(role);
        final canManage = const {
          'admin_competition',
          'admin_club',
          'super_admin',
        }.contains(role);
        final clubIds = clubs.map((club) => club['id'] as String).toSet();
        if (_favoriteClubId != null && !clubIds.contains(_favoriteClubId)) {
          _favoriteClubId = null;
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const CircleAvatar(
              radius: 38,
              backgroundColor: Color(0xFF008751),
              child: Icon(Icons.person, size: 42, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              data['identity'] as String,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nom complet',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFCD116)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _favoriteClubId ?? 'none',
              dropdownColor: const Color(0xFF1A2634),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Club favori',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
              ),
              items: [
                const DropdownMenuItem(value: 'none', child: Text('Aucun')),
                ...clubs.map(
                  (club) => DropdownMenuItem<String>(
                    value: club['id'] as String,
                    child: Text(club['name'] as String),
                  ),
                ),
              ],
              onChanged: (value) => setState(
                () => _favoriteClubId = value == 'none' ? null : value,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _saveProfile,
              child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
            ),
            if (canScan) ...[
              const SizedBox(height: 28),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              Text(
                'Espace stade · $role',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QRScannerScreen()),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Contrôler un billet'),
              ),
            ],
            if (canManage) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminDashboardScreen(
                      role: role,
                      managedClubId: profile['managed_club_id'] as String?,
                    ),
                  ),
                ),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Ouvrir l’administration'),
              ),
            ],
          ],
        );
      },
    ),
  );
}
