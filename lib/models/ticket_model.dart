class TicketModel {
  final String id;
  final String? matchId;
  final String? userId;
  final String categoryName;
  final String? gate;
  final String? seatNumber;
  final double price;
  final String qrTokenSecret;
  final String status; // 'valid', 'used', 'cancelled'
  final DateTime? scannedAt;
  final String? scannedBy;
  final DateTime? createdAt;

  TicketModel({
    required this.id,
    this.matchId,
    this.userId,
    required this.categoryName,
    this.gate,
    this.seatNumber,
    required this.price,
    required this.qrTokenSecret,
    required this.status,
    this.scannedAt,
    this.scannedBy,
    this.createdAt,
  });

  bool get isValid => status == 'paid' || status == 'valid';

  factory TicketModel.fromJson(Map<String, dynamic> json) {
    return TicketModel(
      id: json['id']?.toString() ?? '',
      matchId: json['match_id']?.toString(),
      userId: json['user_id']?.toString(),
      categoryName: json['category_name'] ?? 'Tribune Standard',
      gate: json['gate'],
      seatNumber: json['seat_number'],
      price: (json['price'] as num? ?? 0).toDouble(),
      qrTokenSecret: json['qr_token_secret'] ?? '',
      status: json['status'] ?? 'valid',
      scannedAt: json['scanned_at'] != null
          ? DateTime.parse(json['scanned_at'])
          : null,
      scannedBy: json['scanned_by']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'match_id': matchId,
      'user_id': userId,
      'category_name': categoryName,
      'gate': gate,
      'seat_number': seatNumber,
      'price': price,
      'qr_token_secret': qrTokenSecret,
      'status': status,
      'scanned_at': scannedAt?.toIso8601String(),
      'scanned_by': scannedBy,
    };
  }
}
