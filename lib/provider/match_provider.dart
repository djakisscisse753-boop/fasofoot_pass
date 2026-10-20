import 'package:flutter/foundation.dart';
import '../models/match_model.dart';
import '../services/supabase_service.dart';

class MatchProvider extends ChangeNotifier {
  MatchProvider({SupabaseService? service})
    : _service = service ?? SupabaseService();

  final SupabaseService _service;
  List<MatchModel> _matches = const [];
  bool _isLoading = false;
  String? _errorMessage;

  List<MatchModel> get matches => _matches;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadUpcomingMatches() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _matches = await _service.getUpcomingMatches();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
