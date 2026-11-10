class MatchResultModel {
  final String id;
  final String category; // 'Ligue 1 LONAB', 'Ligue 2', 'Étalons', 'Coupe du Faso'
  final String? homeTeamId;
  final String? awayTeamId;
  final String? competitionId;
  final String? seasonId;
  final String homeTeamName;
  final String awayTeamName;
  final int homeScore;
  final int awayScore;
  final DateTime matchDate;
  final String status; // 'upcoming', 'live', 'finished'
  final String? scorers;
  final String? assists;

  MatchResultModel({
    required this.id,
    required this.category,
    this.homeTeamId,
    this.awayTeamId,
    this.competitionId,
    this.seasonId,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.homeScore,
    required this.awayScore,
    required this.matchDate,
    required this.status,
    this.scorers,
    this.assists,
  });

  factory MatchResultModel.fromJson(Map<String, dynamic> json) {
    return MatchResultModel(
      id: json['id'] as String,
      category: json['category'] as String? ?? 'Match',
      homeTeamId: json['home_team_id'] as String?,
      awayTeamId: json['away_team_id'] as String?,
      competitionId: json['competition_id'] as String?,
      seasonId: json['season_id'] as String?,
      homeTeamName: json['home_team_name'] as String? ?? 'Domicile',
      awayTeamName: json['away_team_name'] as String? ?? 'Visiteur',
      homeScore: (json['home_score'] as num?)?.toInt() ?? 0,
      awayScore: (json['away_score'] as num?)?.toInt() ?? 0,
      matchDate: DateTime.parse(json['match_date'] as String),
      status: json['status'] as String? ?? 'finished',
      scorers: json['scorers'] as String?,
      assists: json['assists'] as String?,
    );
  }
}
