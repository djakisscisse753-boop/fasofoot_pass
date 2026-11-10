class ProductModel {
  final String id;
  final String? clubId;
  final String title;
  final String? description;
  final double price;
  final String? imageUrl;
  final String? clubLogoUrl;
  final String? clubName;
  final String? clubCity;
  final String? marketingPhone;
  final String? headquartersAddress;
  final String? managerName;
  final String? mapsUrl;
  final int stock;

  ProductModel({
    required this.id,
    this.clubId,
    required this.title,
    this.description,
    required this.price,
    this.imageUrl,
    this.clubLogoUrl,
    this.clubName,
    this.clubCity,
    this.marketingPhone,
    this.headquartersAddress,
    this.managerName,
    this.mapsUrl,
    this.stock = 0,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final clubData = json['clubs'] as Map<String, dynamic>?;
    return ProductModel(
      id: json['id'] as String,
      clubId: json['club_id'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      price: (json['price'] as num? ?? 0).toDouble(),
      imageUrl: json['image_url'] as String?,
      clubLogoUrl: clubData?['logo_url'] as String?,
      clubName: clubData?['name'] as String?,
      clubCity: clubData?['city'] as String?,
      marketingPhone: clubData?['marketing_phone'] as String?,
      headquartersAddress: clubData?['headquarters_address'] as String?,
      managerName: clubData?['manager_name'] as String?,
      mapsUrl: clubData?['maps_url'] as String?,
      stock: (json['stock'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'club_id': clubId,
      'title': title,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'stock': stock,
    };
  }
}
