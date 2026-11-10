import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/product_model.dart';
import '../../models/club_model.dart';
import '../../services/marketplace_service.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final MarketplaceService _service = MarketplaceService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  late Future<List<ProductModel>> _productsFuture;
  late Future<List<Club>> _clubsFuture;

  String? _selectedClubId;
  String _searchQuery = '';

  final Map<String, ProductModel> _cartProducts = {};
  final Map<String, int> _cartQuantities = {};
  bool _checkingOut = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _prefillUserInfo();
  }

  void _prefillUserInfo() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final meta = user.userMetadata;
      if (meta != null) {
        final fullName =
            meta['full_name'] as String? ?? meta['name'] as String?;
        if (fullName != null && fullName.isNotEmpty) {
          _nameController.text = fullName;
        }
        final phone = meta['phone'] as String? ?? user.phone;
        if (phone != null && phone.isNotEmpty) {
          _phoneController.text = phone;
        }
      }
    }
  }

  void _refreshAll() {
    setState(() {
      _productsFuture = _service.getProducts(clubId: _selectedClubId);
      _clubsFuture = _service.getAllClubs();
    });
  }

  void _refreshProductsOnly() {
    setState(() {
      _productsFuture = _service.getProducts(clubId: _selectedClubId);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  int get _cartCount =>
      _cartQuantities.values.fold(0, (sum, count) => sum + count);

  int get _cartTotal => _cartQuantities.entries.fold(
    0,
    (sum, entry) =>
        sum + (_cartProducts[entry.key]!.price * entry.value).round(),
  );

  Future<void> _refreshOrderPaymentStatus(String orderId) async {
    try {
      final isPaid = await _service.refreshOrderPaymentStatus(orderId);
      if (!mounted) return;
      if (isPaid) {
        _showMessage(
          'Paiement confirmé par YengaPay. Votre commande est prête.',
        );
        _refreshAll();
        Navigator.pop(context);
        _openOrders();
      } else {
        _showMessage(
          'Paiement en attente de confirmation YengaPay. Réessayez dans quelques instants.',
        );
      }
    } catch (error) {
      debugPrint('Échec de vérification du paiement boutique : $error');
      if (mounted) {
        _showMessage(
          'Vérification impossible. Réessayez dans quelques instants.',
        );
      }
    }
  }

  void _addToCart(ProductModel product, {int quantity = 1}) {
    final currentQty = _cartQuantities[product.id] ?? 0;
    if (product.stock < currentQty + quantity) {
      _showMessage('Stock disponible insuffisant (${product.stock} restants).');
      return;
    }
    setState(() {
      _cartProducts[product.id] = product;
      _cartQuantities.update(
        product.id,
        (val) => val + quantity,
        ifAbsent: () => quantity,
      );
    });
    _showMessage('${product.title} ajouté au panier.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[\s-]'), '');
    final uri = Uri(scheme: 'tel', path: cleanPhone);
    if (!await launchUrl(uri)) {
      _showMessage('Impossible de lancer l’appel vers $phone.');
    }
  }

  Future<void> _openMaps({
    String? mapsUrl,
    String? address,
    String? city,
  }) async {
    Uri? uri;
    if (mapsUrl != null && mapsUrl.trim().isNotEmpty) {
      uri = Uri.tryParse(mapsUrl.trim());
    }
    if (uri == null || !uri.hasScheme) {
      final query = Uri.encodeComponent(
        '${address != null && address.isNotEmpty ? address : 'Guichet'}, ${city ?? 'Ouagadougou'}, Burkina Faso',
      );
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showMessage('Impossible d’ouvrir Google Maps.');
      }
    } catch (_) {
      _showMessage('Impossible d’ouvrir Google Maps.');
    }
  }

  // --- MODALE DU PANIER ---
  Future<void> _openCart() async {
    if (_cartQuantities.isEmpty) {
      _showMessage('Votre panier est vide.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A2634),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) =>
            _buildCartSheet(sheetContext, updateSheet),
      ),
    );
  }

  // --- MODALE DES DÉTAILS D'UN PRODUIT ---
  void _showProductDetail(ProductModel product) {
    int qty = 1;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A2634),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final isOutOfStock = product.stock <= 0;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 220,
                      width: double.infinity,
                      child:
                          product.imageUrl != null &&
                              product.imageUrl!.isNotEmpty
                          ? Image.network(
                              product.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _imagePlaceholder(height: 220),
                            )
                          : _imagePlaceholder(height: 220),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Club & Prix
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (product.clubName != null)
                        Row(
                          children: [
                            if (product.clubLogoUrl != null &&
                                product.clubLogoUrl!.isNotEmpty)
                              CircleAvatar(
                                radius: 14,
                                backgroundImage: NetworkImage(
                                  product.clubLogoUrl!,
                                ),
                              ),
                            const SizedBox(width: 8),
                            Text(
                              product.clubName!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        )
                      else
                        const SizedBox(),
                      Text(
                        '${product.price.toStringAsFixed(0)} FCFA',
                        style: const TextStyle(
                          color: Color(0xFFFCD116),
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    product.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  if (product.description != null &&
                      product.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      product.description!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Bloc Point de retrait & Responsable
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF223142),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.storefront,
                              color: Color(0xFF008751),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Point de retrait officiel',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (product.headquartersAddress != null &&
                            product.headquartersAddress!.isNotEmpty)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 15,
                                color: Color(0xFFFCD116),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${product.headquartersAddress} (${product.clubCity ?? 'Burkina Faso'})',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (product.managerName != null &&
                            product.managerName!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.person_pin,
                                size: 15,
                                color: Colors.white38,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Responsable : ${product.managerName}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        const Text(
                          'ℹ️ Après paiement, vous aurez un bouton 1-clic pour appeler le responsable et lancer l\'itinéraire GPS.',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Sélecteur de quantité & Boutons d'achat
                  if (!isOutOfStock) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Quantité :',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: qty > 1
                                  ? () => setModalState(() => qty--)
                                  : null,
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.white70,
                              ),
                            ),
                            Text(
                              '$qty',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            IconButton(
                              onPressed: qty < product.stock
                                  ? () => setModalState(() => qty++)
                                  : null,
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: Color(0xFF008751),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF008751)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              if (sheetContext.mounted)
                                Navigator.pop(sheetContext);
                              _addToCart(product, quantity: qty);
                            },
                            icon: const Icon(
                              Icons.add_shopping_cart,
                              color: Color(0xFF008751),
                              size: 18,
                            ),
                            label: const Text(
                              'Au panier',
                              style: TextStyle(
                                color: Color(0xFF008751),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF008751),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              if (sheetContext.mounted)
                                Navigator.pop(sheetContext);
                              _addToCart(product, quantity: qty);
                              _openCart();
                            },
                            icon: const Icon(
                              Icons.flash_on,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: const Text(
                              'Acheter direct',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Article en rupture de stock',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- MODALE DES COMMANDES / ACHATS EFFECTUÉS ---
  Future<void> _openOrders() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      _showMessage('Connectez-vous pour consulter vos achats.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101820),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.85,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.receipt_long,
                      color: Color(0xFF008751),
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Mes Achats & Retraits',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              // Liste des commandes
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _service.getMyOrders(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF008751),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Erreur : ${snapshot.error}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    final orders = snapshot.data ?? [];
                    if (orders.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shopping_bag_outlined,
                              size: 56,
                              color: Colors.white24,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Vous n’avez aucun achat pour le moment.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: orders.length,
                      itemBuilder: (context, index) =>
                          _buildOrderReceiptCard(orders[index]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- CARTE D'UN ACHAT / REÇU DE RETRAIT ---
  Widget _buildOrderReceiptCard(Map<String, dynamic> order) {
    final status = order['status']?.toString();
    final paymentTransactionId = order['provider_transaction_id'] as String?;
    final isPaymentVerified =
        paymentTransactionId != null &&
        paymentTransactionId.isNotEmpty &&
        !paymentTransactionId.startsWith('MANUAL-');
    final isPaid = status == 'paid' && isPaymentVerified;
    final isPending = status == 'pending';
    final needsPaymentReview = status == 'paid' && !isPaymentVerified;
    final items = (order['marketplace_order_items'] as List? ?? const [])
        .cast<Map<String, dynamic>>();

    final pickupCode = isPaid ? order['pickup_code'] as String? : null;
    final created = DateTime.tryParse(
      order['created_at']?.toString() ?? '',
    )?.toLocal();
    final dateStr = created != null
        ? '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year} à ${created.hour.toString().padLeft(2, '0')}h${created.minute.toString().padLeft(2, '0')}'
        : '';

    Color badgeColor;
    String badgeText;
    if (isPaid) {
      badgeColor = const Color(0xFF008751);
      badgeText = 'PAYÉ · PRÊT AU RETRAIT';
    } else if (needsPaymentReview) {
      badgeColor = Colors.orangeAccent;
      badgeText = 'PAIEMENT À VÉRIFIER';
    } else if (isPending) {
      badgeColor = const Color(0xFFFCD116);
      badgeText = 'EN ATTENTE DE PAIEMENT';
    } else {
      badgeColor = Colors.redAccent;
      badgeText = _orderStatus(status).toUpperCase();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPaid ? const Color(0xFF008751) : Colors.white12,
          width: isPaid ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // En-tête du reçu
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isPaid ? const Color(0xFF008751) : const Color(0xFF223142),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (pickupCode != null)
                  Row(
                    children: [
                      const Icon(Icons.qr_code, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        pickupCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  )
                else
                  const Text(
                    'Commande',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: isPending ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date & Montant
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateStr,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${order['total_amount']} FCFA',
                      style: const TextStyle(
                        color: Color(0xFFFCD116),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),

                if (order['customer_name'] != null &&
                    (order['customer_name'] as String).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '👤 Client : ${order['customer_name']}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],

                const Divider(color: Colors.white12, height: 24),

                // Articles achetés
                ...items.map((item) {
                  final phone = item['marketing_phone'] as String?;
                  final address = item['headquarters_address'] as String?;
                  final managerName = item['manager_name'] as String?;
                  final mapsUrl = item['maps_url'] as String?;
                  final city = item['club_city'] as String?;
                  final fulfillment = item['fulfillment_status']?.toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF223142),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${item['product_title']} × ${item['quantity']}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: fulfillment == 'completed'
                                    ? Colors.blueGrey
                                    : const Color(
                                        0xFF008751,
                                      ).withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                fulfillment == 'completed'
                                    ? 'Article remis'
                                    : 'À récupérer',
                                style: TextStyle(
                                  color: fulfillment == 'completed'
                                      ? Colors.white70
                                      : const Color(0xFF00D179),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item['club_name']} · ${city ?? 'Burkina Faso'}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),

                        // Adresse de retrait
                        if (address != null && address.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 15,
                                color: Color(0xFFFCD116),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  'Guichet de retrait : $address',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Nom du responsable
                        if (managerName != null && managerName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                                size: 15,
                                color: Colors.white38,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Responsable : $managerName',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],

                        // LES DEUX BOUTONS CLÉS : APPEL DU RESPONSABLE & ITINÉRAIRE GOOGLE MAPS
                        if (isPaid) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // Bouton 1 : Appeler le responsable
                              if (phone != null && phone.isNotEmpty)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF008751),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                    ),
                                    onPressed: () => _callPhone(phone),
                                    icon: const Icon(
                                      Icons.phone,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    label: const Text(
                                      'Appeler le club',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              if (phone != null && phone.isNotEmpty)
                                const SizedBox(width: 8),
                              // Bouton 2 : Itinéraire Google Maps
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E3A5F),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                  onPressed: () => _openMaps(
                                    mapsUrl: mapsUrl,
                                    address: address,
                                    city: city,
                                  ),
                                  icon: const Icon(
                                    Icons.directions,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Itinéraire Maps',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }),

                if (isPaid && pickupCode != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131D27),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Color(0xFFFCD116),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Présentez votre code $pickupCode au guichet pour retirer vos articles.',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (needsPaymentReview)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                              'Nous vérifions cette commande avec le prestataire de paiement avant de confirmer son retrait.',
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (isPaid && pickupCode == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                              'Paiement confirmé, mais code de retrait indisponible. Contactez le support avant de vous déplacer.',
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (isPending) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFCD116),
                        side: const BorderSide(color: Color(0xFFFCD116)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        _showMessage('Vérification du paiement en cours...');
                        await _refreshOrderPaymentStatus(order['id'] as String);
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text(
                        'J\'ai payé · Actualiser le paiement',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- PANIER ET PASSATION DE COMMANDE ---
  Widget _buildCartSheet(BuildContext sheetContext, StateSetter updateSheet) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Mon Panier FasoFoot',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._cartQuantities.entries.map((entry) {
                final product = _cartProducts[entry.key]!;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    product.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${product.price.toStringAsFixed(0)} FCFA / unité',
                    style: const TextStyle(color: Colors.white60),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            if (entry.value <= 1) {
                              _cartQuantities.remove(entry.key);
                              _cartProducts.remove(entry.key);
                            } else {
                              _cartQuantities[entry.key] = entry.value - 1;
                            }
                          });
                          updateSheet(() {});
                        },
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: entry.value >= product.stock
                            ? null
                            : () {
                                setState(
                                  () => _cartQuantities[entry.key] =
                                      entry.value + 1,
                                );
                                updateSheet(() {});
                              },
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: Color(0xFF008751),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(color: Colors.white24, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total à régler :',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  Text(
                    '$_cartTotal FCFA',
                    style: const TextStyle(
                      color: Color(0xFFFCD116),
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Saisie du nom & prénom
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nom et Prénom du client',
                  hintText: 'Ex: Amadou Traoré',
                  prefixIcon: const Icon(
                    Icons.person,
                    color: Colors.white54,
                    size: 20,
                  ),
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF008751)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              // Saisie du téléphone de paiement
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Numéro de téléphone de paiement',
                  hintText: '+226 70 00 00 00',
                  prefixIcon: const Icon(
                    Icons.phone,
                    color: Colors.white54,
                    size: 20,
                  ),
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF008751)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _checkingOut || _cartQuantities.isEmpty
                      ? null
                      : () => _checkout(sheetContext),
                  icon: _checkingOut
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.lock_outline),
                  label: Text(
                    _checkingOut
                        ? 'Préparation YengaPay…'
                        : 'Valider et Payer avec YengaPay',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF008751),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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

  Future<void> _checkout(BuildContext sheetContext) async {
    if (Supabase.instance.client.auth.currentUser == null) {
      _showMessage('Connectez-vous pour passer votre commande.');
      return;
    }
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showMessage('Veuillez saisir votre numéro de téléphone.');
      return;
    }
    final name = _nameController.text.trim();

    setState(() => _checkingOut = true);
    try {
      final checkoutResult = await _service.startCheckout(
        phoneNumber: phone,
        customerName: name.isNotEmpty ? name : null,
        items: _cartQuantities.entries
            .map((entry) => {'product_id': entry.key, 'quantity': entry.value})
            .toList(),
      );

      final checkoutUrl = checkoutResult['checkout_url'] as String;
      final uri = Uri.tryParse(checkoutUrl);
      if (uri == null ||
          uri.scheme != 'https' ||
          !(uri.host == 'yengapay.com' || uri.host.endsWith('.yengapay.com'))) {
        throw StateError('Lien de paiement YengaPay invalide.');
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Impossible d’ouvrir la page de paiement.');
      }
      if (!mounted) return;

      setState(() {
        _cartProducts.clear();
        _cartQuantities.clear();
      });
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      _showMessage(
        'Commande créée avec succès ! Retrouvez votre reçu dans "Mes Achats".',
      );
      _refreshProductsOnly();
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  String _orderStatus(String? status) => switch (status) {
    'paid' => 'Payée',
    'pending' => 'En attente',
    'failed' => 'Échec',
    'cancelled' => 'Annulée',
    'expired' => 'Expirée',
    'refund_required' => 'Remboursement requis',
    _ => 'Statut inconnu',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        title: const Text(
          'Boutique Officielle',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _openOrders,
            tooltip: 'Mes achats & retraits',
            icon: const Icon(Icons.receipt_long, color: Colors.white),
          ),
          IconButton(
            onPressed: _openCart,
            tooltip: 'Panier',
            icon: Badge(
              isLabelVisible: _cartCount > 0,
              label: Text('$_cartCount'),
              backgroundColor: const Color(0xFF008751),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) =>
                  setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Rechercher un maillot, écharpe, ballon...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.white54,
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          color: Colors.white38,
                          size: 18,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1A2634),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),

          // Barre de filtrage par club
          SizedBox(
            height: 48,
            child: FutureBuilder<List<Club>>(
              future: _clubsFuture,
              builder: (context, snapshot) {
                final clubs = snapshot.data ?? [];
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _clubChip(
                      id: null,
                      label: 'Tous les clubs',
                      isSelected: _selectedClubId == null,
                    ),
                    for (final club in clubs)
                      _clubChip(
                        id: club.id,
                        label: club.shortName.isNotEmpty
                            ? club.shortName
                            : club.name,
                        logoUrl: club.logoUrl,
                        isSelected: _selectedClubId == club.id,
                      ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Grille des articles
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refreshAll(),
              color: const Color(0xFF008751),
              child: FutureBuilder<List<ProductModel>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF008751),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_off,
                              color: Colors.white38,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Impossible de charger la boutique.\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _refreshProductsOnly,
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  var products = snapshot.data ?? [];

                  // Filtrage local par recherche textuelle
                  if (_searchQuery.isNotEmpty) {
                    products = products.where((p) {
                      final matchTitle = p.title.toLowerCase().contains(
                        _searchQuery,
                      );
                      final matchClub =
                          p.clubName?.toLowerCase().contains(_searchQuery) ??
                          false;
                      final matchDesc =
                          p.description?.toLowerCase().contains(_searchQuery) ??
                          false;
                      return matchTitle || matchClub || matchDesc;
                    }).toList();
                  }

                  if (products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.shopping_bag_outlined,
                            color: Colors.white24,
                            size: 56,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Aucun article ne correspond à votre recherche.'
                                : 'Aucun article disponible pour ce club actuellement.',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 14,
                        ),
                    itemCount: products.length,
                    itemBuilder: (context, index) =>
                        _productCard(products[index]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clubChip({
    required String? id,
    required String label,
    String? logoUrl,
    required bool isSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        avatar: logoUrl != null && logoUrl.isNotEmpty
            ? CircleAvatar(backgroundImage: NetworkImage(logoUrl))
            : null,
        label: Text(label),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        backgroundColor: const Color(0xFF1A2634),
        selectedColor: const Color(0xFF008751),
        checkmarkColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? const Color(0xFF008751) : Colors.white12,
          ),
        ),
        onSelected: (_) {
          setState(() {
            _selectedClubId = id;
            _refreshProductsOnly();
          });
        },
      ),
    );
  }

  Widget _productCard(ProductModel product) {
    final quantity = _cartQuantities[product.id] ?? 0;
    final outOfStock = product.stock <= quantity;

    return GestureDetector(
      onTap: () => _showProductDetail(product),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A2634),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image du produit avec badge club
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.imageUrl != null && product.imageUrl!.isNotEmpty
                      ? Image.network(
                          product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                  if (product.clubLogoUrl != null &&
                      product.clubLogoUrl!.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF1A2634),
                        backgroundImage: NetworkImage(product.clubLogoUrl!),
                      ),
                    ),
                  if (product.stock <= 3)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: product.stock == 0
                              ? Colors.red
                              : Colors.orange,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          product.stock == 0
                              ? 'Épuisé'
                              : 'Plus que ${product.stock}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Détails sous l'image
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.clubName ?? 'Club partenaire',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '${product.price.toStringAsFixed(0)} F',
                          style: const TextStyle(
                            color: Color(0xFFFCD116),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton.filled(
                        visualDensity: VisualDensity.compact,
                        onPressed: outOfStock
                            ? null
                            : () => _addToCart(product),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF008751),
                          disabledBackgroundColor: Colors.white12,
                        ),
                        icon: Icon(
                          outOfStock ? Icons.check : Icons.add_shopping_cart,
                          size: 16,
                          color: Colors.white,
                        ),
                        tooltip: outOfStock ? 'Épuisé' : 'Ajouter',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder({double? height}) => Container(
    height: height,
    color: const Color(0xFF223142),
    child: const Center(
      child: Icon(
        Icons.shopping_bag_outlined,
        size: 40,
        color: Color(0xFF008751),
      ),
    ),
  );
}
