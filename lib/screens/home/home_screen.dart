import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/match_model.dart';
import '../../services/supabase_service.dart';
import '../marketplace/marketplace_screen.dart';
import '../profile/profile_screen.dart';
import '../results/results_screen.dart';
import '../tickets/my_tickets_screen.dart';
import '../tickets/match_detail_booking_screen.dart';

// --- ÉCRAN PRINCIPAL ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _selectedCompetition = 'Toutes';
  Future<List<MatchModel>> _matchesFuture = SupabaseService()
      .getUpcomingMatches();

  void _navigateToBooking(BuildContext context, MatchModel match) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MatchDetailBookingScreen(match: match),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: _selectedIndex == 0
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF008751),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.sports_soccer,
                      color: Color(0xFFFCD116),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "FASOFOOT PASS",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 1.1,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Aucune nouvelle notification"),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Se déconnecter',
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          FutureBuilder<List<MatchModel>>(
            future: _matchesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Impossible de charger les matchs.',
                        style: TextStyle(color: Colors.white),
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => _matchesFuture = SupabaseService()
                              .getUpcomingMatches(),
                        ),
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                );
              }
              return _buildHomeContent(snapshot.data ?? const []);
            },
          ),
          const ResultsScreen(),
          const MyTicketsScreen(),
          const MarketplaceScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: const Color(0xFF1A2634),
        selectedItemColor: const Color(0xFFFCD116),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: "Accueil",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard_outlined),
            label: "Résultats",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.confirmation_number_outlined),
            label: "Billets",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront_outlined),
            label: "Boutique",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: "Profil",
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent(List<MatchModel> matches) {
    final categories =
        matches.map((match) => match.competition).toSet().toList()..sort();
    final visibleMatches = _selectedCompetition == 'Toutes'
        ? matches
        : matches
              .where((match) => match.competition == _selectedCompetition)
              .toList();
    final featured = visibleMatches.where((match) => match.isHero).toList();
    final heroMatch = featured.isNotEmpty
        ? featured.first
        : (visibleMatches.isEmpty ? null : visibleMatches.first);
    if (matches.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aucun match à venir pour le moment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heroMatch != null) _buildHeroMatchCard(context, heroMatch),
          const SizedBox(height: 28),
          _buildSectionHeader('Championnats & Compétitions'),
          const SizedBox(height: 12),
          _buildCategoriesList(['Toutes', ...categories]),
          const SizedBox(height: 28),
          _buildSectionHeader("Matchs à l'affiche"),
          const SizedBox(height: 12),
          _buildUpcomingMatchesList(context, visibleMatches),
          const SizedBox(height: 28),
          _buildMyTicketsBanner(context),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        TextButton(
          onPressed: () {},
          child: const Text(
            "Voir tout",
            style: TextStyle(color: Color(0xFF008751)),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroMatchCard(BuildContext context, MatchModel match) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF008751), Color(0xFF005A36)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              Icons.sports_soccer,
              size: 160,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDA291C),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "CHOC DE LA JOURNÉE",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  match.teams,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Color(0xFFFCD116),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      match.date,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 14,
                      color: Color(0xFFFCD116),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      match.city == null || match.city!.isEmpty
                          ? match.stadium
                          : '${match.stadium} · ${match.city}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _navigateToBooking(context, match),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFCD116),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    "Réserver à partir de ${match.basePrice} F",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesList(List<String> categories) {
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == _selectedCompetition;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(category),
              selected: isSelected,
              selectedColor: const Color(0xFF008751),
              backgroundColor: const Color(0xFF1A2634),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
              ),
              side: BorderSide.none,
              onSelected: (_) =>
                  setState(() => _selectedCompetition = category),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUpcomingMatchesList(
    BuildContext context,
    List<MatchModel> matches,
  ) {
    final featuredMatches = matches.where((match) => match.isHero).toList();
    final featuredId = featuredMatches.isNotEmpty
        ? featuredMatches.first.id
        : (matches.isEmpty ? null : matches.first.id);
    final upcomingMatches = matches
        .where((match) => match.id != featuredId)
        .toList();
    return Column(
      children: upcomingMatches.map((match) {
        return InkWell(
          onTap: () => _navigateToBooking(context, match),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2634),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        match.teams,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "${match.date} • ${match.stadium}${match.city == null || match.city!.isEmpty ? '' : ' · ${match.city}'}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF008751),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "${match.basePrice} F",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMyTicketsBanner(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _selectedIndex = 1),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2634),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFCD116).withValues(alpha: 0.3),
          ),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0xFFFCD116),
              child: Icon(Icons.qr_code, color: Colors.black),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Retrouvez vos billets",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Accédez à vos billets et à leurs QR codes",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}
