class ProductModel {
  final String id;
  final String? clubId;
  final String title;
  final String? description;
  final double price;
  final String? imageUrl;
  final String? clubLogoUrl;
  final int stock;

  ProductModel({
    required this.id,
    this.clubId,
    required this.title,
    this.description,
    required this.price,
    this.imageUrl,
    this.clubLogoUrl,
    this.stock = 0,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'],
      clubId: json['club_id'],
      title: json['title'],
      description: json['description'],
      price: (json['price'] as num).toDouble(),
      imageUrl: json['image_url'],
      clubLogoUrl: (json['clubs'] as Map<String, dynamic>?)?['logo_url'] as String?,
      stock: json['stock'] ?? 0,
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
