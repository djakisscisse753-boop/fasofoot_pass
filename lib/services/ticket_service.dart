import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ticket_model.dart';

class TicketService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Récupère les billets avec le numéro utilisé lors de la réservation.
  Future<List<TicketModel>> getUserTickets() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final response = await _supabase
        .from('tickets')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => TicketModel.fromJson(json))
        .toList();
  }

  /// Valide et scanne un ticket via son secret QR (Réservé aux agents)
  Future<Map<String, dynamic>> scanAndValidateTicket(String qrSecret) async {
    try {
      final response = await _supabase.rpc(
        'validate_ticket',
        params: {'p_qr_secret': qrSecret},
      );
      final result = Map<String, dynamic>.from(response as Map);
      final ticketJson = result['ticket'];
      return {
        ...result,
        if (ticketJson is Map)
          'ticket': TicketModel.fromJson(Map<String, dynamic>.from(ticketJson)),
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Vérification impossible. Contrôlez la connexion et réessayez.',
      };
    }
  }
}
