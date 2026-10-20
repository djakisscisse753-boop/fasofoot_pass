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
        title: const Text('Résultats & classements'),
        backgroundColor: const Color(0xFF101820),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<MatchResultModel>>(
        future: _resultsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
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
          final isLeague = _selectedCategory.toLowerCase().contains('ligue');

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _categorySelector(categories),
                if (isLeague) ...[
                  const SizedBox(height: 20),
                  _sectionTitle('Classement'),
                  _buildStandings(filtered),
                ],
                const SizedBox(height: 20),
                _sectionTitle('Tous les matchs'),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Text(
                      'Aucun résultat publié pour cette compétition.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                else
                  ...filtered.map(_resultCard),
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
            onSelected: (_) => setState(() => _selectedCategory = category),
            selectedColor: const Color(0xFF008751),
            backgroundColor: const Color(0xFF1A2634),
            labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.white70,
            ),
            side: BorderSide.none,
          ),
        );
      }).toList(),
    ),
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
        return b.goalsFor.compareTo(a.goalsFor);
      });
    if (standings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'Le classement sera disponible après les premiers matchs terminés.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(14),
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
          for (var i = 0; i < standings.length; i++)
            _StandingRow(
              position: '${i + 1}',
              team: standings[i].name,
              played: '${standings[i].played}',
              won: '${standings[i].won}',
              drawn: '${standings[i].drawn}',
              lost: '${standings[i].lost}',
              difference: '${standings[i].goalDifference}',
              points: '${standings[i].points}',
            ),
        ],
      ),
    );
  }

  Widget _resultCard(MatchResultModel match) {
    final finished = _isFinished(match.status);
    final live = match.status.toLowerCase() == 'live';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  match.category,
                  style: const TextStyle(
                    color: Color(0xFFFCD116),
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                _date(match.matchDate),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  match.homeTeamName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                finished || live
                    ? '${match.homeScore}  -  ${match.awayScore}'
                    : 'vs',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Expanded(
                child: Text(
                  match.awayTeamName,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              live ? 'EN DIRECT' : (finished ? 'TERMINÉ' : 'À VENIR'),
              style: TextStyle(
                color: live ? Colors.redAccent : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
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
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        SizedBox(width: 24, child: Text(position, style: _style)),
        Expanded(
          child: Text(
            team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style,
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
          width: 30,
          child: Text(difference, textAlign: TextAlign.center, style: _style),
        ),
        SizedBox(
          width: 32,
          child: Text(points, textAlign: TextAlign.end, style: _style),
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
