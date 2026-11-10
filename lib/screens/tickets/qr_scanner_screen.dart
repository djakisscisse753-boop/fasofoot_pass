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

    // Pause la caméra pendant le traitement
    cameraController.stop();

    // Traitement du scan via le TicketService
    final result = await _ticketService.scanAndValidateTicket(qrSecret);

    if (!mounted) return;

    _showResultDialog(
      success: result['success'] == true,
      reason: result['reason'] as String?,
      message: result['message'] ?? '',
      ticket: result['ticket'] as TicketModel?,
    );
  }

  void _showResultDialog({
    required bool success,
    String? reason,
    required String message,
    TicketModel? ticket,
  }) {
    final bool isAlreadyUsed = reason == 'used';

    Color headerColor;
    IconData headerIcon;
    String headerTitle;

    if (success) {
      headerColor = const Color(0xFF008751); // Vert FasoFoot
      headerIcon = Icons.check_circle_rounded;
      headerTitle = "Billet Valide";
    } else if (isAlreadyUsed) {
      headerColor = Colors.red.shade800;
      headerIcon = Icons.warning_rounded;
      headerTitle = "Billet Déjà Utilisé !";
    } else {
      headerColor = Colors.redAccent.shade700;
      headerIcon = Icons.cancel_rounded;
      headerTitle = "Billet Invalide";
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A2634),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête coloré
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Icon(headerIcon, color: Colors.white, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    headerTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            // Détails du billet
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Message principal
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: headerColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: headerColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: success ? const Color(0xFF00D179) : Colors.redAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  if (ticket != null) ...[
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 12),

                    // Tribune
                    _dialogDetailRow(
                      icon: Icons.confirmation_number_outlined,
                      label: "Tribune",
                      value: ticket.categoryName,
                      valueColor: Colors.white,
                    ),

                    // Nom du propriétaire
                    if (ticket.customerName != null && ticket.customerName!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _dialogDetailRow(
                        icon: Icons.person_outline,
                        label: "Détenteur",
                        value: ticket.customerName!,
                        valueColor: const Color(0xFFFCD116),
                      ),
                    ],

                    // Téléphone
                    if (ticket.customerPhone != null && ticket.customerPhone!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _dialogDetailRow(
                        icon: Icons.phone_outlined,
                        label: "Téléphone",
                        value: ticket.customerPhone!,
                        valueColor: Colors.white70,
                      ),
                    ],

                    // Porte / Siège
                    if (ticket.gate != null || ticket.seatNumber != null) ...[
                      const SizedBox(height: 8),
                      _dialogDetailRow(
                        icon: Icons.door_front_door_outlined,
                        label: "Accès",
                        value: "${ticket.gate != null ? 'Porte ${ticket.gate}' : ''}${ticket.seatNumber != null ? ' • Siège ${ticket.seatNumber}' : ''}",
                        valueColor: Colors.white70,
                      ),
                    ],

                    // Prix
                    const SizedBox(height: 8),
                    _dialogDetailRow(
                      icon: Icons.payments_outlined,
                      label: "Tarif",
                      value: "${ticket.price.toStringAsFixed(0)} FCFA",
                      valueColor: const Color(0xFFFCD116),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: headerColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _isProcessing = false;
                  });
                  cameraController.start();
                },
                icon: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
                label: const Text(
                  "Scanner le billet suivant",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Text(
          "$label : ",
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
          "Contrôle des Billets FasoFoot",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isProcessing
                      ? Colors.orange
                      : const Color(0xFF008751),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: double.infinity,
                  height: 2,
                  color: const Color(0xFFFCD116).withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFFCD116), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Placez le QR Code dans le cadre. Chaque billet ne peut être scanné qu'une seule fois.",
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
