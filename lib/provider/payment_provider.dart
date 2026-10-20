import 'package:flutter/foundation.dart';
import '../services/yenga_pay_service.dart';

class PaymentProvider extends ChangeNotifier {
  PaymentProvider({YengaPayService? paymentService})
    : _paymentService = paymentService ?? YengaPayService();

  final YengaPayService _paymentService;
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentTicketId;
  String? _checkoutUrl;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get currentTicketId => _currentTicketId;
  String? get checkoutUrl => _checkoutUrl;

  Future<bool> initiatePayment({
    required String matchId,
    required String phoneNumber,
    required String customerName,
    required String categoryName,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final checkout = await _paymentService.createCheckout(
        matchId: matchId,
        phoneNumber: phoneNumber,
        customerName: customerName,
        categoryName: categoryName,
      );
      _currentTicketId = checkout.ticketId;
      _checkoutUrl = checkout.checkoutUrl;
      return true;
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void resetPayment() {
    _currentTicketId = null;
    _checkoutUrl = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }
}
