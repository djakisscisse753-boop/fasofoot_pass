class ProfileModel {
  final String id;
  final String? phoneNumber;
  final String? fullName;
  final String? favoriteClubId;
  final String role; // 'supporter', 'agent_stade', 'admin_club', 'super_admin'
  final DateTime? createdAt;

  ProfileModel({
    required this.id,
    this.phoneNumber,
    this.fullName,
    this.favoriteClubId,
    required this.role,
    this.createdAt,
  });

  bool get isAgentOrAdmin =>
      role == 'agent_stade' || role == 'admin_club' || role == 'super_admin';

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'],
      phoneNumber: json['phone_number'],
      fullName: json['full_name'],
      favoriteClubId: json['favorite_club_id'],
      role: json['role'] ?? 'supporter',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone_number': phoneNumber,
      'full_name': fullName,
      'favorite_club_id': favoriteClubId,
      'role': role,
    };
  }
}
