import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/match_result_model.dart';

class NewsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Récupère tous les résultats récents classés par date
  Future<List<MatchResultModel>> getMatchResults({String? category}) async {
    var query = _supabase
        .from('match_results')
        .select('*, competition:competitions(competition_type)');

    if (category != null && category != 'Tous') {
      query = query.eq('category', category);
    }

    final response = await query.order('match_date', ascending: false);

    return (response as List)
        .map((json) => MatchResultModel.fromJson(json))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getSeasons(String competitionId) async {
    final rows = await _supabase
        .from('seasons')
        .select('id, name, starts_on, ends_on, is_active, created_at')
        .eq('competition_id', competitionId)
        .order('created_at', ascending: false);
    return (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getCompetitions() async {
    final rows = await _supabase
        .from('competitions')
        .select('id, name, competition_type')
        .eq('is_active', true)
        .order('name');
    return (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getCompetitionTeams(
    String seasonId,
  ) async {
    final rows = await _supabase
        .from('competition_teams')
        .select('team_name, group_name, is_eliminated')
        .eq('season_id', seasonId)
        .order('group_name')
        .order('team_name');
    return (rows as List).map((row) => Map<String, dynamic>.from(row)).toList();
  }
}
