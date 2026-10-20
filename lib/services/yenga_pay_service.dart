import 'package:supabase_flutter/supabase_flutter.dart';

class TicketCheckout {
  const TicketCheckout({required this.ticketId, required this.checkoutUrl});

  final String ticketId;
  final String checkoutUrl;
}

class YengaPayService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<TicketCheckout> createCheckout({
    required String matchId,
    required String categoryName,
    required String customerName,
    required String phoneNumber,
  }) async {
    final response = await _supabase.functions.invoke(
      'initiate-yenga-payment',
      body: {
        'match_id': matchId,
        'category_name': categoryName,
        'customer_name': customerName,
        'phone_number': phoneNumber,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      throw Exception('Erreur serveur (${response.status}).');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['success'] != true ||
        data['ticket_id'] is! String ||
        data['checkout_url'] is! String) {
      throw Exception(data['error'] ?? 'Réponse de paiement invalide.');
    }

    return TicketCheckout(
      ticketId: data['ticket_id'] as String,
      checkoutUrl: data['checkout_url'] as String,
    );
  }

  Stream<Map<String, dynamic>> listenToTicketStatus(String ticketId) {
    return _supabase
        .from('tickets')
        .stream(primaryKey: ['id'])
        .eq('id', ticketId)
        .map((rows) => rows.isEmpty ? <String, dynamic>{} : rows.first);
  }
}
