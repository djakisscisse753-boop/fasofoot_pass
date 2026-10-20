import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../provider/payment_provider.dart';
import '../../services/yenga_pay_service.dart';

class PaymentScreen extends StatefulWidget {
  final String matchId;
  final String categoryName;

  const PaymentScreen({
    super.key,
    required this.matchId,
    this.categoryName = 'Tribune Populaire',
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final TextEditingController _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _submitPayment(PaymentProvider provider) async {
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.isEmpty) return;

    final success = await provider.initiatePayment(
      matchId: widget.matchId,
      phoneNumber: phoneNumber,
      customerName: 'Client FasoFoot',
      categoryName: widget.categoryName,
    );

    if (!mounted) return;

    if (!success && provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${provider.errorMessage}'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (success && provider.checkoutUrl != null) {
      final uri = Uri.parse(provider.checkoutUrl!);
      if (uri.scheme == 'https' && uri.host.endsWith('.yengapay.com')) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Paiement Billet"),
        leading: Consumer<PaymentProvider>(
          builder: (context, provider, child) {
            if (provider.currentTicketId != null) {
              return IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => provider.resetPayment(),
              );
            }
            return IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            );
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<PaymentProvider>(
          builder: (context, provider, child) {
            return provider.currentTicketId == null
                ? _buildPaymentForm(provider)
                : _buildRealtimeStatusListener(provider.currentTicketId!);
          },
        ),
      ),
    );
  }

  /// Le montant et l'opérateur sont confirmés sur le checkout YengaPay.
  Widget _buildPaymentForm(PaymentProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.categoryName,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: "Numéro Mobile Money",
            hintText: "+22670000000",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Le prix final sera calculé par le serveur.'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: provider.isLoading
                ? null
                : () => _submitPayment(provider),
            child: provider.isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text("Payer le Billet"),
          ),
        ),
      ],
    );
  }

  /// Écouteur en temps réel du statut du ticket
  Widget _buildRealtimeStatusListener(String ticketId) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: YengaPayService().listenToTicketStatus(ticketId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final ticket = snapshot.data!;
        final String status = ticket['status'] ?? 'pending';

        if (status == 'pending') {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text(
                  "Veuillez valider le paiement sur votre téléphone...",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }

        if (status == 'paid') {
          final String qrContent = ticket['qr_token_secret'] ?? '';
          if (qrContent.isEmpty) {
            return const Center(child: Text('QR indisponible pour ce billet.'));
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 64),
                const SizedBox(height: 10),
                const Text(
                  "Paiement Réussi !",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                QrImageView(
                  data: qrContent,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
                const SizedBox(height: 10),
                Text(
                  "Billet ID: $ticketId",
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return const Center(
          child: Text(
            "Le paiement a échoué ou a été annulé.",
            style: TextStyle(color: Colors.red),
          ),
        );
      },
    );
  }
}
