import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';

class MarketplaceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Récupère les articles en stock
  Future<List<ProductModel>> getProducts({String? clubId}) async {
    final clubs = await _supabase
        .from('clubs')
        .select('id')
        .or('marketing_phone.not.is.null,headquarters_address.not.is.null');
    final readyClubIds = (clubs as List)
        .map((club) => club['id'] as String)
        .toList();
    if (readyClubIds.isEmpty) return [];

    var query = _supabase
        .from('products')
        .select('*, clubs(logo_url)')
        .eq('is_active', true)
        .gt('stock', 0)
        .inFilter('club_id', readyClubIds);

    if (clubId != null) {
      query = query.eq('club_id', clubId);
    }

    final response = await query.order('created_at', ascending: false);

    return (response as List)
        .map((json) => ProductModel.fromJson(json))
        .toList();
  }

  Future<String> startCheckout({
    required List<Map<String, dynamic>> items,
    required String phoneNumber,
  }) async {
    final response = await _supabase.functions.invoke(
      'initiate-marketplace-payment',
      body: {'items': items, 'phone_number': phoneNumber},
    );
    final data = response.data;
    if (data is! Map ||
        data['success'] != true ||
        data['checkout_url'] is! String) {
      final message = data is Map ? data['error'] : null;
      throw StateError(
        message?.toString() ?? 'Impossible de préparer le paiement.',
      );
    }
    return data['checkout_url'] as String;
  }

  Future<List<Map<String, dynamic>>> getMyOrders() async {
    final response = await _supabase
        .from('marketplace_orders')
        .select(
          'id,status,total_amount,created_at,marketplace_order_items(product_title,unit_price,quantity,club_name,club_city,marketing_phone,headquarters_address,fulfillment_status)',
        )
        .order('created_at', ascending: false)
        .limit(30);
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
