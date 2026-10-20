class Club {
  final String id;
  final String name;
  final String shortName;
  final String city;
  final String? logoUrl;

  Club({
    required this.id,
    required this.name,
    required this.shortName,
    required this.city,
    this.logoUrl,
  });

  factory Club.fromJson(Map<String, dynamic> json) {
    return Club(
      id: json['id'],
      name: json['name'],
      shortName: json['short_name'],
      city: json['city'],
      logoUrl: json['logo_url'],
    );
  }
}