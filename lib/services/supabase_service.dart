import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/match_model.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Récupère les matchs à venir disponibles à la réservation
  /// Un match qui a commencé (live) ou qui est terminé (finished) n'est plus proposé à l'achat.
  Future<List<MatchModel>> getUpcomingMatches() async {
    final response = await _client
        .from('matches')
        .select(
          'id, teams, date_time, stadium, city, price, is_hero, status, '
          'home_club:clubs!matches_home_club_id_fkey(name, logo_url), '
          'away_club:clubs!matches_away_club_id_fkey(name, logo_url), '
          'competition:competitions(name)',
        )
        .eq('status', 'scheduled')
        .gte('date_time', DateTime.now().toUtc().toIso8601String())
        .order('date_time');
    return (response as List)
        .map((row) => MatchModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }
}
