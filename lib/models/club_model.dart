class Club {
  final String id;
  final String name;
  final String shortName;
  final String city;
  final String? logoUrl;
  final String? marketingPhone;
  final String? headquartersAddress;
  final String? managerName;
  final String? mapsUrl;

  Club({
    required this.id,
    required this.name,
    required this.shortName,
    required this.city,
    this.logoUrl,
    this.marketingPhone,
    this.headquartersAddress,
    this.managerName,
    this.mapsUrl,
  });

  factory Club.fromJson(Map<String, dynamic> json) {
    return Club(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      shortName: json['short_name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
      marketingPhone: json['marketing_phone'] as String?,
      headquartersAddress: json['headquarters_address'] as String?,
      managerName: json['manager_name'] as String?,
      mapsUrl: json['maps_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'short_name': shortName,
    'city': city,
    'logo_url': logoUrl,
    'marketing_phone': marketingPhone,
    'headquarters_address': headquartersAddress,
    'manager_name': managerName,
    'maps_url': mapsUrl,
  };
}
