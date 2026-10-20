import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/match_model.dart';
import '../../services/yenga_pay_service.dart';

class MatchDetailBookingScreen extends StatefulWidget {
  final MatchModel match;

  const MatchDetailBookingScreen({super.key, required this.match});

  @override
  State<MatchDetailBookingScreen> createState() =>
      _MatchDetailBookingScreenState();
}

class _MatchDetailBookingScreenState extends State<MatchDetailBookingScreen> {
  int _selectedTierIndex = 0;
  final YengaPayService _paymentService = YengaPayService();
  List<Map<String, dynamic>> _tiers = [];

  @override
  void initState() {
    super.initState();
    _loadTicketTiers();
  }

  Future<void> _loadTicketTiers() async {
    try {
      final rows = await Supabase.instance.client
          .from('ticket_catalog')
          .select('category_name, price')
          .eq('match_id', widget.match.id)
          .eq('is_active', true)
          .order('price');
      if (!mounted) return;
      setState(() {
        _tiers = (rows as List).asMap().entries.map((entry) {
          final row = Map<String, dynamic>.from(entry.value);
          return {
            'title': row['category_name'] as String,
            'price': (row['price'] as num).toInt(),
            'color': [
              Colors.grey,
              const Color(0xFF008751),
              const Color(0xFFFCD116),
            ][entry.key % 3],
          };
        }).toList();
        _selectedTierIndex = 0;
      });
    } catch (_) {
      if (mounted) setState(() => _tiers = []);
    }
  }

  // Fonction pour afficher la modale de paiement rapide (façon Fluxa)
  void _showPaymentModal(
    BuildContext context,
    String categoryName,
    double amount,
  ) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A2634),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Détails de la commande",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nom complet',
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.person_outline, color: Colors.grey),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Numéro Mobile Money (+226)',
                labelStyle: TextStyle(color: Colors.grey),
                hintText: '05600291',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.phone_android, color: Colors.grey),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008751),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  if (nameController.text.trim().isEmpty ||
                      phoneController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Veuillez remplir tous les champs'),
                      ),
                    );
                    return;
                  }

                  final enteredPhone = phoneController.text.trim();

                  Navigator.pop(modalContext);
                  await _processYengaPayment(
                    context,
                    nameController.text.trim(),
                    enteredPhone,
                    amount,
                    categoryName,
                  );
                },
                child: const Text(
                  "Payer et Commander",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processYengaPayment(
    BuildContext context,
    String customerName,
    String phoneNumber,
    double amount,
    String categoryName,
  ) async {
    NavigatorState? dialogNavigator;
    final messenger = ScaffoldMessenger.of(context);

    // 1. Afficher un indicateur de chargement en capturant son propre contexte
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogNavigator = Navigator.of(ctx);
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFF008751)),
        );
      },
    );

    try {
      final response = await _paymentService.createCheckout(
        matchId: widget.match.id,
        categoryName: categoryName,
        customerName: customerName,
        phoneNumber: phoneNumber,
      );

      // Fermeture sécurisée du loader via son contexte dédié
      _closeProgressDialog(dialogNavigator);

      if (!mounted) return;

      // Récupération sécurisée des données de la réponse
      final uri = Uri.parse(response.checkoutUrl);
      final trustedYengaHost =
          uri.host == 'yengapay.com' || uri.host.endsWith('.yengapay.com');
      if (uri.scheme != 'https' || !trustedYengaHost) {
        throw StateError('URL de paiement YengaPay invalide.');
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError("Impossible d'ouvrir la page de paiement.");
      } else {
        if (!mounted) return;
        if (!messenger.mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Finalise le paiement dans YengaPay. Le billet apparaîtra après confirmation.',
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Échec de création du paiement : $e\n$stackTrace');

      // Fermer le loader en cas d'erreur de manière sécurisée
      _closeProgressDialog(dialogNavigator);

      if (!mounted) return;

      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _closeProgressDialog(NavigatorState? navigator) {
    if (navigator?.mounted ?? false) {
      navigator!.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tiers.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF101820),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Billets', style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text(
            'Aucune catégorie de billet disponible pour ce match.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
    final selectedPrice =
        _tiers[_selectedTierIndex]["price"] as int;
    final selectedTierTitle = _tiers[_selectedTierIndex]["title"] as String;

    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Sélection des places",
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.match.teams,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "${widget.match.date} • ${widget.match.stadium}${widget.match.city == null || widget.match.city!.isEmpty ? '' : ' · ${widget.match.city}'}",
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            const Text(
              "Choisissez votre tribune :",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(_tiers.length, (index) {
              final tier = _tiers[index];
              final isSelected = _selectedTierIndex == index;
              final price = tier["price"] as int;

              return GestureDetector(
                onTap: () => setState(() => _selectedTierIndex = index),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2634),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? (tier["color"] as Color)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: tier["color"] as Color,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            tier["title"] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "$price FCFA",
                        style: TextStyle(
                          color: tier["color"] as Color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008751),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  _showPaymentModal(
                    context,
                    selectedTierTitle,
                    selectedPrice.toDouble(),
                  );
                },
                child: Text(
                  "Payer $selectedPrice FCFA",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
