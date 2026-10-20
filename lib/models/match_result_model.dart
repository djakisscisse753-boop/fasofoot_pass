class MatchResultModel {
  final String id;
  final String
  category; // 'Ligue 1 LONAB', 'Ligue 2', 'Étalons', 'Coupe du Faso'
  final String? homeTeamId;
  final String? awayTeamId;
  final String homeTeamName;
  final String awayTeamName;
  final int homeScore;
  final int awayScore;
  final DateTime matchDate;
  final String status; // 'upcoming', 'live', 'finished'

  MatchResultModel({
    required this.id,
    required this.category,
    this.homeTeamId,
    this.awayTeamId,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.homeScore,
    required this.awayScore,
    required this.matchDate,
    required this.status,
  });

  factory MatchResultModel.fromJson(Map<String, dynamic> json) {
    return MatchResultModel(
      id: json['id'],
      category: json['category'],
      homeTeamId: json['home_team_id'],
      awayTeamId: json['away_team_id'],
      homeTeamName: json['home_team_name'],
      awayTeamName: json['away_team_name'],
      homeScore: json['home_score'] ?? 0,
      awayScore: json['away_score'] ?? 0,
      matchDate: DateTime.parse(json['match_date']),
      status: json['status'] ?? 'finished',
    );
  }
}
