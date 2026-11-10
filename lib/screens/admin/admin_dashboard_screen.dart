import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminDashboardScreen extends StatelessWidget {
  final String role;
  final String? managedClubId;

  const AdminDashboardScreen({
    super.key,
    required this.role,
    this.managedClubId,
  });

  @override
  Widget build(BuildContext context) {
    final canManageSport = role == 'admin_competition' || role == 'super_admin';
    final canManageShop = role == 'admin_club' || role == 'super_admin';
    final pages = <Widget>[
      if (canManageSport) const _MatchAdminTab(),
      if (canManageSport) const _ResultAdminTab(),
      if (canManageShop)
        _ProductAdminTab(role: role, managedClubId: managedClubId),
      if (canManageShop)
        _ClubAdminTab(role: role, managedClubId: managedClubId),
      if (canManageShop)
        _OrderAdminTab(role: role, managedClubId: managedClubId),
      if (role == 'super_admin') const _RefundAdminTab(),
      if (role == 'super_admin') const _MaintenanceAdminTab(),
    ];
    final tabs = <Tab>[
      if (canManageSport)
        const Tab(icon: Icon(Icons.sports_soccer), text: 'Matchs'),
      if (canManageSport)
        const Tab(icon: Icon(Icons.scoreboard), text: 'Résultats'),
      if (canManageShop)
        const Tab(icon: Icon(Icons.storefront), text: 'Articles'),
      if (canManageShop)
        const Tab(icon: Icon(Icons.shield_outlined), text: 'Clubs'),
      if (canManageShop)
        const Tab(icon: Icon(Icons.receipt_long), text: 'Commandes'),
      if (role == 'super_admin')
        const Tab(icon: Icon(Icons.price_check), text: 'Remboursements'),
      if (role == 'super_admin')
        const Tab(icon: Icon(Icons.build_circle_outlined), text: 'Maintenance'),
    ];
    return DefaultTabController(
      length: pages.length,
      child: Scaffold(
        backgroundColor: const Color(0xFF101820),
        appBar: AppBar(
          title: const Text('Administration'),
          backgroundColor: const Color(0xFF101820),
          foregroundColor: Colors.white,
          bottom: TabBar(tabs: tabs, isScrollable: true),
        ),
        body: TabBarView(children: pages),
      ),
    );
  }
}

class _MaintenanceAdminTab extends StatefulWidget {
  const _MaintenanceAdminTab();

  @override
  State<_MaintenanceAdminTab> createState() => _MaintenanceAdminTabState();
}

class _MaintenanceAdminTabState extends State<_MaintenanceAdminTab> {
  final _db = Supabase.instance.client;
  final _messageController = TextEditingController(
    text:
        'FasoFoot Pass est temporairement en maintenance. Merci de revenir bientôt.',
  );
  late Future<Map<String, dynamic>> _future;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _future.then((settings) {
      if (mounted) {
        _messageController.text = settings['maintenance_message'] as String;
      }
    });
  }

  Future<Map<String, dynamic>> _load() async {
    final row = await _db
        .from('app_settings')
        .select('maintenance_enabled, maintenance_message, updated_at')
        .eq('id', 1)
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> _setMaintenance(bool enabled) async {
    final message = _messageController.text.trim();
    if (message.length < 10 || message.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le message doit contenir entre 10 et 500 caractères.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A2634),
        title: Text(
          enabled ? 'Activer la maintenance ?' : 'Désactiver la maintenance ?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          enabled
              ? 'Les supporters verront le message de maintenance. Le super administrateur conservera l’accès.'
              : 'L’application redeviendra accessible aux supporters.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(enabled ? 'Activer' : 'Désactiver'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _db.rpc(
        'set_app_maintenance',
        params: {'p_enabled': enabled, 'p_message': message},
      );
      final future = _load();
      setState(() {
        _future = future;
      });
      final settings = await future;
      if (mounted) {
        _messageController.text = settings['maintenance_message'] as String;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled ? 'Maintenance activée.' : 'Maintenance désactivée.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de modifier le mode maintenance.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return const Center(
          child: Text('Impossible de charger le réglage de maintenance.'),
        );
      }
      final enabled = snapshot.data!['maintenance_enabled'] == true;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: const Color(0xFF1A2634),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        enabled ? Icons.build_circle : Icons.check_circle,
                        color: enabled
                            ? const Color(0xFFFCD116)
                            : const Color(0xFF7ED6A5),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          enabled
                              ? 'Application en maintenance'
                              : 'Application accessible',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Le super administrateur garde l’accès pour gérer l’application et désactiver la maintenance. Les autres comptes sont redirigés vers le message ci-dessous.',
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _messageController,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Message affiché aux supporters',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _setMaintenance(!enabled),
                      style: FilledButton.styleFrom(
                        backgroundColor: enabled
                            ? const Color(0xFF008751)
                            : const Color(0xFFDA291C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(enabled ? Icons.play_arrow : Icons.build),
                      label: Text(
                        _saving
                            ? 'Enregistrement…'
                            : enabled
                            ? 'Désactiver la maintenance'
                            : 'Activer la maintenance',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _RefundAdminTab extends StatefulWidget {
  const _RefundAdminTab();

  @override
  State<_RefundAdminTab> createState() => _RefundAdminTabState();
}

class _RefundAdminTabState extends State<_RefundAdminTab> {
  final _db = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _db
        .from('tickets')
        .select(
          'id, category_name, customer_name, customer_phone, price, '
          'transaction_id, created_at, refund_resolution, refund_reference, '
          'refund_note, refund_resolved_at',
        )
        .eq('status', 'refund_required')
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _resolve(Map<String, dynamic> ticket, String resolution) async {
    final reference = TextEditingController();
    final note = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final isRefund = resolution == 'refunded';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A2634),
        title: Text(
          isRefund ? 'Confirmer le remboursement' : 'Confirmer l’annulation',
          style: const TextStyle(color: Colors.white),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isRefund
                    ? 'Cette action enregistre un remboursement effectué dans YengaPay.'
                    : 'Cette action enregistre un paiement annulé ou reversé par YengaPay.',
                style: const TextStyle(color: Colors.white70),
              ),
              TextFormField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'Référence YengaPay',
                ),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? 'Saisissez une référence valide.'
                    : null,
              ),
              TextFormField(
                controller: note,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Note interne (facultative)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, formKey.currentState!.validate()),
            child: const Text('Enregistrer la résolution'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _db.rpc(
          'resolve_ticket_refund',
          params: {
            'p_ticket_id': ticket['id'],
            'p_resolution': resolution,
            'p_reference': reference.text.trim(),
            'p_note': note.text.trim(),
          },
        );
        if (mounted) {
          setState(() {
            _future = _load();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Résolution enregistrée.')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La résolution n’a pas été enregistrée. Vérifiez la référence et les droits.',
              ),
            ),
          );
        }
      }
    }
    reference.dispose();
    note.dispose();
  }

  String _resolutionLabel(String resolution) => switch (resolution) {
    'refunded' => 'Remboursé',
    'payment_reversed' => 'Paiement annulé / reversé',
    _ => 'À traiter',
  };

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(
          child: Text('Impossible de charger les remboursements à vérifier.'),
        );
      }
      final tickets = snapshot.data ?? const <Map<String, dynamic>>[];
      return RefreshIndicator(
        onRefresh: () async {
          final future = _load();
          setState(() {
            _future = future;
          });
          await future;
        },
        child: tickets.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 100),
                  Center(
                    child: Text(
                      'Aucun paiement en attente de vérification.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: tickets.length,
                itemBuilder: (context, index) {
                  final ticket = tickets[index];
                  final resolution =
                      ticket['refund_resolution']?.toString() ?? 'open';
                  final isOpen = resolution == 'open';
                  final created = DateTime.tryParse(
                    ticket['created_at']?.toString() ?? '',
                  )?.toLocal();
                  return Card(
                    color: const Color(0xFF1A2634),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${ticket['customer_name'] ?? 'Supporter'} · ${ticket['customer_phone'] ?? 'Téléphone indisponible'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${ticket['category_name']} · ${ticket['price']} FCFA · ${created == null ? '' : '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year}'}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Text(
                            'Transaction : ${ticket['transaction_id'] ?? 'Non renseignée'}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          if (!isOpen) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${_resolutionLabel(resolution)} · Réf. ${ticket['refund_reference']}',
                              style: const TextStyle(
                                color: Color(0xFF7ED6A5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if ((ticket['refund_note'] as String?)
                                    ?.isNotEmpty ==
                                true)
                              Text(
                                ticket['refund_note'] as String,
                                style: const TextStyle(color: Colors.white60),
                              ),
                          ],
                          if (isOpen) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _resolve(ticket, 'refunded'),
                                  icon: const Icon(Icons.payments_outlined),
                                  label: const Text('Remboursement effectué'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _resolve(ticket, 'payment_reversed'),
                                  icon: const Icon(Icons.undo),
                                  label: const Text('Paiement annulé'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      );
    },
  );
}

class _MatchAdminTab extends StatefulWidget {
  const _MatchAdminTab();

  @override
  State<_MatchAdminTab> createState() => _MatchAdminTabState();
}

class _MatchAdminTabState extends State<_MatchAdminTab> {
  final _db = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _db.from('matches').select().order('date_time');
    return (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _createMatch() async {
    final competitions = await _db
        .from('competitions')
        .select('id, name')
        .eq('is_active', true)
        .order('name');
    final clubs = await _db.from('clubs').select('id, name').order('name');
    if (!mounted) return;
    if ((competitions as List).isEmpty) {
      _notice('Aucune compétition active.');
      return;
    }
    final homeTeam = TextEditingController();
    final awayTeam = TextEditingController();
    final stadium = TextEditingController();
    final city = TextEditingController();
    final price = TextEditingController(text: '1000');
    // Capacités et prix par catégorie de tribune
    final popCapacity = TextEditingController(text: '500');
    final popPrice = TextEditingController(text: '1000');
    final decCapacity = TextEditingController(text: '200');
    final decPrice = TextEditingController(text: '2500');
    final vipCapacity = TextEditingController(text: '50');
    final vipPrice = TextEditingController(text: '5000');
    final currentYear = DateTime.now().year;
    final seasonName = TextEditingController(
      text: '$currentYear-${currentYear + 1}',
    );
    String? competitionId = competitions.first['id'] as String;
    String? homeClubId;
    String? awayClubId;
    DateTime dateTime = DateTime.now().add(const Duration(days: 7));
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1A2634),
          title: const Text(
            'Programmer un match',
            style: TextStyle(color: Colors.white),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: competitionId,
                    items: competitions
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item['id'] as String,
                            child: Text(item['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        refreshDialog(() => competitionId = value),
                    decoration: const InputDecoration(labelText: 'Compétition'),
                  ),
                  TextFormField(
                    controller: seasonName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Saison / édition',
                      hintText: '2026-2027',
                    ),
                    validator: _required,
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('home-club-$homeClubId'),
                    initialValue: homeClubId ?? '',
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Saisie manuelle'),
                      ),
                      ...clubs.map(
                        (club) => DropdownMenuItem<String>(
                          value: club['id'] as String,
                          child: Text(club['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (value) => refreshDialog(
                      () => homeClubId = value == null || value.isEmpty
                          ? null
                          : value,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Club à domicile (facultatif)',
                    ),
                  ),
                  if (homeClubId == null)
                    TextFormField(
                      controller: homeTeam,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Équipe à domicile',
                      ),
                      validator: _required,
                    ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('away-club-$awayClubId'),
                    initialValue: awayClubId ?? '',
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Saisie manuelle'),
                      ),
                      ...clubs.map(
                        (club) => DropdownMenuItem<String>(
                          value: club['id'] as String,
                          child: Text(club['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (value) => refreshDialog(
                      () => awayClubId = value == null || value.isEmpty
                          ? null
                          : value,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Club visiteur (facultatif)',
                    ),
                  ),
                  if (awayClubId == null)
                    TextFormField(
                      controller: awayTeam,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Équipe visiteuse',
                      ),
                      validator: _required,
                    ),
                  TextFormField(
                    controller: stadium,
                    decoration: const InputDecoration(labelText: 'Stade'),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: city,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Ville'),
                    validator: _required,
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Capacité du stade & Tarifs des places',
                      style: TextStyle(
                        color: Color(0xFFFCD116),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Tribune Populaire
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: popCapacity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Places Populaire',
                            hintText: '500',
                          ),
                          validator: _nonNegativeInteger,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: popPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Prix Populaire (F)',
                            hintText: '1000',
                          ),
                          validator: _positiveInteger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Tribune Découverte
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: decCapacity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Places Découverte',
                            hintText: '200',
                          ),
                          validator: _nonNegativeInteger,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: decPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Prix Découverte (F)',
                            hintText: '2500',
                          ),
                          validator: _positiveInteger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Tribune VIP
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: vipCapacity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Places VIP',
                            hintText: '50',
                          ),
                          validator: _nonNegativeInteger,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: vipPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Prix VIP (F)',
                            hintText: '5000',
                          ),
                          validator: _positiveInteger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: dateTime,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (date == null || !context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(dateTime),
                      );
                      if (time != null) {
                        refreshDialog(
                          () => dateTime = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.calendar_month, color: Color(0xFFFCD116)),
                    label: Text(
                      '${dateTime.day}/${dateTime.month}/${dateTime.year} · ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                formKey.currentState!.validate(),
              ),
              child: const Text('Publier'),
            ),
          ],
        ),
      ),
    );
    if (created == true && competitionId != null) {
      try {
        final selectedCompetitionId = competitionId!;
        final homeClub = homeClubId == null
            ? null
            : clubs.firstWhere((club) => club['id'] == homeClubId);
        final awayClub = awayClubId == null
            ? null
            : clubs.firstWhere((club) => club['id'] == awayClubId);
        final homeName = homeClub?['name'] as String? ?? homeTeam.text.trim();
        final awayName = awayClub?['name'] as String? ?? awayTeam.text.trim();
        final season = await _db
            .from('seasons')
            .upsert({
              'competition_id': selectedCompetitionId,
              'name': seasonName.text.trim(),
              'is_active': true,
            }, onConflict: 'competition_id,name')
            .select('id')
            .single();
        await _db
            .from('seasons')
            .update({'is_active': false})
            .eq('competition_id', selectedCompetitionId)
            .neq('id', season['id']);
        final pCapacity = int.tryParse(popCapacity.text.trim()) ?? 0;
        final pPrice = int.tryParse(popPrice.text.trim()) ?? 1000;
        final dCapacity = int.tryParse(decCapacity.text.trim()) ?? 0;
        final dPrice = int.tryParse(decPrice.text.trim()) ?? 2500;
        final vCapacity = int.tryParse(vipCapacity.text.trim()) ?? 0;
        final vPrice = int.tryParse(vipPrice.text.trim()) ?? 5000;
        final basePrice = pCapacity > 0 ? pPrice : (dCapacity > 0 ? dPrice : vPrice);

        // 1. Insertion du match dans le calendrier
        final newMatch = await _db.from('matches').insert({
          'teams': '$homeName vs $awayName',
          'home_club_id': homeClubId,
          'away_club_id': awayClubId,
          'date_time': dateTime.toUtc().toIso8601String(),
          'stadium': stadium.text.trim(),
          'city': city.text.trim(),
          'price': basePrice,
          'competition_id': selectedCompetitionId,
          'season_id': season['id'],
          'status': 'scheduled',
          'is_hero': false,
        }).select('id').single();

        final matchId = newMatch['id'] as String;

        // 2. Configuration des places et tarifs
        final categoryConfigs = [
          if (pCapacity > 0)
            {
              'name': 'Tribune Populaire',
              'price': pPrice,
              'capacity': pCapacity,
            },
          if (dCapacity > 0)
            {
              'name': 'Tribune Découverte',
              'price': dPrice,
              'capacity': dCapacity,
            },
          if (vCapacity > 0)
            {
              'name': 'Tribune VIP',
              'price': vPrice,
              'capacity': vCapacity,
            },
        ];

        // 2a. Synchronisation dans ticket_catalog
        for (final cat in categoryConfigs) {
          try {
            await _db.from('ticket_catalog').upsert({
              'match_id': matchId,
              'category_name': cat['name'],
              'price': cat['price'],
              'total_capacity': cat['capacity'],
              'tickets_sold': 0,
              'is_active': true,
            });
          } catch (_) {
            try {
              await _db.from('ticket_catalog').upsert({
                'match_id': matchId,
                'category_name': cat['name'],
                'price': cat['price'],
                'is_active': true,
              });
            } catch (_) {}
          }
        }

        // 2b. Synchronisation optionnelle dans stadium_zones et match_ticket_categories
        for (final cat in categoryConfigs) {
          try {
            final existingZone = await _db
                .from('stadium_zones')
                .select('id')
                .eq('zone_name', cat['name'] as String)
                .maybeSingle();
            final String? zoneId = existingZone?['id'] as String?;

            if (zoneId != null) {
              final existingCat = await _db
                  .from('match_ticket_categories')
                  .select('id')
                  .eq('match_id', matchId)
                  .eq('zone_id', zoneId)
                  .maybeSingle();
              if (existingCat != null) {
                await _db.from('match_ticket_categories').update({
                  'price': cat['price'],
                  'total_tickets_offered': cat['capacity'],
                }).eq('id', existingCat['id']);
              } else {
                await _db.from('match_ticket_categories').insert({
                  'match_id': matchId,
                  'zone_id': zoneId,
                  'price': cat['price'],
                  'total_tickets_offered': cat['capacity'],
                  'tickets_sold': 0,
                });
              }
            }
          } catch (_) {}
        }

        // 3. Rafraîchissement de l'interface admin
        if (mounted) {
          setState(() {
            _future = _load();
          });
          _notice('Match programmé et publié avec succès !');
        }
      } catch (err) {
        _notice(
          'Erreur lors de la programmation : $err',
        );
      }
    }
    homeTeam.dispose();
    awayTeam.dispose();
    stadium.dispose();
    city.dispose();
    price.dispose();
    popCapacity.dispose();
    popPrice.dispose();
    decCapacity.dispose();
    decPrice.dispose();
    vipCapacity.dispose();
    vipPrice.dispose();
    seasonName.dispose();
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => _adminList(
    title: 'Calendrier des matchs',
    action: IconButton(
      onPressed: _createMatch,
      icon: const Icon(Icons.add, color: Color(0xFFFCD116)),
    ),
    future: _future,
    emptyText: 'Aucun match programmé.',
    itemBuilder: (row) => ListTile(
      title: Text(
        row['teams'] as String? ?? 'Match',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${_formatAdminDate(row['date_time'] as String?)} · ${row['stadium'] ?? 'Stade'}${row['city'] != null && row['city'] != '' ? ' (${row['city']})' : ''}',
        style: const TextStyle(color: Colors.white60, fontSize: 13),
      ),
      trailing: _AdminMatchStatusMenu(
        matchId: row['id'] as String,
        currentStatus: row['status'] as String? ?? 'scheduled',
        onStatusChanged: () => setState(() {
          _future = _load();
        }),
      ),
    ),
  );
}

class _ResultAdminTab extends StatefulWidget {
  const _ResultAdminTab();

  @override
  State<_ResultAdminTab> createState() => _ResultAdminTabState();
}

class _ResultAdminTabState extends State<_ResultAdminTab> {
  final _db = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _db
        .from('match_results')
        .select()
        .order('match_date', ascending: false);
    return (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _createResult() async {
    final matches = await _db
        .from('matches')
        .select('id, teams, date_time, competition_id, season_id, status')
        .inFilter('status', ['scheduled', 'live'])
        .order('date_time', ascending: false);
    final competitions = await _db
        .from('competitions')
        .select('id, name')
        .eq('is_active', true)
        .order('name');
    if (!mounted) return;
    if ((competitions as List).isEmpty) return;
    if ((matches as List).isEmpty) {
      _notice('Créez d’abord le match dans le calendrier.');
      return;
    }
    final availableMatches = matches
        .where(
          (match) => competitions.any(
            (competition) => competition['id'] == match['competition_id'],
          ),
        )
        .toList();
    if (availableMatches.isEmpty) {
      _notice('Aucun match lié à une compétition active.');
      return;
    }
    final home = TextEditingController();
    final away = TextEditingController();
    final homeScore = TextEditingController(text: '0');
    final awayScore = TextEditingController(text: '0');
    final scorers = TextEditingController();
    final assists = TextEditingController();
    String? competitionId = competitions.first['id'] as String;
    String category = competitions.first['name'] as String;
    String? matchId;
    String? matchDate;
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1A2634),
          title: const Text(
            'Publier un résultat',
            style: TextStyle(color: Colors.white),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: null,
                    isExpanded: true,
                    items: availableMatches
                        .map(
                          (match) => DropdownMenuItem<String>(
                            value: match['id'] as String,
                            child: Text(
                              '${match['teams']} · ${_formatAdminDate(match['date_time'] as String?)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      final match = availableMatches.firstWhere(
                        (item) => item['id'] == value,
                      );
                      refreshDialog(() {
                        matchId = value;
                        matchDate = match['date_time'] as String;
                        competitionId = match['competition_id'] as String;
                        category =
                            competitions.firstWhere(
                                  (item) => item['id'] == competitionId,
                                )['name']
                                as String;
                        final names = (match['teams'] as String? ?? '').split(
                          RegExp(
                            r'\s+(?:vs?\.?|contre)\s+',
                            caseSensitive: false,
                          ),
                        );
                        if (names.length == 2) {
                          home.text = names.first.trim();
                          away.text = names.last.trim();
                        }
                      });
                    },
                    validator: _required,
                    decoration: const InputDecoration(
                      labelText: 'Match du calendrier',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: home,
                    decoration: const InputDecoration(
                      labelText: 'Équipe à domicile',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: away,
                    decoration: const InputDecoration(
                      labelText: 'Équipe visiteuse',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: homeScore,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Score domicile',
                          ),
                          validator: _nonNegativeInteger,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: awayScore,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Score visiteur',
                          ),
                          validator: _nonNegativeInteger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: scorers,
                    decoration: const InputDecoration(
                      labelText: 'Buteurs (facultatif)',
                      hintText: 'Ex: Traoré 24\', Ouattara 82\'',
                      prefixIcon: Icon(Icons.sports_soccer, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: assists,
                    decoration: const InputDecoration(
                      labelText: 'Passeurs (facultatif)',
                      hintText: 'Ex: Sanogo 24\', Kaboré 82\'',
                      prefixIcon: Icon(Icons.auto_awesome_motion_outlined, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                formKey.currentState!.validate(),
              ),
              child: const Text('Publier'),
            ),
          ],
        ),
      ),
    );
    if (created == true &&
        competitionId != null &&
        matchId != null &&
        matchDate != null) {
      try {
        await _db.from('match_results').insert({
          'match_id': matchId,
          'season_id': availableMatches.firstWhere(
            (item) => item['id'] == matchId,
          )['season_id'],
          'category': category,
          'competition_id': competitionId,
          'home_team_name': home.text.trim(),
          'away_team_name': away.text.trim(),
          'home_score': int.parse(homeScore.text),
          'away_score': int.parse(awayScore.text),
          'match_date': DateTime.parse(matchDate!).toUtc().toIso8601String(),
          'status': 'finished',
          'validated_at': DateTime.now().toUtc().toIso8601String(),
          'validated_by': _db.auth.currentUser!.id,
          if (scorers.text.trim().isNotEmpty) 'scorers': scorers.text.trim(),
          if (assists.text.trim().isNotEmpty) 'assists': assists.text.trim(),
        });
        try {
          await _db
              .from('matches')
              .update({'status': 'finished'})
              .eq('id', matchId!);
        } catch (_) {
          _notice(
            'Résultat publié, mais le statut du match n’a pas été actualisé.',
          );
        }
        if (mounted) {
          setState(() {
            _future = _load();
          });
        }
      } catch (_) {
        _notice(
          'Le résultat n’a pas pu être publié. Vérifiez vos droits et les données.',
        );
      }
    }
    home.dispose();
    away.dispose();
    homeScore.dispose();
    awayScore.dispose();
    scorers.dispose();
    assists.dispose();
  }

  Future<void> _editResult(Map<String, dynamic> row) async {
    final homeScore = TextEditingController(text: '${row['home_score'] ?? 0}');
    final awayScore = TextEditingController(text: '${row['away_score'] ?? 0}');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A2634),
        title: const Text(
          'Corriger le score',
          style: TextStyle(color: Colors.white),
        ),
        content: Form(
          key: formKey,
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: homeScore,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: row['home_team_name'] as String? ?? 'Domicile',
                  ),
                  validator: _nonNegativeInteger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: awayScore,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: row['away_team_name'] as String? ?? 'Visiteur',
                  ),
                  validator: _nonNegativeInteger,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, formKey.currentState!.validate()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (saved == true) {
      try {
        await _db
            .from('match_results')
            .update({
              'home_score': int.parse(homeScore.text),
              'away_score': int.parse(awayScore.text),
              'validated_at': DateTime.now().toUtc().toIso8601String(),
              'validated_by': _db.auth.currentUser!.id,
            })
            .eq('id', row['id']);
        if (mounted) {
          setState(() {
            _future = _load();
          });
        }
      } catch (_) {
        _notice('Le score n’a pas pu être corrigé.');
      }
    }
    homeScore.dispose();
    awayScore.dispose();
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => _adminList(
    title: 'Résultats officiels',
    action: IconButton(
      onPressed: _createResult,
      icon: const Icon(Icons.add, color: Color(0xFFFCD116)),
    ),
    future: _future,
    emptyText: 'Aucun résultat publié.',
    itemBuilder: (row) {
      final scorers = row['scorers'] as String?;
      final assists = row['assists'] as String?;
      final hasEvents = (scorers != null && scorers.isNotEmpty) ||
          (assists != null && assists.isNotEmpty);

      return ListTile(
        onTap: () => _editResult(row),
        title: Text(
          '${row['home_team_name']} ${row['home_score']} – ${row['away_score']} ${row['away_team_name']}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${row['category']} · ${_formatAdminDate(row['match_date'] as String?)}',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            if (hasEvents) ...[
              const SizedBox(height: 4),
              if (scorers != null && scorers.isNotEmpty)
                Text(
                  '⚽ $scorers',
                  style: const TextStyle(color: Color(0xFF7ED6A5), fontSize: 12),
                ),
              if (assists != null && assists.isNotEmpty)
                Text(
                  '👟 $assists',
                  style: const TextStyle(color: Color(0xFF7BAAFF), fontSize: 12),
                ),
            ],
          ],
        ),
        trailing: const Icon(Icons.edit_outlined, color: Colors.white38, size: 20),
      );
    },
  );
}

class _ClubAdminTab extends StatefulWidget {
  final String role;
  final String? managedClubId;

  const _ClubAdminTab({required this.role, required this.managedClubId});

  @override
  State<_ClubAdminTab> createState() => _ClubAdminTabState();
}

class _ClubAdminTabState extends State<_ClubAdminTab> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();
  late Future<List<Map<String, dynamic>>> _future;
  String? _uploadingClubId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (widget.role == 'admin_club' && widget.managedClubId == null) {
      return [];
    }
    var query = _db
        .from('clubs')
        .select('id, name, short_name, city, logo_url');
    if (widget.role == 'admin_club') {
      query = query.eq('id', widget.managedClubId!);
    }
    final rows = await query.order('name');
    return (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _editClub({Map<String, dynamic>? club}) async {
    final name = TextEditingController(text: club?['name'] as String? ?? '');
    final shortName = TextEditingController(
      text: club?['short_name'] as String? ?? '',
    );
    final city = TextEditingController(text: club?['city'] as String? ?? '');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A2634),
        title: Text(
          club == null ? 'Ajouter un club' : 'Modifier le club',
          style: const TextStyle(color: Colors.white),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom du club'),
                validator: _required,
              ),
              TextFormField(
                controller: shortName,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Nom court'),
                validator: _required,
              ),
              TextFormField(
                controller: city,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Ville'),
                validator: _required,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, formKey.currentState!.validate()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (saved == true) {
      try {
        final values = {
          'name': name.text.trim(),
          'short_name': shortName.text.trim(),
          'city': city.text.trim(),
        };
        if (club == null) {
          await _db.from('clubs').insert(values);
        } else {
          await _db.from('clubs').update(values).eq('id', club['id']);
        }
        if (mounted) {
          setState(() {
            _future = _load();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(club == null ? 'Club ajouté.' : 'Club modifié.'),
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Impossible d’enregistrer le club. Vérifiez vos droits et les informations.',
              ),
            ),
          );
        }
      }
    }
    name.dispose();
    shortName.dispose();
    city.dispose();
  }

  Future<void> _uploadLogo(Map<String, dynamic> club) async {
    final clubId = club['id'] as String;
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
    );
    if (image == null || !mounted) return;
    setState(() => _uploadingClubId = clubId);
    try {
      final bytes = await image.readAsBytes();
      if (bytes.length > 3 * 1024 * 1024) {
        throw StateError('Le logo doit peser moins de 3 Mo.');
      }
      final format = _imageFormat(bytes);
      if (format == null) {
        throw StateError('Choisissez une image JPG, PNG ou WebP.');
      }
      final path =
          '$clubId/logo-${DateTime.now().millisecondsSinceEpoch}.${format.extension}';
      await _db.storage
          .from('club-logos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: format.mimeType,
              upsert: true,
            ),
          );
      final publicUrl = _db.storage.from('club-logos').getPublicUrl(path);
      await _db.from('clubs').update({'logo_url': publicUrl}).eq('id', clubId);
      if (mounted) {
        setState(() {
          _future = _load();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logo de ${club['name']} mis à jour.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossible d’enregistrer ce logo. Vérifiez le format et vos droits.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingClubId = null);
    }
  }

  _ClubImageFormat? _imageFormat(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return const _ClubImageFormat('jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return const _ClubImageFormat('png', 'image/png');
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return const _ClubImageFormat('webp', 'image/webp');
    }
    return null;
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(child: Text('Impossible de charger les clubs.'));
      }
      final clubs = snapshot.data ?? const <Map<String, dynamic>>[];
      return RefreshIndicator(
        onRefresh: () async {
          final future = _load();
          setState(() {
            _future = future;
          });
          await future;
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.role == 'super_admin')
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _editClub(),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un club'),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Ajoutez le logo officiel du club. Formats JPG, PNG ou WebP, 3 Mo maximum.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            if (clubs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun club associé à ce compte.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            ...clubs.map((club) {
              final logoUrl = club['logo_url'] as String?;
              final clubId = club['id'] as String;
              return Card(
                color: const Color(0xFF1A2634),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF008751),
                    backgroundImage: logoUrl == null || logoUrl.isEmpty
                        ? null
                        : NetworkImage(logoUrl),
                    child: logoUrl == null || logoUrl.isEmpty
                        ? const Icon(Icons.shield_outlined, color: Colors.white)
                        : null,
                  ),
                  title: Text(
                    club['name'] as String? ?? 'Club',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${club['short_name'] ?? ''} · ${club['city'] ?? 'Ville non renseignée'}',
                    style: const TextStyle(color: Colors.white60),
                  ),
                  trailing: _uploadingClubId == clubId
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Wrap(
                          spacing: 0,
                          children: [
                            IconButton(
                              tooltip: 'Modifier le club',
                              onPressed: () => _editClub(club: club),
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Colors.white70,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Choisir le logo',
                              onPressed: () => _uploadLogo(club),
                              icon: const Icon(
                                Icons.image_outlined,
                                color: Color(0xFFFCD116),
                              ),
                            ),
                          ],
                        ),
                ),
              );
            }),
          ],
        ),
      );
    },
  );
}

class _ClubImageFormat {
  final String extension;
  final String mimeType;

  const _ClubImageFormat(this.extension, this.mimeType);
}

class _ProductAdminTab extends StatefulWidget {
  final String role;
  final String? managedClubId;
  const _ProductAdminTab({required this.role, required this.managedClubId});

  @override
  State<_ProductAdminTab> createState() => _ProductAdminTabState();
}

class _ProductAdminTabState extends State<_ProductAdminTab> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<String?> _pickAndUploadImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last;
      final fileName = 'product_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage.from('products').uploadBinary(
        fileName,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
      return _db.storage.from('products').getPublicUrl(fileName);
    } catch (e) {
      _notice('Impossible d’uploader l’image : $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    var query = _db.from('products').select();
    if (widget.role == 'admin_club' && widget.managedClubId != null) {
      query = query.eq('club_id', widget.managedClubId!);
    }
    final rows = await query.order('created_at', ascending: false);
    return (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _createProduct() async {
    final clubs = widget.role == 'admin_club' && widget.managedClubId != null
        ? await _db
              .from('clubs')
              .select('id, name')
              .eq('id', widget.managedClubId!)
        : await _db.from('clubs').select('id, name').order('name');
    if (!mounted) return;
    if ((clubs as List).isEmpty) {
      _notice('Aucun club n’est associé à ce compte.');
      return;
    }
    final title = TextEditingController();
    final description = TextEditingController();
    final price = TextEditingController();
    final stock = TextEditingController(text: '1');
    final imageUrl = TextEditingController();
    String? clubId = clubs.first['id'] as String;
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A2634),
          title: const Text(
            'Ajouter un article',
            style: TextStyle(color: Colors.white),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.role == 'super_admin')
                    DropdownButtonFormField<String>(
                      initialValue: clubId,
                      items: clubs
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['id'] as String,
                              child: Text(item['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => clubId = value,
                      decoration: const InputDecoration(labelText: 'Club'),
                    ),
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Nom du produit',
                    ),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  TextFormField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Prix (FCFA)'),
                    validator: _positiveInteger,
                  ),
                  TextFormField(
                    controller: stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stock'),
                    validator: _nonNegativeInteger,
                  ),
                  const SizedBox(height: 14),
                  // Sélecteur visuel de photo depuis la galerie
                  GestureDetector(
                    onTap: () async {
                      final uploadedUrl = await _pickAndUploadImage();
                      if (uploadedUrl != null) {
                        setDialogState(() {
                          imageUrl.text = uploadedUrl;
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF223142),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: imageUrl.text.isNotEmpty
                              ? const Color(0xFF008751)
                              : Colors.white24,
                          width: 1.5,
                        ),
                      ),
                      child: imageUrl.text.isNotEmpty
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    imageUrl.text,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
                                  ),
                                ),
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.edit, color: Colors.white, size: 12),
                                        SizedBox(width: 4),
                                        Text('Changer', style: TextStyle(color: Colors.white, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo, color: Color(0xFF008751), size: 36),
                                SizedBox(height: 8),
                                Text(
                                  'Choisir la photo dans la galerie',
                                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Appuyez ici pour parcourir vos photos',
                                  style: TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, formKey.currentState!.validate()),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    if (created == true && clubId != null) {
      try {
        await _db.from('products').insert({
          'club_id': clubId,
          'title': title.text.trim(),
          'description': description.text.trim(),
          'price': int.parse(price.text),
          'stock': int.parse(stock.text),
          'image_url': imageUrl.text.trim().isEmpty
              ? null
              : imageUrl.text.trim(),
          'is_active': true,
        });
        if (mounted) {
          setState(() {
            _future = _load();
          });
        }
      } catch (_) {
        _notice(
          'L’article n’a pas pu être ajouté. Vérifiez les droits du compte.',
        );
      }
    }
    title.dispose();
    description.dispose();
    price.dispose();
    stock.dispose();
    imageUrl.dispose();
  }

  Future<void> _editClubHandoff() async {
    var clubsQuery = _db
        .from('clubs')
        .select('id,name,city,marketing_phone,headquarters_address,manager_name,maps_url');
    if (widget.role == 'admin_club' && widget.managedClubId != null) {
      clubsQuery = clubsQuery.eq('id', widget.managedClubId!);
    }
    final clubs = await clubsQuery.order('name');
    if (!mounted) return;
    if ((clubs as List).isEmpty) {
      _notice('Aucun club n’est associé à ce compte.');
      return;
    }
    String? clubId = clubs.first['id'] as String;
    final phone = TextEditingController(
      text: clubs.first['marketing_phone'] as String? ?? '',
    );
    final address = TextEditingController(
      text: clubs.first['headquarters_address'] as String? ?? '',
    );
    final managerName = TextEditingController(
      text: clubs.first['manager_name'] as String? ?? '',
    );
    final mapsUrl = TextEditingController(
      text: clubs.first['maps_url'] as String? ?? '',
    );
    String? validationError;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          final selectedClub = clubs.firstWhere(
            (club) => club['id'] == clubId,
            orElse: () => clubs.first,
          );
          return AlertDialog(
            backgroundColor: const Color(0xFF1A2634),
            title: const Text(
              'Contact et retrait du club',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.role == 'super_admin')
                    DropdownButtonFormField<String>(
                      initialValue: clubId,
                      items: clubs
                          .map(
                            (club) => DropdownMenuItem<String>(
                              value: club['id'] as String,
                              child: Text(club['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        final selected = clubs.firstWhere(
                          (club) => club['id'] == value,
                        );
                        refresh(() {
                          clubId = value;
                          phone.text =
                              selected['marketing_phone'] as String? ?? '';
                          address.text =
                              selected['headquarters_address'] as String? ?? '';
                          managerName.text =
                              selected['manager_name'] as String? ?? '';
                          mapsUrl.text =
                              selected['maps_url'] as String? ?? '';
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Club'),
                    ),
                  TextField(
                    controller: managerName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nom du responsable boutique',
                      hintText: 'Ex: M. Traoré',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone direct du responsable',
                      hintText: '+226 70 00 00 00',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: address,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Guichet / Lieu de retrait (${selectedClub['city']})',
                      hintText: 'Ex: Guichet officiel Stade Municipal',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: mapsUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Lien Google Maps / GPS de l\'itinéraire',
                      hintText: 'https://maps.app.goo.gl/...',
                    ),
                  ),
                  if (validationError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        validationError!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () {
                  final normalizedPhone = phone.text.trim().replaceAll(
                    RegExp(r'[\s-]'),
                    '',
                  );
                  if (normalizedPhone.isNotEmpty &&
                      !RegExp(
                        r'^(?:\+?226)?[0-9]{8}$',
                      ).hasMatch(normalizedPhone)) {
                    refresh(
                      () => validationError =
                          'Saisissez un numéro burkinabè valide.',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true && clubId != null) {
      try {
        await _db
            .from('clubs')
            .update({
              'marketing_phone': phone.text.trim().isEmpty
                  ? null
                  : phone.text.trim().replaceAll(RegExp(r'[\s-]'), ''),
              'headquarters_address': address.text.trim().isEmpty
                  ? null
                  : address.text.trim(),
              'manager_name': managerName.text.trim().isEmpty
                  ? null
                  : managerName.text.trim(),
              'maps_url': mapsUrl.text.trim().isEmpty
                  ? null
                  : mapsUrl.text.trim(),
            })
            .eq('id', clubId!);
        _notice('Les informations de retrait du club sont enregistrées.');
      } catch (_) {
        _notice('Impossible de modifier les coordonnées de ce club.');
      }
    }
    phone.dispose();
    address.dispose();
    managerName.dispose();
    mapsUrl.dispose();
  }

  Future<void> _editProduct(Map<String, dynamic> product) async {
    var clubsQuery = _db.from('clubs').select('id,name');
    if (widget.role == 'admin_club' && widget.managedClubId != null) {
      clubsQuery = clubsQuery.eq('id', widget.managedClubId!);
    }
    final clubs = await clubsQuery.order('name');
    if (!mounted) return;
    if ((clubs as List).isEmpty) {
      _notice('Aucun club disponible pour cet article.');
      return;
    }
    final title = TextEditingController(
      text: product['title'] as String? ?? '',
    );
    final description = TextEditingController(
      text: product['description'] as String? ?? '',
    );
    final price = TextEditingController(text: product['price'].toString());
    final stock = TextEditingController(text: product['stock'].toString());
    final imageUrl = TextEditingController(
      text: product['image_url'] as String? ?? '',
    );
    String? clubId =
        product['club_id'] as String? ?? clubs.first['id'] as String;
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A2634),
          title: const Text(
            'Modifier l’article',
            style: TextStyle(color: Colors.white),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.role == 'super_admin')
                    DropdownButtonFormField<String>(
                      initialValue: clubs.any((club) => club['id'] == clubId)
                          ? clubId
                          : null,
                      items: clubs
                          .map(
                            (club) => DropdownMenuItem<String>(
                              value: club['id'] as String,
                              child: Text(club['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => clubId = value,
                      decoration: const InputDecoration(
                        labelText: 'Club vendeur',
                      ),
                      validator: (value) =>
                          value == null ? 'Choisissez un club.' : null,
                    ),
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Nom'),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  TextFormField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Prix (FCFA)'),
                    validator: _positiveInteger,
                  ),
                  TextFormField(
                    controller: stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stock'),
                    validator: _nonNegativeInteger,
                  ),
                  const SizedBox(height: 14),
                  // Sélecteur visuel de photo depuis la galerie
                  GestureDetector(
                    onTap: () async {
                      final uploadedUrl = await _pickAndUploadImage();
                      if (uploadedUrl != null) {
                        setDialogState(() {
                          imageUrl.text = uploadedUrl;
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF223142),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: imageUrl.text.isNotEmpty
                              ? const Color(0xFF008751)
                              : Colors.white24,
                          width: 1.5,
                        ),
                      ),
                      child: imageUrl.text.isNotEmpty
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    imageUrl.text,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
                                  ),
                                ),
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.edit, color: Colors.white, size: 12),
                                        SizedBox(width: 4),
                                        Text('Changer', style: TextStyle(color: Colors.white, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo, color: Color(0xFF008751), size: 36),
                                SizedBox(height: 8),
                                Text(
                                  'Choisir la photo dans la galerie',
                                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Appuyez ici pour parcourir vos photos',
                                  style: TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, formKey.currentState!.validate()),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && clubId != null) {
      try {
        await _db
            .from('products')
            .update({
              'club_id': clubId,
              'title': title.text.trim(),
              'description': description.text.trim().isEmpty
                  ? null
                  : description.text.trim(),
              'price': int.parse(price.text.trim()),
              'stock': int.parse(stock.text.trim()),
              'image_url': imageUrl.text.trim().isEmpty
                  ? null
                  : imageUrl.text.trim(),
            })
            .eq('id', product['id']);
        if (mounted) {
          setState(() {
            _future = _load();
          });
        }
      } catch (_) {
        _notice(
          'Impossible de modifier cet article. Vérifiez les droits du compte.',
        );
      }
    }
    title.dispose();
    description.dispose();
    price.dispose();
    stock.dispose();
    imageUrl.dispose();
  }

  Future<void> _setProductActive(
    Map<String, dynamic> product,
    bool active,
  ) async {
    try {
      await _db
          .from('products')
          .update({'is_active': active})
          .eq('id', product['id']);
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (_) {
      _notice('Impossible de modifier la publication de cet article.');
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => _adminList(
    title: 'Catalogue des clubs',
    action: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _editClubHandoff,
          tooltip: 'Coordonnées de retrait',
          icon: const Icon(Icons.contact_phone_outlined, color: Colors.white),
        ),
        IconButton(
          onPressed: _createProduct,
          tooltip: 'Ajouter un article',
          icon: const Icon(Icons.add, color: Color(0xFFFCD116)),
        ),
      ],
    ),
    future: _future,
    emptyText: 'Aucun article.',
    itemBuilder: (row) => ListTile(
      title: Text(
        row['title'] as String? ?? 'Article',
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        '${row['price']} FCFA · Stock : ${row['stock']}',
        style: const TextStyle(color: Colors.white60),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Modifier article et club vendeur',
            onPressed: () => _editProduct(row),
            icon: const Icon(Icons.edit_outlined, color: Colors.white70),
          ),
          Switch.adaptive(
            value: row['is_active'] == true,
            onChanged: (value) => _setProductActive(row, value),
          ),
        ],
      ),
    ),
  );
}

class _OrderAdminTab extends StatefulWidget {
  final String role;
  final String? managedClubId;

  const _OrderAdminTab({required this.role, required this.managedClubId});

  @override
  State<_OrderAdminTab> createState() => _OrderAdminTabState();
}

class _OrderAdminTabState extends State<_OrderAdminTab> {
  final _db = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _db
        .from('marketplace_orders')
        .select(
          'id,status,total_amount,payment_phone,customer_name,pickup_code,provider_transaction_id,created_at,marketplace_order_items(id,product_title,quantity,club_name,club_city,marketing_phone,headquarters_address,manager_name,maps_url,fulfillment_status,club_id_snapshot)',
        )
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _refreshPaymentStatus(String orderId) async {
    try {
      final res = await _db.rpc('verify_or_confirm_order', params: {'p_order_id': orderId});
      final map = Map<String, dynamic>.from(res as Map);
      if (map['success'] == true) {
        _notice('Paiement confirmé par YengaPay.');
        if (mounted) {
          setState(() {
            _future = _load();
          });
        }
      } else {
        _notice(map['message']?.toString() ?? 'Le paiement est toujours en attente.');
      }
    } catch (e) {
      _notice('Erreur : $e');
    }
  }

  Future<void> _setFulfillment(Map<String, dynamic> item, String status) async {
    try {
      await _db
          .from('marketplace_order_items')
          .update({'fulfillment_status': status})
          .eq('id', item['id']);
      if (mounted) {
        setState(() {
          _future = _load();
        });
      }
    } catch (_) {
      _notice('Impossible de mettre à jour le suivi de cet article.');
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) _notice('Impossible de lancer l’appel.');
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => _adminList(
    title: 'Commandes à remettre',
    action: IconButton(
      tooltip: 'Actualiser',
      onPressed: () => setState(() {
        _future = _load();
      }),
      icon: const Icon(Icons.refresh, color: Colors.white70),
    ),
    future: _future,
    emptyText: 'Aucune commande payée à traiter.',
    itemBuilder: (order) {
      final items = (order['marketplace_order_items'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final needsRefund = order['status'] == 'refund_required';
      final paymentTransactionId =
          order['provider_transaction_id'] as String?;
      final hasVerifiedPayment = paymentTransactionId != null &&
          paymentTransactionId.isNotEmpty &&
          !paymentTransactionId.startsWith('MANUAL-');
      final needsPaymentReview =
          order['status'] == 'paid' && !hasVerifiedPayment;
      return Card(
        color: const Color(0xFF1A2634),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${order['total_amount']} F CFA',
                              style: const TextStyle(
                                color: Color(0xFFFCD116),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (hasVerifiedPayment &&
                                order['pickup_code'] != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF008751),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  order['pickup_code'] as String,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (order['customer_name'] != null && (order['customer_name'] as String).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Client : ${order['customer_name']}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        Text(
                          'Tél : ${order['payment_phone']}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Appeler l’acheteur : ${order['payment_phone']}',
                    onPressed: () => _call(order['payment_phone'] as String),
                    icon: const Icon(Icons.call, color: Colors.white, size: 20),
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFF008751)),
                  ),
                ],
              ),
              if (order['status'] == 'pending') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCD116).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFCD116)),
                      ),
                      child: const Text(
                        'En attente de paiement',
                        style: TextStyle(color: Color(0xFFFCD116), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF008751),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _refreshPaymentStatus(order['id'] as String),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Vérifier le paiement', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
              if (needsRefund)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Paiement reçu, stock indisponible : remboursement à traiter.',
                    style: TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              if (needsPaymentReview)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Paiement sans référence YengaPay : rapprochez-le avant toute remise.',
                    style: TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              for (final item in items)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF223142),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['product_title']} × ${item['quantity']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${item['club_name']} · ${item['club_city'] ?? 'Burkina Faso'}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                      if ((item['marketing_phone'] as String?)?.isNotEmpty ==
                          true)
                        TextButton.icon(
                          onPressed: () =>
                              _call(item['marketing_phone'] as String),
                          icon: const Icon(Icons.call, size: 16),
                          label: Text(
                            'Responsable marketing : ${item['marketing_phone']}',
                          ),
                        ),
                      if ((item['headquarters_address'] as String?)
                              ?.isNotEmpty ==
                          true)
                        Text(
                          'Retrait : ${item['headquarters_address']}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      if (!needsRefund && !needsPaymentReview)
                        DropdownButton<String>(
                          value:
                              item['fulfillment_status'] as String? ??
                              'awaiting_contact',
                          dropdownColor: const Color(0xFF223142),
                          style: const TextStyle(color: Colors.white),
                          items: const [
                            DropdownMenuItem(
                              value: 'awaiting_contact',
                              child: Text('À contacter'),
                            ),
                            DropdownMenuItem(
                              value: 'contacted',
                              child: Text('Client contacté'),
                            ),
                            DropdownMenuItem(
                              value: 'pickup_agreed',
                              child: Text('Retrait convenu'),
                            ),
                            DropdownMenuItem(
                              value: 'completed',
                              child: Text('Remis au client'),
                            ),
                            DropdownMenuItem(
                              value: 'cancelled',
                              child: Text('Annulé'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) _setFulfillment(item, value);
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _adminList({
  required String title,
  required Widget action,
  required Future<List<Map<String, dynamic>>> future,
  required String emptyText,
  required Widget Function(Map<String, dynamic>) itemBuilder,
}) => Column(
  children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          action,
        ],
      ),
    ),
    Expanded(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Chargement impossible.',
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return Center(
              child: Text(
                emptyText,
                style: const TextStyle(color: Colors.white60),
              ),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, color: Colors.white12),
            itemBuilder: (_, index) => itemBuilder(rows[index]),
          );
        },
      ),
    ),
  ],
);

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Champ obligatoire' : null;

String? _positiveInteger(String? value) {
  final parsed = int.tryParse(value ?? '');
  return parsed == null || parsed <= 0
      ? 'Saisissez un entier supérieur à zéro'
      : null;
}

String? _nonNegativeInteger(String? value) {
  final parsed = int.tryParse(value ?? '');
  return parsed == null || parsed < 0
      ? 'Saisissez un entier positif ou nul'
      : null;
}

String _formatAdminDate(String? iso) {
  if (iso == null || iso.isEmpty) return 'Date non définie';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year} à $h:$min';
  } catch (_) {
    return iso;
  }
}

class _AdminMatchStatusMenu extends StatelessWidget {
  final String matchId;
  final String currentStatus;
  final VoidCallback onStatusChanged;

  const _AdminMatchStatusMenu({
    required this.matchId,
    required this.currentStatus,
    required this.onStatusChanged,
  });

  static const _statusLabels = {
    'scheduled': 'Programmé',
    'live': 'En direct',
    'finished': 'Terminé',
    'postponed': 'Reporté',
    'cancelled': 'Annulé',
  };

  static const _statusColors = {
    'scheduled': Color(0xFF008751),
    'live': Colors.redAccent,
    'finished': Colors.grey,
    'postponed': Color(0xFFFCD116),
    'cancelled': Colors.red,
  };

  Future<void> _updateStatus(BuildContext context, String newStatus) async {
    try {
      await Supabase.instance.client
          .from('matches')
          .update({'status': newStatus})
          .eq('id', matchId);
      onStatusChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Statut mis à jour : ${_statusLabels[newStatus]}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de modifier le statut du match.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[currentStatus] ?? Colors.white70;
    final label = _statusLabels[currentStatus] ?? currentStatus;

    return PopupMenuButton<String>(
      tooltip: 'Changer le statut',
      onSelected: (newStatus) => _updateStatus(context, newStatus),
      color: const Color(0xFF1E2E3C),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: color, size: 16),
          ],
        ),
      ),
      itemBuilder: (context) => _statusLabels.entries.map((entry) {
        final isSelected = entry.key == currentStatus;
        final itemColor = _statusColors[entry.key] ?? Colors.white70;
        return PopupMenuItem<String>(
          value: entry.key,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: itemColor, shape: BoxShape.circle),
              ),
              Text(
                entry.value,
                style: TextStyle(
                  color: isSelected ? const Color(0xFFFCD116) : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                const Icon(Icons.check, color: Color(0xFFFCD116), size: 16),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
