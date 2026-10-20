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
    if (!mounted) return;
    if ((competitions as List).isEmpty) {
      _notice('Aucune compétition active.');
      return;
    }
    final teams = TextEditingController();
    final stadium = TextEditingController();
    final city = TextEditingController();
    final price = TextEditingController();
    String? competitionId = competitions.first['id'] as String;
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
                    controller: teams,
                    decoration: const InputDecoration(
                      labelText: 'Équipes (ex. Club A vs Club B)',
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
                  TextFormField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Prix de base (FCFA)',
                    ),
                    validator: _positiveInteger,
                  ),
                  const SizedBox(height: 8),
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
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      '${dateTime.day}/${dateTime.month}/${dateTime.year} · ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}',
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
        await _db.from('matches').insert({
          'teams': teams.text.trim(),
          'date_time': dateTime.toUtc().toIso8601String(),
          'stadium': stadium.text.trim(),
          'city': city.text.trim(),
          'price': int.parse(price.text.trim()),
          'competition_id': competitionId,
          'status': 'scheduled',
          'is_hero': false,
        });
        if (mounted) setState(() => _future = _load());
      } catch (_) {
        _notice(
          'Le match n’a pas pu être publié. Vérifiez vos droits et les données.',
        );
      }
    }
    teams.dispose();
    stadium.dispose();
    city.dispose();
    price.dispose();
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
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        '${row['city'] ?? 'Ville à préciser'} · ${row['stadium'] ?? 'Stade'} · ${row['date_time'] ?? ''}',
        style: const TextStyle(color: Colors.white60),
      ),
      trailing: Text(
        row['status'] as String? ?? '',
        style: const TextStyle(color: Color(0xFFFCD116)),
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
        .select('id, teams, date_time, competition_id, status')
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
        .where((match) => competitions.any((competition) => competition['id'] == match['competition_id']))
        .toList();
    if (availableMatches.isEmpty) {
      _notice('Aucun match lié à une compétition active.');
      return;
    }
    final home = TextEditingController();
    final away = TextEditingController();
    final homeScore = TextEditingController(text: '0');
    final awayScore = TextEditingController(text: '0');
    String? competitionId = competitions.first['id'] as String;
    String category = competitions.first['name'] as String;
    String? matchId;
    String? matchDate;
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) => AlertDialog(
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
                  items: availableMatches.map((match) => DropdownMenuItem<String>(
                    value: match['id'] as String,
                    child: Text('${match['teams']} · ${match['date_time']}'),
                  )).toList(),
                  onChanged: (value) {
                    final match = availableMatches.firstWhere((item) => item['id'] == value);
                    refreshDialog(() {
                      matchId = value;
                      matchDate = match['date_time'] as String;
                      competitionId = match['competition_id'] as String;
                      category = competitions.firstWhere((item) => item['id'] == competitionId)['name'] as String;
                      final names = (match['teams'] as String? ?? '').split(RegExp(r'\s+(?:vs?\.?|contre)\s+', caseSensitive: false));
                      if (names.length == 2) {
                        home.text = names.first.trim();
                        away.text = names.last.trim();
                      }
                    });
                  },
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'Match du calendrier'),
                ),
                TextFormField(
                  controller: home,
                  decoration: const InputDecoration(
                    labelText: 'Équipe à domicile',
                  ),
                  validator: _required,
                ),
                TextFormField(
                  controller: away,
                  decoration: const InputDecoration(
                    labelText: 'Équipe visiteuse',
                  ),
                  validator: _required,
                ),
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
            child: const Text('Publier'),
          ),
        ],
      )),
    );
    if (created == true && competitionId != null && matchId != null && matchDate != null) {
      try {
        await _db.from('match_results').insert({
          'match_id': matchId,
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
        });
        try {
          await _db.from('matches').update({'status': 'finished'}).eq('id', matchId!);
        } catch (_) {
          _notice('Résultat publié, mais le statut du match n’a pas été actualisé.');
        }
        if (mounted) setState(() => _future = _load());
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
        if (mounted) setState(() => _future = _load());
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
    itemBuilder: (row) => ListTile(
      onTap: () => _editResult(row),
      title: Text(
        '${row['home_team_name']} ${row['home_score']} – ${row['away_score']} ${row['away_team_name']}',
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        '${row['category']} · ${row['match_date']}',
        style: const TextStyle(color: Colors.white60),
      ),
    ),
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
    var query = _db.from('clubs').select('id, name, short_name, city, logo_url');
    if (widget.role == 'admin_club') {
      query = query.eq('id', widget.managedClubId!);
    }
    final rows = await query.order('name');
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
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
      final path = '$clubId/logo.${format.extension}';
      await _db.storage.from('club-logos').uploadBinary(
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
        setState(() => _future = _load());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logo de ${club['name']} mis à jour.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’enregistrer ce logo. Vérifiez le format et vos droits.')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingClubId = null);
    }
  }

  _ClubImageFormat? _imageFormat(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
      return const _ClubImageFormat('jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4e && bytes[3] == 0x47) {
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
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
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
          setState(() => _future = future);
          await future;
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                child: Text('Aucun club associé à ce compte.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
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
                  title: Text(club['name'] as String? ?? 'Club', style: const TextStyle(color: Colors.white)),
                  subtitle: Text(club['city'] as String? ?? 'Ville non renseignée', style: const TextStyle(color: Colors.white60)),
                  trailing: _uploadingClubId == clubId
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          tooltip: 'Choisir le logo',
                          onPressed: () => _uploadLogo(club),
                          icon: const Icon(Icons.image_outlined, color: Color(0xFFFCD116)),
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
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
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
      builder: (dialogContext) => AlertDialog(
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
                TextFormField(
                  controller: imageUrl,
                  decoration: const InputDecoration(
                    labelText: 'URL de l’image (facultatif)',
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
        if (mounted) setState(() => _future = _load());
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
        .select('id,name,city,marketing_phone,headquarters_address');
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
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Club'),
                    ),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone du responsable marketing',
                      hintText: '+226 70 00 00 00',
                    ),
                  ),
                  TextField(
                    controller: address,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Adresse du siège (${selectedClub['city']})',
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
            })
            .eq('id', clubId!);
        _notice('Les informations de retrait du club sont enregistrées.');
      } catch (_) {
        _notice('Impossible de modifier les coordonnées de ce club.');
      }
    }
    phone.dispose();
    address.dispose();
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
      builder: (dialogContext) => AlertDialog(
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
                TextFormField(
                  controller: imageUrl,
                  decoration: const InputDecoration(
                    labelText: 'URL de l’image (facultatif)',
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
        if (mounted) setState(() => _future = _load());
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
      if (mounted) setState(() => _future = _load());
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
          'id,status,total_amount,payment_phone,created_at,marketplace_order_items(id,product_title,quantity,club_name,club_city,marketing_phone,headquarters_address,fulfillment_status,club_id_snapshot)',
        )
        .inFilter('status', ['paid', 'refund_required'])
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> _setFulfillment(Map<String, dynamic> item, String status) async {
    try {
      await _db
          .from('marketplace_order_items')
          .update({'fulfillment_status': status})
          .eq('id', item['id']);
      if (mounted) setState(() => _future = _load());
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
      onPressed: () => setState(() => _future = _load()),
      icon: const Icon(Icons.refresh, color: Colors.white70),
    ),
    future: _future,
    emptyText: 'Aucune commande payée à traiter.',
    itemBuilder: (order) {
      final items = (order['marketplace_order_items'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final needsRefund = order['status'] == 'refund_required';
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
                    child: Text(
                      'Commande ${order['id'].toString().substring(0, 8)} · ${order['total_amount']} F CFA',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Appeler l’acheteur : ${order['payment_phone']}',
                    onPressed: () => _call(order['payment_phone'] as String),
                    icon: const Icon(Icons.call, color: Color(0xFF008751)),
                  ),
                ],
              ),
              if (needsRefund)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Paiement reçu, stock indisponible : remboursement à traiter.',
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
                      if (!needsRefund)
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
