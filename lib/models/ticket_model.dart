class TicketModel {
  final String id;
  final String? matchId;
  final String? userId;
  final String categoryName;
  final double price;
  final String qrTokenSecret;
  final String status; // 'pending', 'paid', 'failed', 'used', 'cancelled', 'refund_required'
  final DateTime? scannedAt;
  final String? scannedBy;
  final DateTime? createdAt;
  final String? gate;
  final String? seatNumber;
  // Infos du propriétaire du billet
  final String? customerName;
  final String? customerPhone;
  // Champs issus de la jointure avec la table matches
  final String? matchTeams;
  final DateTime? matchDateTime;
  final String? matchStadium;
  final String? matchCity;

  TicketModel({
    required this.id,
    this.matchId,
    this.userId,
    required this.categoryName,
    required this.price,
    required this.qrTokenSecret,
    required this.status,
    this.scannedAt,
    this.scannedBy,
    this.createdAt,
    this.gate,
    this.seatNumber,
    this.customerName,
    this.customerPhone,
    this.matchTeams,
    this.matchDateTime,
    this.matchStadium,
    this.matchCity,
  });

  bool get isValid => status == 'paid';
  bool get isPending => status == 'pending';
  bool get isUsed => status == 'used';
  bool get isCancelled => status == 'cancelled' || status == 'failed';
  bool get isRefundRequired => status == 'refund_required';

  String get statusLabel {
    switch (status) {
      case 'paid':
        return 'VALIDE';
      case 'pending':
        return 'EN ATTENTE';
      case 'used':
        return 'UTILISÉ';
      case 'cancelled':
        return 'ANNULÉ';
      case 'failed':
        return 'ÉCHEC';
      case 'refund_required':
        return 'REMB. REQUIS';
      default:
        return status.toUpperCase();
    }
  }

  factory TicketModel.fromJson(Map<String, dynamic> json) {
    final matchJson = json['match'] as Map<String, dynamic>?;
    return TicketModel(
      id: json['id']?.toString() ?? '',
      matchId: json['match_id']?.toString(),
      userId: json['user_id']?.toString(),
      categoryName: json['category_name'] as String? ?? 'Tribune Standard',
      price: (json['price'] as num? ?? 0).toDouble(),
      qrTokenSecret: json['qr_token_secret'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      scannedAt: json['scanned_at'] != null
          ? DateTime.parse(json['scanned_at'] as String)
          : null,
      scannedBy: json['scanned_by']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      gate: json['gate']?.toString(),
      seatNumber: json['seat_number']?.toString(),
      customerName: json['customer_name']?.toString(),
      customerPhone: json['customer_phone']?.toString(),
      matchTeams: matchJson?['teams'] as String?,
      matchDateTime: matchJson?['date_time'] != null
          ? DateTime.parse(matchJson!['date_time'] as String)
          : null,
      matchStadium: matchJson?['stadium'] as String?,
      matchCity: matchJson?['city'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'match_id': matchId,
    'user_id': userId,
    'category_name': categoryName,
    'price': price,
    'qr_token_secret': qrTokenSecret,
    'status': status,
    'scanned_at': scannedAt?.toIso8601String(),
    'scanned_by': scannedBy,
    'customer_name': customerName,
    'customer_phone': customerPhone,
  };
}
