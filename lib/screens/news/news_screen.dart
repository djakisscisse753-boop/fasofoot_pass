import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
                child: Text(
                  "Erreur de chargement : ${snapshot.error}",
                  style: const TextStyle(color: Colors.redAccent),
                ),
              );
            }

            final tickets = snapshot.data ?? [];

            if (tickets.isEmpty) {
              return const Center(
                child: Text(
                  "Vous n'avez aucun billet pour le moment.",
                  style: TextStyle(color: Colors.white60, fontSize: 16),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
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
    final bool isValid = ticket.status == 'valid';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2634),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isValid ? const Color(0xFF008751) : Colors.grey.shade700,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Entête du billet
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isValid ? const Color(0xFF008751) : Colors.grey.shade800,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  ticket.categoryName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isValid ? const Color(0xFFFCD116) : Colors.red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ticket.status.toUpperCase(),
                    style: TextStyle(
                      color: isValid ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Corps du billet + QR Code
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Section QR Code
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: ticket.qrTokenSecret,
                    version: QrVersions.auto,
                    size: 90.0,
                  ),
                ),
                const SizedBox(width: 16),
                // Détails de la place
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Porte : ${ticket.gate ?? 'N/A'}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Siège : ${ticket.seatNumber ?? 'Libre'}",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Prix : ${ticket.price.toStringAsFixed(0)} FCFA",
                        style: const TextStyle(
                          color: Color(0xFFFCD116),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
