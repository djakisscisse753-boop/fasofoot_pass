class MatchModel {
  final String id;
  final String teams;
  final DateTime dateTime;
  final String stadium;
  final String? city;
  final String? homeClubLogoUrl;
  final String? awayClubLogoUrl;
  final int basePrice;
  final String competition;
  final bool isHero;
  final String status; // 'scheduled', 'live', 'finished', 'postponed', 'cancelled'

  const MatchModel({
    required this.id,
    required this.teams,
    required this.dateTime,
    required this.stadium,
    this.city,
    this.homeClubLogoUrl,
    this.awayClubLogoUrl,
    required this.basePrice,
    this.competition = 'Autre',
    this.isHero = false,
    this.status = 'scheduled',
  });

  String get date =>
      '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} • ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

  bool get isLive => status == 'live';
  bool get isFinished => status == 'finished';
  bool get isScheduled => status == 'scheduled';

  factory MatchModel.fromJson(Map<String, dynamic> json) => MatchModel(
    id: json['id'] as String,
    teams: json['teams'] as String? ?? 'Match à confirmer',
    dateTime: DateTime.parse(json['date_time'] as String),
    stadium: json['stadium'] as String? ?? 'Stade à confirmer',
    city: json['city'] as String?,
    homeClubLogoUrl:
        (json['home_club'] as Map<String, dynamic>?)?['logo_url'] as String?,
    awayClubLogoUrl:
        (json['away_club'] as Map<String, dynamic>?)?['logo_url'] as String?,
    basePrice: (json['price'] as num?)?.toInt() ?? 0,
    competition:
        (json['competition'] as Map<String, dynamic>?)?['name'] as String? ??
        'Autre',
    isHero: json['is_hero'] as bool? ?? false,
    status: json['status'] as String? ?? 'scheduled',
  );
}
