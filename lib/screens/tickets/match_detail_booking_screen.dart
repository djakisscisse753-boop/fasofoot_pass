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
  bool _isLoadingTiers = true;
  String? _tiersError;

  @override
  void initState() {
    super.initState();
    _loadTicketTiers();
  }

  Future<void> _loadTicketTiers() async {
    List<dynamic> rows = [];
    String? loadError;
    try {
      // 1. Tenter la requête complète avec les colonnes de capacité
      rows = await Supabase.instance.client
          .from('ticket_catalog')
          .select(
            'category_name, price, total_capacity, tickets_sold, is_active',
          )
          .eq('match_id', widget.match.id)
          .order('price');
    } catch (_) {
      try {
        // 2. Fallback si total_capacity/tickets_sold ne sont pas encore créées en base
        rows = await Supabase.instance.client
            .from('ticket_catalog')
            .select('category_name, price, is_active')
            .eq('match_id', widget.match.id)
            .order('price');
      } catch (error) {
        debugPrint('Échec du chargement des catégories de billets : $error');
        loadError = 'Vérifiez votre connexion puis réessayez.';
      }
    }

    if (!mounted) return;

    final colors = [
      const Color(0xFF008751), // Vert Faso
      const Color(0xFFFCD116), // Jaune Faso
      const Color(0xFF29B6F6), // Bleu
      const Color(0xFFAB47BC), // Violet
    ];

    final mappedTiers = rows.asMap().entries.map((entry) {
      final row = Map<String, dynamic>.from(entry.value as Map);
      final totalCap = (row['total_capacity'] as num?)?.toInt() ?? 100;
      final sold = (row['tickets_sold'] as num?)?.toInt() ?? 0;
      final remaining = (totalCap - sold).clamp(0, totalCap);
      final isSoldOut = remaining <= 0 || row['is_active'] == false;

      return {
        'title': row['category_name'] as String,
        'price': (row['price'] as num).toInt(),
        'totalCapacity': totalCap,
        'remaining': remaining,
        'isSoldOut': isSoldOut,
        'color': colors[entry.key % colors.length],
      };
    }).toList();

    int firstAvailableIndex = mappedTiers.indexWhere(
      (t) => t['isSoldOut'] == false,
    );
    if (firstAvailableIndex == -1) firstAvailableIndex = 0;

    setState(() {
      _tiers = mappedTiers;
      _selectedTierIndex = firstAvailableIndex;
      _tiersError = loadError;
      _isLoadingTiers = false;
    });
  }

  // Modale de paiement Mobile Money avec pré-remplissage et validation
  void _showPaymentModal(
    BuildContext context,
    String categoryName,
    int amount,
  ) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser?.userMetadata?['full_name'] != null) {
      nameController.text = currentUser!.userMetadata!['full_name'] as String;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14212B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 16,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                "Finaliser votre réservation",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              // Récapitulatif
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2E3C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          categoryName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.match.teams,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      "$amount FCFA",
                      style: const TextStyle(
                        color: Color(0xFFFCD116),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration(
                  label: 'Nom complet du supporter',
                  icon: Icons.person_outline,
                ),
                validator: (value) => (value == null || value.trim().length < 2)
                    ? 'Veuillez saisir votre nom complet.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  label: 'Numéro Mobile Money (Orange, Moov, Telecel)',
                  icon: Icons.phone_android,
                  hintText: 'Ex: 70 00 00 00',
                ),
                validator: (value) {
                  final clean =
                      value?.trim().replaceAll(RegExp(r'[\s\-]'), '') ?? '';
                  if (!RegExp(r'^(?:\+?226)?[0-9]{8}$').hasMatch(clean)) {
                    return 'Saisissez un numéro burkinabè valide (8 chiffres).';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF008751),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    final cleanPhone = phoneController.text.trim().replaceAll(
                      RegExp(r'[\s\-]'),
                      '',
                    );
                    final cleanName = nameController.text.trim();

                    Navigator.pop(modalContext);
                    await _processYengaPayment(
                      context,
                      cleanName,
                      cleanPhone,
                      amount.toDouble(),
                      categoryName,
                    );
                  },
                  child: Text(
                    "Payer $amount FCFA via YengaPay",
                    style: const TextStyle(
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
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hintText,
  }) => InputDecoration(
    labelText: label,
    hintText: hintText,
    hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
    labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
    prefixIcon: Icon(icon, color: Colors.white60, size: 20),
    filled: true,
    fillColor: const Color(0xFF1E2E3C),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.white12),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFFCD116), width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
    ),
  );

  Future<void> _processYengaPayment(
    BuildContext context,
    String customerName,
    String phoneNumber,
    double amount,
    String categoryName,
  ) async {
    NavigatorState? dialogNavigator;
    final messenger = ScaffoldMessenger.of(context);

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

      _closeProgressDialog(dialogNavigator);
      if (!mounted) return;

      final uri = Uri.parse(response.checkoutUrl);
      final trustedYengaHost =
          uri.host == 'yengapay.com' || uri.host.endsWith('.yengapay.com');
      if (uri.scheme != 'https' || !trustedYengaHost) {
        throw StateError('URL de paiement YengaPay invalide.');
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError("Impossible d'ouvrir la page de paiement.");
      } else {
        if (!mounted || !messenger.mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Finalisez le paiement dans YengaPay. Retrouvez votre billet dans "Mes Billets" après confirmation.',
            ),
            duration: Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Échec de création du paiement : $e\n$stackTrace');
      _closeProgressDialog(dialogNavigator);
      if (!mounted || !messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
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
    if (_isLoadingTiers) {
      return Scaffold(
        backgroundColor: const Color(0xFF101820),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Billetterie',
            style: TextStyle(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF008751)),
        ),
      );
    }

    if (_tiers.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF101820),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Billets', style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.confirmation_number_outlined,
                  size: 64,
                  color: Colors.white24,
                ),
                const SizedBox(height: 16),
                Text(
                  _tiersError == null
                      ? 'Aucune catégorie de billets n’est configurée pour ce match.'
                      : 'Impossible de charger les catégories de billets.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                if (_tiersError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _tiersError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      setState(() => _isLoadingTiers = true);
                      _loadTicketTiers();
                    },
                    child: const Text('Réessayer'),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  child: const Text('Retour aux matchs'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bool allSoldOut = _tiers.every((t) => t['isSoldOut'] == true);
    final selectedTier = _tiers.isNotEmpty ? _tiers[_selectedTierIndex] : null;
    final selectedPrice = selectedTier?["price"] as int? ?? 0;
    final selectedTierTitle = selectedTier?["title"] as String? ?? '';
    final bool isSelectedTierSoldOut = selectedTier?['isSoldOut'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Sélection des places",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
            // Carte du match
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2634),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.match.teams,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Color(0xFFFCD116),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.match.date,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Color(0xFFFCD116),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.match.city == null || widget.match.city!.isEmpty
                            ? widget.match.stadium
                            : '${widget.match.stadium} · ${widget.match.city}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Bandeau d'alerte si guichet fermé
            if (allSoldOut)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.6),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Guichet fermé : Toutes les places pour ce match sont épuisées.",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              "Catégories et places disponibles :",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.builder(
                itemCount: _tiers.length,
                itemBuilder: (context, index) {
                  final tier = _tiers[index];
                  final isSelected = _selectedTierIndex == index;
                  final price = tier["price"] as int;
                  final color = tier["color"] as Color;
                  final int remaining = tier["remaining"] as int? ?? 0;
                  final bool isSoldOut = tier["isSoldOut"] == true;

                  return GestureDetector(
                    onTap: () {
                      if (isSoldOut) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "La ${tier['title']} est déjà complète.",
                            ),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      setState(() => _selectedTierIndex = index);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSoldOut
                            ? const Color(0xFF151E28).withValues(alpha: 0.6)
                            : isSelected
                            ? color.withValues(alpha: 0.15)
                            : const Color(0xFF1A2634),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSoldOut
                              ? Colors.white10
                              : isSelected
                              ? color
                              : Colors.white12,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isSoldOut
                                    ? Icons.block
                                    : isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: isSoldOut
                                    ? Colors.white24
                                    : isSelected
                                    ? color
                                    : Colors.white38,
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tier["title"] as String,
                                    style: TextStyle(
                                      color: isSoldOut
                                          ? Colors.white38
                                          : Colors.white,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (isSoldOut)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        "COMPLET",
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    )
                                  else if (remaining <= 15)
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.local_fire_department,
                                          color: Colors.orangeAccent,
                                          size: 13,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "Plus que $remaining places !",
                                          style: const TextStyle(
                                            color: Colors.orangeAccent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      "$remaining places disponibles",
                                      style: const TextStyle(
                                        color: Color(0xFF7ED6A5),
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            "$price FCFA",
                            style: TextStyle(
                              color: isSoldOut
                                  ? Colors.white24
                                  : isSelected
                                  ? color
                                  : const Color(0xFFFCD116),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: allSoldOut || isSelectedTierSoldOut
                      ? Colors.grey.shade800
                      : const Color(0xFF008751),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: (allSoldOut || isSelectedTierSoldOut)
                    ? null
                    : () {
                        _showPaymentModal(
                          context,
                          selectedTierTitle,
                          selectedPrice,
                        );
                      },
                child: Text(
                  allSoldOut
                      ? "Guichet fermé - Match complet"
                      : isSelectedTierSoldOut
                      ? "Tribune complète"
                      : "Payer $selectedPrice FCFA",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: allSoldOut || isSelectedTierSoldOut
                        ? Colors.white38
                        : Colors.white,
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
