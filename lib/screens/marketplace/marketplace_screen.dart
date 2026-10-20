import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/product_model.dart';
import '../../services/marketplace_service.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final MarketplaceService _service = MarketplaceService();
  final TextEditingController _phoneController = TextEditingController();
  late Future<List<ProductModel>> _productsFuture;
  final Map<String, ProductModel> _cartProducts = {};
  final Map<String, int> _cartQuantities = {};
  bool _checkingOut = false;

  @override
  void initState() {
    super.initState();
    _productsFuture = _service.getProducts();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  int get _cartCount =>
      _cartQuantities.values.fold(0, (sum, count) => sum + count);

  int get _cartTotal => _cartQuantities.entries.fold(
    0,
    (sum, entry) =>
        sum + (_cartProducts[entry.key]!.price * entry.value).round(),
  );

  void _refreshProducts() {
    setState(() => _productsFuture = _service.getProducts());
  }

  void _addToCart(ProductModel product) {
    if (product.stock <= (_cartQuantities[product.id] ?? 0)) {
      _showMessage('Stock disponible insuffisant.');
      return;
    }
    setState(() {
      _cartProducts[product.id] = product;
      _cartQuantities.update(
        product.id,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    });
    _showMessage('${product.title} ajouté au panier.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCart() async {
    if (_cartQuantities.isEmpty) {
      _showMessage('Votre panier est vide.');
      return;
    }
    _phoneController.clear();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A2634),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) =>
            _buildCart(sheetContext, updateSheet),
      ),
    );
  }

  Future<void> _openOrders() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      _showMessage('Connectez-vous pour consulter vos commandes.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A2634),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Mes commandes',
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
                      return const Center(
                        child: Text(
                          'Impossible de charger vos commandes.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    final orders = snapshot.data ?? [];
                    if (orders.isEmpty) {
                      return const Center(
                        child: Text(
                          'Vous n’avez pas encore passé de commande.',
                          style: TextStyle(color: Colors.white60),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: orders.length,
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        final items =
                            (order['marketplace_order_items'] as List? ??
                            const []);
                        final created = DateTime.tryParse(
                          order['created_at']?.toString() ?? '',
                        )?.toLocal();
                        return Card(
                          color: const Color(0xFF223142),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${created == null ? '' : '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year} · '}${_orderStatus(order['status']?.toString())}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${order['total_amount']} F CFA',
                                      style: const TextStyle(
                                        color: Color(0xFFFCD116),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                for (final item in items)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${item['product_title']} × ${item['quantity']}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${item['club_name']} · ${item['club_city'] ?? 'Burkina Faso'} · ${_handoffStatus(item['fulfillment_status']?.toString())}',
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if ((item['headquarters_address']
                                                    as String?)
                                                ?.isNotEmpty ==
                                            true)
                                          Text(
                                            'Retrait au siège : ${item['headquarters_address']}',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        if ((item['marketing_phone'] as String?)
                                                ?.isNotEmpty ==
                                            true)
                                          TextButton.icon(
                                            onPressed: () => _callClub(
                                              item['marketing_phone'] as String,
                                            ),
                                            icon: const Icon(
                                              Icons.call,
                                              size: 16,
                                            ),
                                            label: Text(
                                              'Appeler le responsable marketing : ${item['marketing_phone']}',
                                            ),
                                          )
                                        else
                                          const Text(
                                            'Le club n’a pas encore renseigné son numéro marketing. Contactez son siège.',
                                            style: TextStyle(
                                              color: Colors.orangeAccent,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
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

  String _orderStatus(String? status) => switch (status) {
    'paid' => 'Payée',
    'pending' => 'En attente de paiement',
    'failed' => 'Échec du paiement',
    'cancelled' => 'Annulée',
    'expired' => 'Réservation expirée',
    'refund_required' => 'Paiement reçu, remboursement à traiter',
    _ => 'Statut inconnu',
  };

  String _handoffStatus(String? status) => switch (status) {
    'contacted' => 'Club contacté',
    'pickup_agreed' => 'Retrait convenu',
    'completed' => 'Article remis',
    'cancelled' => 'Remise annulée',
    _ => 'À organiser avec le club',
  };

  Future<void> _callClub(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) _showMessage('Impossible de lancer l’appel.');
  }

  Widget _buildCart(BuildContext sheetContext, StateSetter updateSheet) {
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
                      'Mon panier',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
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
              ..._cartQuantities.entries.map((entry) {
                final product = _cartProducts[entry.key]!;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    product.title,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${product.price.toStringAsFixed(0)} F CFA / unité',
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
                        style: const TextStyle(color: Colors.white),
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
              const Divider(color: Colors.white24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(color: Colors.white70)),
                  Text(
                    '$_cartTotal F CFA',
                    style: const TextStyle(
                      color: Color(0xFFFCD116),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Téléphone de paiement',
                  hintText: '+226 70 00 00 00',
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
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _checkingOut || _cartQuantities.isEmpty
                      ? null
                      : () => _checkout(_phoneController.text, sheetContext),
                  icon: _checkingOut
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline),
                  label: Text(
                    _checkingOut ? 'Préparation…' : 'Payer avec YengaPay',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF008751),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkout(String phone, BuildContext sheetContext) async {
    if (Supabase.instance.client.auth.currentUser == null) {
      _showMessage('Connectez-vous pour passer une commande.');
      return;
    }
    setState(() => _checkingOut = true);
    try {
      final checkoutUrl = await _service.startCheckout(
        phoneNumber: phone.trim(),
        items: _cartQuantities.entries
            .map((entry) => {'product_id': entry.key, 'quantity': entry.value})
            .toList(),
      );
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
      Navigator.pop(context);
      _showMessage('Commande créée. Elle sera confirmée après le paiement.');
      _refreshProducts();
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        title: const Text(
          'Boutique officielle',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _openOrders,
            tooltip: 'Mes commandes',
            icon: const Icon(Icons.receipt_long_outlined, color: Colors.white),
          ),
          IconButton(
            onPressed: _openCart,
            tooltip: 'Panier',
            icon: Badge(
              isLabelVisible: _cartCount > 0,
              label: Text('$_cartCount'),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<ProductModel>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF008751)),
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
                      color: Colors.white54,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Impossible de charger la boutique. ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: _refreshProducts,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }
          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return const Center(
              child: Text(
                'Aucun article disponible pour le moment.',
                style: TextStyle(color: Colors.white60),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.70,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) => _productCard(products[index]),
          );
        },
      ),
    );
  }

  Widget _productCard(ProductModel product) {
    final quantity = _cartQuantities[product.id] ?? 0;
    final outOfStock = product.stock <= quantity;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
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
                      top: 10,
                      left: 10,
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFF1A2634),
                        backgroundImage: NetworkImage(product.clubLogoUrl!),
                        onBackgroundImageError: (_, _) {},
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
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
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.description ?? 'Produit officiel du club',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 8),
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
                      onPressed: outOfStock ? null : () => _addToCart(product),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF008751),
                        disabledBackgroundColor: Colors.white12,
                      ),
                      icon: Icon(
                        outOfStock ? Icons.check : Icons.add,
                        size: 18,
                      ),
                      tooltip: outOfStock
                          ? 'Rupture de stock'
                          : 'Ajouter au panier',
                    ),
                  ],
                ),
                if (product.stock <= 3)
                  Text(
                    product.stock == 0
                        ? 'Rupture de stock'
                        : 'Plus que ${product.stock} en stock',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() => const ColoredBox(
    color: Color(0xFF223142),
    child: Center(
      child: Icon(
        Icons.shopping_bag_outlined,
        size: 48,
        color: Color(0xFF008751),
      ),
    ),
  );
}
