import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/match_result_model.dart';

class NewsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Récupère tous les résultats récents classés par date
  Future<List<MatchResultModel>> getMatchResults({String? category}) async {
    var query = _supabase.from('match_results').select();

    if (category != null && category != 'Tous') {
      query = query.eq('category', category);
    }

    final response = await query.order('match_date', ascending: false);

    return (response as List)
        .map((json) => MatchResultModel.fromJson(json))
        .toList();
  }
}
