import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompetitionAdminTab extends StatefulWidget {
  const CompetitionAdminTab({super.key});

  @override
  State<CompetitionAdminTab> createState() => _CompetitionAdminTabState();
}

class _CompetitionAdminTabState extends State<CompetitionAdminTab> {
  final _db = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await _db
        .from('competitions')
        .select(
          'id, code, name, competition_type, is_active, '
          'seasons(id, name, is_active, group_count, qualifiers_per_group, '
          'competition_teams(id, team_name, group_name, is_eliminated, is_qualified))',
        )
        .order('name');
    return (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _createCompetition({Map<String, dynamic>? existing}) async {
    final clubsResponse = await _db
        .from('clubs')
        .select('id, name')
        .order('name');
    final clubs = (clubsResponse as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (!mounted) return;

    final name = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    final season = TextEditingController(
      text: '${DateTime.now().year}-${DateTime.now().year + 1}',
    );
    final teamCount = TextEditingController();
    final groupCount = TextEditingController(text: '2');
    final qualifiers = TextEditingController(text: '2');
    final customTeams = TextEditingController();
    final selectedClubIds = <String>{};
    final groupAssignments = <String, String>{};
    final formKey = GlobalKey<FormState>();
    var type = existing?['competition_type'] as String? ?? 'league';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) {
          final requestedGroups = int.tryParse(groupCount.text) ?? 0;
          final groups = List.generate(
            requestedGroups.clamp(0, 128).toInt(),
            _groupLabel,
          );
          final selectedClubs = clubs
              .where((club) => selectedClubIds.contains(club['id']))
              .toList();
          final typedNames = customTeams.text
              .split(RegExp(r'[\r\n]+'))
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList();
          final allTeamNames = [
            ...selectedClubs.map((club) => club['name'] as String),
            ...typedNames,
          ];
          for (var index = 0; index < allTeamNames.length; index++) {
            groupAssignments.putIfAbsent(
              allTeamNames[index].toLowerCase(),
              () => groups.isEmpty ? '' : groups[index % groups.length],
            );
          }

          Widget groupAssignment(String teamName) => DropdownButton<String>(
            value: groups.contains(groupAssignments[teamName.toLowerCase()])
                ? groupAssignments[teamName.toLowerCase()]
                : groups.first,
            dropdownColor: const Color(0xFF1A2634),
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Colors.white70),
            items: groups
                .map(
                  (group) => DropdownMenuItem(
                    value: group,
                    child: Text('Groupe $group'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              refreshDialog(
                () => groupAssignments[teamName.toLowerCase()] = value,
              );
            },
          );

          return AlertDialog(
            backgroundColor: const Color(0xFF1A2634),
            title: const Text(
              'Créer une compétition',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 520,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: name,
                        readOnly: existing != null,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nom de la compétition',
                          hintText: 'Ligue 1, Coupe du Faso, CAN...',
                        ),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: type,
                        decoration: const InputDecoration(labelText: 'Format'),
                        items: const [
                          DropdownMenuItem(
                            value: 'league',
                            child: Text('Championnat (classement par points)'),
                          ),
                          DropdownMenuItem(
                            value: 'cup',
                            child: Text('Coupe à élimination directe'),
                          ),
                          DropdownMenuItem(
                            value: 'international',
                            child: Text('Tournoi avec phase de groupes'),
                          ),
                        ],
                        onChanged: existing == null
                            ? (value) =>
                                  refreshDialog(() => type = value ?? 'league')
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: season,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Saison / édition',
                        ),
                        validator: _required,
                      ),
                      if (type == 'international') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: groupCount,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre de groupes',
                                ),
                                validator: _positiveInteger,
                                onChanged: (_) => refreshDialog(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: qualifiers,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Qualifiés / groupe',
                                ),
                                validator: _positiveInteger,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: teamCount,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Nombre d’équipes',
                          helperText:
                              'Équipes sélectionnées : ${allTeamNames.length}',
                        ),
                        validator: (value) {
                          final count = int.tryParse(value?.trim() ?? '');
                          if (count == null || count < 2 || count > 128) {
                            return 'Indiquez entre 2 et 128 équipes.';
                          }
                          if (count != allTeamNames.length) {
                            return 'Le nombre doit correspondre aux équipes sélectionnées.';
                          }
                          if (type == 'international' &&
                              count < (int.tryParse(groupCount.text) ?? 1)) {
                            return 'Il faut au moins une équipe par groupe.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Sélectionner les clubs participants',
                        style: TextStyle(
                          color: Color(0xFFFCD116),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (clubs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Aucun club disponible. Ajoutez les équipes dans l’onglet Clubs.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView(
                            shrinkWrap: true,
                            children: clubs.map((club) {
                              final id = club['id'] as String;
                              return CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  club['name'] as String,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                value: selectedClubIds.contains(id),
                                onChanged: (selected) => refreshDialog(() {
                                  if (selected == true) {
                                    selectedClubIds.add(id);
                                  } else {
                                    selectedClubIds.remove(id);
                                  }
                                }),
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: customTeams,
                        minLines: 2,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Autres équipes (facultatif)',
                          hintText: 'Une équipe par ligne, ex. Étalons',
                          helperText:
                              'Utile pour les sélections nationales non enregistrées comme clubs.',
                        ),
                        onChanged: (_) => refreshDialog(() {}),
                      ),
                      if (type == 'international' && groups.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Affecter les équipes aux groupes',
                          style: TextStyle(
                            color: Color(0xFFFCD116),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        for (final teamName in allTeamNames)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  teamName,
                                  style: const TextStyle(color: Colors.white70),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              groupAssignment(teamName),
                            ],
                          ),
                      ],
                    ],
                  ),
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
                child: const Text('Créer'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      try {
        final selectedClubs = clubs
            .where((club) => selectedClubIds.contains(club['id']))
            .toList();
        final typedNames = customTeams.text
            .split(RegExp(r'[\r\n]+'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList();
        final teams = [
          ...selectedClubs.map(
            (club) => {
              'club_id': club['id'],
              'team_name': club['name'],
              if (type == 'international')
                'group_name':
                    groupAssignments[(club['name'] as String).toLowerCase()],
            },
          ),
          ...typedNames.map(
            (teamName) => {
              'team_name': teamName,
              if (type == 'international')
                'group_name': groupAssignments[teamName.toLowerCase()],
            },
          ),
        ];
        final code =
            existing?['code'] as String? ??
            name.text
                .trim()
                .toUpperCase()
                .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
                .replaceAll(RegExp(r'^-+|-+$'), '');
        await _db.rpc(
          'create_competition_season',
          params: {
            'p_code': code,
            'p_name': name.text.trim(),
            'p_competition_type': type,
            'p_season_name': season.text.trim(),
            'p_group_count': type == 'international'
                ? int.parse(groupCount.text)
                : 0,
            'p_qualifiers_per_group': type == 'international'
                ? int.parse(qualifiers.text)
                : 2,
            'p_teams': teams,
          },
        );
        if (mounted) {
          setState(() => _future = _load());
          _notice('Compétition et édition créées.');
        }
      } catch (error) {
        if (mounted) {
          final errorText = error.toString();
          if (errorText.contains('competition_code_name_or_type_conflict')) {
            _notice(
              'Une compétition avec ce nom existe déjà avec un autre format, '
              'ou ce code est déjà utilisé. Vérifiez la compétition existante.',
            );
          } else if (errorText.contains('seasons_competition_id_name_key')) {
            _notice('Cette édition existe déjà pour cette compétition.');
          } else {
            _notice('Création impossible : $error');
          }
        }
      }
    }

    name.dispose();
    season.dispose();
    teamCount.dispose();
    groupCount.dispose();
    qualifiers.dispose();
    customTeams.dispose();
  }

  Future<void> _deleteCompetition(Map<String, dynamic> competition) async {
    final name = competition['name'] as String? ?? 'cette compétition';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A2634),
        title: const Text(
          'Supprimer la compétition ?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '« $name », ses éditions et ses équipes inscrites seront supprimées. '
          'La suppression sera refusée si des matchs ou résultats y sont liés.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Supprimer',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final deleted = await _db
          .from('competitions')
          .delete()
          .eq('id', competition['id'] as String)
          .select('id');
      if (!mounted) return;
      if ((deleted as List).isEmpty) {
        _notice(
          'Suppression impossible : accès refusé ou compétition introuvable.',
        );
        return;
      }
      setState(() => _future = _load());
      _notice('Compétition supprimée.');
    } catch (error) {
      if (!mounted) return;
      final errorText = error.toString().toLowerCase();
      if (errorText.contains('23503') ||
          errorText.contains('foreign key constraint')) {
        _notice(
          'Suppression refusée : cette compétition contient des matchs ou '
          'des résultats. Ils doivent être conservés.',
        );
      } else {
        _notice('Suppression impossible : $error');
      }
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Compétitions et éditions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Créer une compétition',
              onPressed: _createCompetition,
              icon: const Icon(Icons.add, color: Color(0xFFFCD116)),
            ),
          ],
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(() => _future = _load()),
                  child: const Text('Impossible de charger. Réessayer'),
                ),
              );
            }
            final competitions = snapshot.data ?? const [];
            if (competitions.isEmpty) {
              return const Center(
                child: Text(
                  'Aucune compétition. Appuyez sur + pour en créer une.',
                  style: TextStyle(color: Colors.white60),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                final future = _load();
                setState(() => _future = future);
                await future;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: competitions.map(_competitionCard).toList(),
              ),
            );
          },
        ),
      ),
    ],
  );

  Widget _competitionCard(Map<String, dynamic> competition) {
    final seasons = (competition['seasons'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final type = competition['competition_type'] as String? ?? 'league';
    final typeLabel = switch (type) {
      'cup' => 'Coupe à élimination directe',
      'international' => 'Tournoi avec groupes',
      _ => 'Championnat',
    };
    return Card(
      color: const Color(0xFF1A2634),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    competition['name'] as String? ?? 'Compétition',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Créer une nouvelle édition',
                  onPressed: () => _createCompetition(existing: competition),
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Color(0xFFFCD116),
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer la compétition',
                  onPressed: () => _deleteCompetition(competition),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(typeLabel, style: const TextStyle(color: Colors.white60)),
            for (final season in seasons) ...[
              const Divider(color: Colors.white12, height: 20),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  season['name'] as String? ?? 'Édition',
                  style: const TextStyle(
                    color: Color(0xFFFCD116),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${(season['competition_teams'] as List? ?? const []).length} équipes'
                  '${type == 'international' ? ' · ${season['group_count']} groupes · ${season['qualifiers_per_group']} qualifiés/groupe' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                children: [
                  for (final entry
                      in (season['competition_teams'] as List? ?? const []).map(
                        (item) => Map<String, dynamic>.from(item as Map),
                      ))
                    ListTile(
                      dense: true,
                      title: Text(
                        entry['team_name'] as String? ?? 'Équipe',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: entry['group_name'] == null
                          ? null
                          : Text(
                              'Groupe ${entry['group_name']}',
                              style: const TextStyle(color: Colors.white54),
                            ),
                      trailing: Text(
                        entry['is_eliminated'] == true
                            ? 'Éliminée'
                            : entry['is_qualified'] == true
                            ? 'Qualifiée'
                            : 'En lice',
                        style: TextStyle(
                          color: entry['is_eliminated'] == true
                              ? Colors.redAccent
                              : entry['is_qualified'] == true
                              ? const Color(0xFF7ED6A5)
                              : Colors.white54,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _groupLabel(int index) {
  var value = index;
  var label = '';
  do {
    label = String.fromCharCode(65 + value % 26) + label;
    value = value ~/ 26 - 1;
  } while (value >= 0);
  return label;
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Champ obligatoire.' : null;

String? _positiveInteger(String? value) {
  final integer = int.tryParse(value?.trim() ?? '');
  return integer == null || integer < 1 || integer > 128
      ? 'Saisissez un entier entre 1 et 128.'
      : null;
}
