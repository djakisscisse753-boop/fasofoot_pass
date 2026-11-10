import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ticket_model.dart';

class TicketService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Récupère les billets de l'utilisateur avec les informations du match correspondant.
  Future<List<TicketModel>> getUserTickets() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    try {
      // 1. Tenter avec la relation FK directe
      final response = await _supabase
          .from('tickets')
          .select(
            'id, match_id, user_id, category_name, customer_name, customer_phone, '
            'price, qr_token_secret, status, scanned_at, scanned_by, created_at, '
            'match:matches(teams, date_time, stadium, city)',
          )
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => TicketModel.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (_) {
      // 2. Si la relation FK match:matches n'est pas déclarée en base, charger les tickets puis les matches séparément
      final ticketRows = await _supabase
          .from('tickets')
          .select(
            'id, match_id, user_id, category_name, customer_name, customer_phone, '
            'price, qr_token_secret, status, scanned_at, scanned_by, created_at',
          )
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final list = (ticketRows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return [];

      final matchIds = list
          .map((t) => t['match_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> matchesMap = {};
      if (matchIds.isNotEmpty) {
        try {
          final matchesRows = await _supabase
              .from('matches')
              .select('id, teams, date_time, stadium, city')
              .filter('id', 'in', matchIds);
          for (final m in (matchesRows as List)) {
            final map = Map<String, dynamic>.from(m as Map);
            matchesMap[map['id'] as String] = map;
          }
        } catch (_) {}
      }

      return list.map((json) {
        final mId = json['match_id'] as String?;
        final combined = Map<String, dynamic>.from(json);
        if (mId != null && matchesMap.containsKey(mId)) {
          combined['match'] = matchesMap[mId];
        }
        return TicketModel.fromJson(combined);
      }).toList();
    }
  }

  /// Valide et scanne un ticket via son secret QR (Réservé aux agents de stade / super admin)
  Future<Map<String, dynamic>> scanAndValidateTicket(String qrSecret) async {
    try {
      final response = await _supabase.rpc(
        'validate_ticket',
        params: {'p_qr_secret': qrSecret.trim()},
      );
      final result = Map<String, dynamic>.from(response as Map);
      final ticketJson = result['ticket'];
      return {
        ...result,
        if (ticketJson is Map)
          'ticket': TicketModel.fromJson(Map<String, dynamic>.from(ticketJson)),
      };
    } catch (e) {
      final errStr = e.toString();
      String errorMsg = 'Vérification impossible. Contrôlez la connexion et réessayez.';
      if (errStr.contains('42501') || errStr.toLowerCase().contains('réservé')) {
        errorMsg = 'Accès réservé : votre compte n\'a pas les droits d\'agent de stade.';
      } else if (errStr.contains('message:')) {
        errorMsg = errStr;
      }
      return {
        'success': false,
        'message': errorMsg,
      };
    }
  }
}
