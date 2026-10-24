import 'package:flutter_test/flutter_test.dart';
import 'package:try_on_clothes_ai/core/constants/app_constants.dart';

void main() {
  group('1-Month Ad-Free Subscription Pack Tests', () {
    test('AppConstants contains correct 1-month \$4.99 configuration', () {
      expect(AppConstants.subscriptionProductId, 'remove_ads');
      expect(AppConstants.subscriptionPriceUSD, 4.99);
      expect(AppConstants.subscriptionDurationMonths, 1);
      expect(AppConstants.subscriptionDurationLabel, '1 Month');
      expect(AppConstants.subscriptionMonthlyEquivalentUSD, 4.99);
      expect(
        AppConstants.subscriptionProductIds,
        contains(AppConstants.subscriptionProductId),
      );
    });

    test('Pricing formatting calculation is correct', () {
      final formatted = '\$${AppConstants.subscriptionPriceUSD.toStringAsFixed(2)}';
      expect(formatted, '\$4.99');
      final monthly = '\$${AppConstants.subscriptionMonthlyEquivalentUSD.toStringAsFixed(2)}';
      expect(monthly, '\$4.99');
    });
  });
}
