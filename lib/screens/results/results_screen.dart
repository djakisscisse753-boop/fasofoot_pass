import 'package:flutter/material.dart';
import '../../models/match_result_model.dart';
import '../../services/news_service.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final NewsService _service = NewsService();
  late Future<List<MatchResultModel>> _resultsFuture;
  String _selectedCategory = 'Toutes';
  String _selectedSeasonId = 'all';
  bool _activeSeasonChosen = false;
  Future<List<Map<String, dynamic>>>? _seasonsFuture;

  @override
  void initState() {
    super.initState();
    _resultsFuture = _service.getMatchResults();
  }

  Future<void> _refresh() async {
    final future = _service.getMatchResults();
    setState(() => _resultsFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        title: const Text(
          'Résultats & classements',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF101820),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<MatchResultModel>>(
        future: _resultsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF008751)));
          }
          if (snapshot.hasError) {
            return _message(
              'Impossible de charger les résultats. Réessayez dans un instant.',
              action: TextButton(
                onPressed: _refresh,
                child: const Text('Réessayer'),
              ),
            );
          }

          final results = snapshot.data ?? const <MatchResultModel>[];
          final categories =
              results.map((match) => match.category).toSet().toList()..sort();
          if (_selectedCategory != 'Toutes' &&
              !categories.contains(_selectedCategory)) {
            _selectedCategory = 'Toutes';
          }
          final filtered = _selectedCategory == 'Toutes'
              ? results
              : results
                    .where((match) => match.category == _selectedCategory)
                    .toList();
          final competitionIds = filtered
              .map((match) => match.competitionId)
              .whereType<String>()
              .toList();
          final competitionId =
              competitionIds.isEmpty ? null : competitionIds.first;
          if (_selectedCategory != 'Toutes' &&
              competitionId != null &&
              _seasonsFuture == null) {
            _seasonsFuture = _service.getSeasons(competitionId);
          }
          final seasonFiltered = _selectedSeasonId == 'all'
              ? filtered
              : filtered
                    .where((match) => match.seasonId == _selectedSeasonId)
                    .toList();
          final isLeague =
              _selectedCategory.toLowerCase().contains('ligue');

          return RefreshIndicator(
            onRefresh: _refresh,
            color: const Color(0xFF008751),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _categorySelector(categories),
                if (_selectedCategory != 'Toutes' && isLeague)
                  _seasonSelector(),
                if (isLeague) ...[
                  const SizedBox(height: 24),
                  _sectionTitle('Classement général'),
                  _buildStandings(seasonFiltered),
                ],
                const SizedBox(height: 24),
                _sectionTitle('Résultats des rencontres'),
                if (seasonFiltered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Text(
                      'Aucun résultat publié pour cette compétition.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                else
                  ...seasonFiltered.map(_resultCard),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _categorySelector(List<String> categories) => SizedBox(
    height: 42,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: ['Toutes', ...categories].map((category) {
        final selected = category == _selectedCategory;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(category),
            selected: selected,
            onSelected: (_) {
              setState(() {
                _selectedCategory = category;
                _selectedSeasonId = 'all';
                _activeSeasonChosen = false;
                _seasonsFuture = null;
              });
            },
            selectedColor: const Color(0xFF008751),
            backgroundColor: const Color(0xFF1A2634),
            labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
            side: BorderSide.none,
          ),
        );
      }).toList(),
    ),
  );

  Widget _seasonSelector() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _seasonsFuture,
    builder: (context, snapshot) {
      final seasons = snapshot.data ?? const <Map<String, dynamic>>[];
      if (!snapshot.hasData || seasons.isEmpty) return const SizedBox.shrink();
      final activeSeason = seasons.cast<Map<String, dynamic>?>().firstWhere(
        (season) => season?['is_active'] == true,
        orElse: () => null,
      );
      if (!_activeSeasonChosen && activeSeason != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _activeSeasonChosen) return;
          setState(() {
            _selectedSeasonId = activeSeason['id'] as String;
            _activeSeasonChosen = true;
          });
        });
      }
      if (_selectedSeasonId != 'all' &&
          !seasons.any((season) => season['id'] == _selectedSeasonId)) {
        _selectedSeasonId = 'all';
      }
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DropdownButtonFormField<String>(
          initialValue: _selectedSeasonId,
          dropdownColor: const Color(0xFF1A2634),
          decoration: const InputDecoration(
            labelText: 'Saison / Édition',
            labelStyle: TextStyle(color: Colors.white70),
            border: OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
          ),
          style: const TextStyle(color: Colors.white),
          items: [
            const DropdownMenuItem(
              value: 'all',
              child: Text('Toutes les saisons'),
            ),
            ...seasons.map(
              (season) => DropdownMenuItem<String>(
                value: season['id'] as String,
                child: Text(season['name'] as String),
              ),
            ),
          ],
          onChanged: (value) => setState(() {
            _selectedSeasonId = value ?? 'all';
            _activeSeasonChosen = true;
          }),
        ),
      );
    },
  );

  Widget _buildStandings(List<MatchResultModel> matches) {
    final table = <String, _Standing>{};
    for (final match in matches.where((item) => _isFinished(item.status))) {
      final home = table.putIfAbsent(
        match.homeTeamName,
        () => _Standing(match.homeTeamName),
      );
      final away = table.putIfAbsent(
        match.awayTeamName,
        () => _Standing(match.awayTeamName),
      );
      home.played++;
      away.played++;
      home.goalsFor += match.homeScore;
      home.goalsAgainst += match.awayScore;
      away.goalsFor += match.awayScore;
      away.goalsAgainst += match.homeScore;
      if (match.homeScore > match.awayScore) {
        home.won++;
        away.lost++;
      } else if (match.homeScore < match.awayScore) {
        away.won++;
        home.lost++;
      } else {
        home.drawn++;
        away.drawn++;
      }
    }

    final standings = table.values.toList()
      ..sort((a, b) {
        final points = b.points.compareTo(a.points);
        if (points != 0) return points;
        final difference = b.goalDifference.compareTo(a.goalDifference);
        if (difference != 0) return difference;
        final goalsFor = b.goalsFor.compareTo(a.goalsFor);
        if (goalsFor != 0) return goalsFor;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    if (standings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'Le classement sera calculé dès que les premiers matchs seront terminés.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const _StandingRow(
            position: '#',
            team: 'Club',
            played: 'MJ',
            won: 'V',
            drawn: 'N',
            lost: 'D',
            difference: 'DB',
            points: 'Pts',
            header: true,
          ),
          for (var i = 0; i < standings.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: Colors.white10, indent: 12, endIndent: 12),
            _StandingRow(
              position: '${i + 1}',
              team: standings[i].name,
              played: '${standings[i].played}',
              won: '${standings[i].won}',
              drawn: '${standings[i].drawn}',
              lost: '${standings[i].lost}',
              difference: '${standings[i].goalDifference > 0 ? '+' : ''}${standings[i].goalDifference}',
              points: '${standings[i].points}',
              isTop: i < 3,
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultCard(MatchResultModel match) {
    final finished = _isFinished(match.status);
    final live = match.status.toLowerCase() == 'live';
    final homeWon = match.homeScore > match.awayScore;
    final awayWon = match.awayScore > match.homeScore;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: live ? Colors.redAccent.withValues(alpha: 0.6) : Colors.white10,
          width: live ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // En-tête du match (compétition & statut/date)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: live
                  ? Colors.redAccent.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  match.category.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFFCD116),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                if (live)
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Text(
                        'EN DIRECT',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    _date(match.matchDate),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          // Scores et équipes
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    match.homeTeamName,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: homeWon ? FontWeight.bold : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B151D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: live ? Colors.redAccent : Colors.white12,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    finished || live
                        ? '${match.homeScore} - ${match.awayScore}'
                        : 'vs',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    match.awayTeamName,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: awayWon ? FontWeight.bold : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Buteurs et passeurs si renseignés
          if ((match.scorers != null && match.scorers!.trim().isNotEmpty) ||
              (match.assists != null && match.assists!.trim().isNotEmpty)) ...[
            const Divider(color: Colors.white12, height: 1),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (match.scorers != null && match.scorers!.trim().isNotEmpty)
                    _eventItem(
                      Icons.sports_soccer,
                      'Buteurs :',
                      match.scorers!,
                      const Color(0xFF7ED6A5),
                    ),
                  if (match.assists != null && match.assists!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _eventItem(
                      Icons.auto_awesome_motion_outlined,
                      'Passeurs :',
                      match.assists!,
                      const Color(0xFF7BAAFF),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _eventItem(IconData icon, String label, String value, Color color) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(
        '$label ',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12,
          ),
        ),
      ),
    ],
  );

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _message(String text, {Widget? action}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          ?action,
        ],
      ),
    ),
  );

  bool _isFinished(String status) => const {
    'finished',
    'completed',
    'termine',
    'terminé',
  }.contains(status.toLowerCase());

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _Standing {
  final String name;
  int played = 0;
  int won = 0;
  int drawn = 0;
  int lost = 0;
  int goalsFor = 0;
  int goalsAgainst = 0;

  _Standing(this.name);
  int get points => won * 3 + drawn;
  int get goalDifference => goalsFor - goalsAgainst;
}

class _StandingRow extends StatelessWidget {
  final String position;
  final String team;
  final String played;
  final String won;
  final String drawn;
  final String lost;
  final String difference;
  final String points;
  final bool header;
  final bool isTop;

  const _StandingRow({
    required this.position,
    required this.team,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.difference,
    required this.points,
    this.header = false,
    this.isTop = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            position,
            style: _style.copyWith(
              color: isTop ? const Color(0xFFFCD116) : _style.color,
              fontWeight: isTop ? FontWeight.bold : _style.fontWeight,
            ),
          ),
        ),
        Expanded(
          child: Text(
            team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style.copyWith(
              fontWeight: isTop ? FontWeight.bold : _style.fontWeight,
            ),
          ),
        ),
        SizedBox(
          width: 26,
          child: Text(played, textAlign: TextAlign.center, style: _style),
        ),
        SizedBox(
          width: 24,
          child: Text(won, textAlign: TextAlign.center, style: _style),
        ),
        SizedBox(
          width: 24,
          child: Text(drawn, textAlign: TextAlign.center, style: _style),
        ),
        SizedBox(
          width: 24,
          child: Text(lost, textAlign: TextAlign.center, style: _style),
        ),
        SizedBox(
          width: 32,
          child: Text(difference, textAlign: TextAlign.center, style: _style),
        ),
        SizedBox(
          width: 32,
          child: Text(
            points,
            textAlign: TextAlign.end,
            style: _style.copyWith(
              fontWeight: FontWeight.bold,
              color: header ? Colors.white54 : Colors.white,
            ),
          ),
        ),
      ],
    ),
  );

  TextStyle get _style => TextStyle(
    color: header ? Colors.white54 : Colors.white,
    fontSize: header ? 11 : 13,
    fontWeight: header ? FontWeight.bold : FontWeight.normal,
  );
}
