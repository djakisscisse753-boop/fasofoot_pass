import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/ticket_service.dart';
import '../../models/ticket_model.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final TicketService _ticketService = TicketService();
  bool _isProcessing = false;
  MobileScannerController cameraController = MobileScannerController();

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? qrSecret = barcodes.first.rawValue;
    if (qrSecret == null || qrSecret.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    // Traitement du scan via le TicketService
    final result = await _ticketService.scanAndValidateTicket(qrSecret);

    if (!mounted) return;

    // Pause la caméra pendant l'affichage de la boîte de dialogue
    cameraController.stop();

    _showResultDialog(
      success: result['success'] ?? false,
      message: result['message'] ?? '',
      ticket: result['ticket'] as TicketModel?,
    );
  }

  void _showResultDialog({
    required bool success,
    required String message,
    TicketModel? ticket,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A2634),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? const Color(0xFF008751) : Colors.red,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              success ? "Billet Valide" : "Billet Invalide",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(
                color: success ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (ticket != null) ...[
              const Divider(color: Colors.white24, height: 24),
              Text(
                "Catégorie : ${ticket.categoryName}",
                style: const TextStyle(color: Colors.white70),
              ),
              if (ticket.gate != null)
                Text(
                  "Porte : ${ticket.gate}",
                  style: const TextStyle(color: Colors.white70),
                ),
              if (ticket.seatNumber != null)
                Text(
                  "Siège : ${ticket.seatNumber}",
                  style: const TextStyle(color: Colors.white70),
                ),
              Text(
                "Prix : ${ticket.price.toStringAsFixed(0)} FCFA",
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: success ? const Color(0xFF008751) : Colors.red,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _isProcessing = false;
              });
              cameraController.start();
            },
            child: const Text(
              "Scanner le suivant",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        title: const Text(
          "Contrôle des Billets FBF",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: cameraController,
              builder: (context, state, child) {
                final torchState = state.torchState;
                return Icon(
                  torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                  color: Colors.white,
                );
              },
            ),
            onPressed: () => cameraController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: cameraController, onDetect: _onDetect),
          // Cadre de visée
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isProcessing
                      ? Colors.orange
                      : const Color(0xFFFCD116),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Placez le QR Code du billet dans le cadre pour effectuer la vérification.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
