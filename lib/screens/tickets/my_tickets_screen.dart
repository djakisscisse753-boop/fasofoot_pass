import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/ticket_service.dart';
import '../../models/ticket_model.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  final TicketService _ticketService = TicketService();
  late Future<List<TicketModel>> _ticketsFuture;

  @override
  void initState() {
    super.initState();
    _refreshTickets();
  }

  void _refreshTickets() {
    setState(() {
      _ticketsFuture = _ticketService.getUserTickets();
    });
  }

  /// Affiche le QR Code agrandi dans une boîte de dialogue modale
  void _showQrZoom(BuildContext context, TicketModel ticket) {
    final matchDate = ticket.matchDateTime;
    final dateStr = matchDate != null
        ? '${matchDate.day.toString().padLeft(2, '0')}/${matchDate.month.toString().padLeft(2, '0')}/${matchDate.year} '
            '${matchDate.hour.toString().padLeft(2, '0')}:${matchDate.minute.toString().padLeft(2, '0')}'
        : null;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A2634),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Titre du dialog
              Text(
                ticket.categoryName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              if (ticket.matchTeams != null) ...[
                const SizedBox(height: 4),
                Text(
                  ticket.matchTeams!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              // QR Code agrandi
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 16),
                  ],
                ),
                child: QrImageView(
                  data: ticket.qrTokenSecret,
                  version: QrVersions.auto,
                  size: 220.0,
                ),
              ),
              const SizedBox(height: 20),
              // Infos rapides sous le QR
              if (dateStr != null)
                _dialogInfoRow(Icons.event, dateStr, const Color(0xFFFCD116)),
              if (ticket.matchStadium != null)
                _dialogInfoRow(
                  Icons.stadium,
                  ticket.matchCity != null
                      ? '${ticket.matchStadium} · ${ticket.matchCity}'
                      : ticket.matchStadium!,
                  Colors.white54,
                ),
              const SizedBox(height: 8),
              const Text(
                'Présentez ce QR au portillon d\'entrée du stade.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008751),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Fermer',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogInfoRow(IconData icon, String text, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// Partage les informations du billet (texte)
  void _shareTicket(TicketModel ticket) {
    final matchDate = ticket.matchDateTime;
    final dateStr = matchDate != null
        ? '${matchDate.day.toString().padLeft(2, '0')}/${matchDate.month.toString().padLeft(2, '0')}/${matchDate.year} '
            'à ${matchDate.hour.toString().padLeft(2, '0')}h${matchDate.minute.toString().padLeft(2, '0')}'
        : 'Date à confirmer';

    final ownerLine = ticket.customerName != null && ticket.customerName!.isNotEmpty
        ? '\n👤 Propriétaire : ${ticket.customerName}'
        : '';
    final phoneLine = ticket.customerPhone != null && ticket.customerPhone!.isNotEmpty
        ? '\n📱 Tél : ${ticket.customerPhone}'
        : '';
    final stadiumLine = ticket.matchStadium != null
        ? '\n🏟️ Stade : ${ticket.matchStadium}${ticket.matchCity != null ? ' (${ticket.matchCity})' : ''}'
        : '';

    final text = '🎟️ *FasoFoot Pass — Billet d\'accès*\n'
        '\n'
        '⚽ Match : ${ticket.matchTeams ?? 'FasoFoot'}\n'
        '📅 Date : $dateStr'
        '$stadiumLine\n'
        '🪑 Tribune : ${ticket.categoryName}\n'
        '💰 Prix : ${ticket.price.toStringAsFixed(0)} FCFA'
        '$ownerLine'
        '$phoneLine\n'
        '\n'
        'Présentez le QR Code de l\'application FasoFoot Pass au portillon d\'accès du stade.';

    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        title: const Text(
          "Mes Billets",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshTickets(),
        color: const Color(0xFF008751),
        child: FutureBuilder<List<TicketModel>>(
          future: _ticketsFuture,
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
                      const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        "Impossible de charger vos billets.",
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _refreshTickets,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final tickets = snapshot.data ?? [];

            if (tickets.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.confirmation_number_outlined,
                          size: 64,
                          color: Colors.white24,
                        ),
                        SizedBox(height: 16),
                        Text(
                          "Vous n'avez aucun billet pour le moment.",
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Vos billets achetés s'afficheront ici avec leur QR code d'accès au stade.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: tickets.length,
              itemBuilder: (context, index) {
                final ticket = tickets[index];
                return _buildTicketCard(ticket);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildTicketCard(TicketModel ticket) {
    final bool isValid = ticket.isValid;
    final bool isPending = ticket.isPending;
    final bool isUsed = ticket.isUsed;
    final bool hasQr = ticket.qrTokenSecret.isNotEmpty && isValid;

    Color badgeColor;
    Color badgeTextColor;
    if (isValid) {
      badgeColor = const Color(0xFF008751);
      badgeTextColor = Colors.white;
    } else if (isPending) {
      badgeColor = const Color(0xFFFCD116);
      badgeTextColor = Colors.black;
    } else if (isUsed) {
      badgeColor = Colors.red.shade700;
      badgeTextColor = Colors.white;
    } else {
      badgeColor = Colors.redAccent;
      badgeTextColor = Colors.white;
    }

    final matchDate = ticket.matchDateTime;
    final dateStr = matchDate != null
        ? '${matchDate.day.toString().padLeft(2, '0')}/${matchDate.month.toString().padLeft(2, '0')}/${matchDate.year} • ${matchDate.hour.toString().padLeft(2, '0')}:${matchDate.minute.toString().padLeft(2, '0')}'
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUsed
              ? Colors.red.shade700
              : isValid
                  ? const Color(0xFF008751)
                  : Colors.white12,
          width: (isValid || isUsed) ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // En-tête du billet : Titre de la tribune et statut
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isUsed
                  ? Colors.red.shade900
                  : isValid
                      ? const Color(0xFF008751)
                      : const Color(0xFF223142),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isUsed ? Icons.check_circle : Icons.confirmation_number,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ticket.categoryName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Text(
                    ticket.statusLabel,
                    style: TextStyle(
                      color: badgeTextColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Corps du billet : Match, Stade, Prix & QR Code
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Section QR Code — cliquable pour zoomer
                if (hasQr)
                  GestureDetector(
                    onTap: () => _showQrZoom(context, ticket),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 6),
                            ],
                          ),
                          child: QrImageView(
                            data: ticket.qrTokenSecret,
                            version: QrVersions.auto,
                            size: 96.0,
                          ),
                        ),
                        // Icône loupe pour indiquer le zoom
                        Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF008751),
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.zoom_in,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isUsed)
                  // Ticket utilisé → rouge avec icône
                  Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade700, width: 1.5),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.redAccent,
                            size: 36,
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Scanné',
                            style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      color: const Color(0xFF223142),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPending
                                ? Icons.hourglass_top_rounded
                                : Icons.block,
                            color: isPending ? const Color(0xFFFCD116) : Colors.white38,
                            size: 32,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isPending ? 'En attente' : 'Non actif',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 16),
                // Détails du match
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.matchTeams ?? "Billet FasoFoot Pass",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (dateStr != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.event, size: 13, color: Color(0xFFFCD116)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                dateStr,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (ticket.matchStadium != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 13, color: Color(0xFFFCD116)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                ticket.matchCity != null && ticket.matchCity!.isNotEmpty
                                    ? "${ticket.matchStadium} · ${ticket.matchCity}"
                                    : ticket.matchStadium!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Infos propriétaire du billet
                      if (ticket.customerName != null && ticket.customerName!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.person, size: 13, color: Colors.white38),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                ticket.customerName!,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (ticket.customerPhone != null && ticket.customerPhone!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.phone, size: 13, color: Colors.white38),
                            const SizedBox(width: 5),
                            Text(
                              ticket.customerPhone!,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        "${ticket.price.toStringAsFixed(0)} FCFA",
                        style: const TextStyle(
                          color: Color(0xFFFCD116),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Pied du billet : Infos accès + bouton Partager
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF131D27),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                // Message d'info selon le statut
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        isUsed
                            ? Icons.check_circle_outline
                            : isPending
                                ? Icons.hourglass_top_rounded
                                : isValid
                                    ? Icons.info_outline
                                    : Icons.block,
                        size: 13,
                        color: isUsed ? Colors.redAccent : Colors.white38,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isUsed
                              ? "Ce billet a déjà été scanné et utilisé."
                              : isPending
                                  ? "Paiement en cours de vérification..."
                                  : isValid
                                      ? "Présentez ce QR Code au portillon d'accès."
                                      : "Billet non valide.",
                          style: TextStyle(
                            color: isUsed ? Colors.red.shade300 : Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Bouton partager (disponible pour tout billet valide ou en attente)
                if (isValid || isPending) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _shareTicket(ticket),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A5F),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.share, size: 13, color: Colors.white70),
                          SizedBox(width: 4),
                          Text(
                            'Partager',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
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
}
