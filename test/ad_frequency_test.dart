import 'package:flutter_test/flutter_test.dart';
import 'package:try_on_clothes_ai/core/services/ad_service.dart';

void main() {
  test('Interstitial ad triggers strictly on every 2nd result', () {
    AdService.resetGenerationCounter();

    // 1st result
    expect(AdService.onGenerationResultCompleted(), isFalse, reason: '1st result must not show interstitial');
    expect(AdService.generationResultCount, equals(1));

    // 2nd result -> Trigger!
    expect(AdService.onGenerationResultCompleted(), isTrue, reason: '2nd result MUST trigger interstitial');
    expect(AdService.generationResultCount, equals(2));

    // 3rd result
    expect(AdService.onGenerationResultCompleted(), isFalse, reason: '3rd result must not show interstitial');
    expect(AdService.generationResultCount, equals(3));

    // 4th result -> Trigger!
    expect(AdService.onGenerationResultCompleted(), isTrue, reason: '4th result MUST trigger interstitial');
    expect(AdService.generationResultCount, equals(4));

    // 5th result
    expect(AdService.onGenerationResultCompleted(), isFalse, reason: '5th result must not show interstitial');

    // 6th result -> Trigger!
    expect(AdService.onGenerationResultCompleted(), isTrue, reason: '6th result MUST trigger interstitial');
  });

  test('Concurrent background generation ad trigger on upcoming 2nd result', () {
    AdService.resetGenerationCounter();

    // Before 1st generation
    expect(AdService.shouldTriggerForNextGeneration(), isFalse, reason: 'Generation #1 must NOT trigger ad');
    AdService.recordGenerationCompleted();
    expect(AdService.generationResultCount, equals(1));

    // Before 2nd generation -> MUST trigger ad during background generation!
    expect(AdService.shouldTriggerForNextGeneration(), isTrue, reason: 'Generation #2 MUST trigger ad concurrently');
    AdService.recordGenerationCompleted();
    expect(AdService.generationResultCount, equals(2));

    // Before 3rd generation
    expect(AdService.shouldTriggerForNextGeneration(), isFalse, reason: 'Generation #3 must NOT trigger ad');
    AdService.recordGenerationCompleted();
    expect(AdService.generationResultCount, equals(3));

    // Before 4th generation -> MUST trigger ad
    expect(AdService.shouldTriggerForNextGeneration(), isTrue, reason: 'Generation #4 MUST trigger ad concurrently');
    AdService.recordGenerationCompleted();
    expect(AdService.generationResultCount, equals(4));
  });
}

