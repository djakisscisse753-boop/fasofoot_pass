import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/match_model.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<MatchModel>> getUpcomingMatches() async {
    final response = await _client
        .from('matches')
        .select(
          'id, teams, date_time, stadium, price, is_hero, competition:competitions(name)',
        )
        .gte('date_time', DateTime.now().toUtc().toIso8601String())
        .order('date_time');
    return (response as List)
        .map((row) => MatchModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }
}
