import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/club_model.dart';

class MarketplaceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Récupère la liste de tous les clubs pour le filtrage
  Future<List<Club>> getAllClubs() async {
    try {
      final response = await _supabase
          .from('clubs')
          .select('id, name, short_name, city, logo_url, marketing_phone, headquarters_address, manager_name, maps_url')
          .order('name');
      return (response as List)
          .map((json) => Club.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Récupère les articles en stock avec les détails du club vendeur
  Future<List<ProductModel>> getProducts({String? clubId}) async {
    var query = _supabase
        .from('products')
        .select('*, clubs(id, name, city, logo_url, marketing_phone, headquarters_address, manager_name, maps_url)')
        .eq('is_active', true)
        .gt('stock', 0);

    if (clubId != null && clubId.isNotEmpty) {
      query = query.eq('club_id', clubId);
    }

    final response = await query.order('created_at', ascending: false);

    return (response as List)
        .map((json) => ProductModel.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  /// Initie le paiement d'une commande via la fonction Edge YengaPay
  Future<Map<String, dynamic>> startCheckout({
    required List<Map<String, dynamic>> items,
    required String phoneNumber,
    String? customerName,
  }) async {
    final response = await _supabase.functions.invoke(
      'initiate-marketplace-payment',
      body: {
        'items': items,
        'phone_number': phoneNumber,
        if (customerName != null && customerName.isNotEmpty)
          'customer_name': customerName,
      },
    );
    final data = response.data;
    if (data is! Map ||
        data['success'] != true ||
        data['checkout_url'] is! String) {
      final message = data is Map ? data['error'] : null;
      throw StateError(
        message?.toString() ?? 'Impossible de préparer le paiement YengaPay.',
      );
    }
    return {
      'checkout_url': data['checkout_url'] as String,
      'order_id': data['order_id'] as String?,
    };
  }

  /// Récupère l'historique des commandes de l'utilisateur connecté
  Future<List<Map<String, dynamic>>> getMyOrders() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final response = await _supabase
        .from('marketplace_orders')
        .select(
          'id, status, total_amount, payment_phone, customer_name, pickup_code, provider_transaction_id, created_at, '
          'marketplace_order_items(id, product_title, unit_price, quantity, club_name, club_city, marketing_phone, headquarters_address, manager_name, maps_url, fulfillment_status)',
        )
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(40);

    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  /// Met à jour le statut de remise d'un article (utilisé par le club admin)
  Future<void> updateFulfillmentStatus({
    required String orderItemId,
    required String status,
  }) async {
    await _supabase
        .from('marketplace_order_items')
        .update({'fulfillment_status': status})
        .eq('id', orderItemId);
  }

  /// Rafraîchit l'état après le webhook; seule sa confirmation serveur marque payé.
  Future<bool> refreshOrderPaymentStatus(String orderId) async {
    final response = await _supabase.rpc(
      'verify_or_confirm_order',
      params: {'p_order_id': orderId},
    );
    if (response is! Map) {
      throw const FormatException('Réponse de vérification de commande invalide.');
    }
    return response['success'] == true && response['status'] == 'paid';
  }
}
