# Parachute Testing Guide

**Last Updated:** December 8, 2025

This guide covers testing for the Parachute Flutter app.

---

## Quick Start

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/features/recorder/services/vad/simple_vad_test.dart

# Run tests matching a pattern
flutter test --name "SimpleVAD"
```

**Current Status:** 116+ tests covering audio pipeline, VAD, and core services.

---

## Test Organization

```
test/
├── features/
│   └── recorder/
│       └── services/
│           ├── audio_processing/
│           │   ├── resampler_test.dart
│           │   └── simple_noise_filter_test.dart
│           └── vad/
│               ├── simple_vad_test.dart
│               └── smart_chunker_test.dart
└── widget_test.dart
```

### Test Categories

**Unit Tests** - Pure logic testing:
- Audio processing (resampler, noise filter)
- VAD (voice activity detection)
- SmartChunker (silence-based segmentation)
- Data models

**Widget Tests** - UI component testing:
- Screens render correctly
- User interactions work
- State updates properly

---

## Writing Tests

### Unit Test Structure

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/recorder/services/vad/simple_vad.dart';

void main() {
  group('SimpleVAD', () {
    late SimpleVAD vad;

    setUp(() {
      vad = SimpleVAD();
    });

    test('detects speech for high-energy samples', () {
      // Given
      final samples = List.generate(160, (i) => (i * 100) % 32767);

      // When
      final result = vad.processFrame(samples);

      // Then
      expect(result, isTrue);
    });

    test('detects silence for low-energy samples', () {
      // Given
      final samples = List.generate(160, (_) => 10);

      // When
      final result = vad.processFrame(samples);

      // Then
      expect(result, isFalse);
    });
  });
}
```

### Widget Test Structure

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/widgets/recording_card.dart';

void main() {
  testWidgets('RecordingCard displays title', (tester) async {
    // Given
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RecordingCard(recording: mockRecording),
        ),
      ),
    );

    // Then
    expect(find.text('Test Recording'), findsOneWidget);
  });
}
```

**Important:** Always wrap widgets using Riverpod providers in `ProviderScope`.

---

## Testing Best Practices

### Do

- Test edge cases (empty input, max values, null)
- Test error conditions
- Use descriptive test names
- Group related tests with `group()`
- Use `setUp()` for common initialization

### Don't

- Test implementation details (test behavior, not internals)
- Write flaky tests (tests that sometimes fail)
- Skip tests without good reason
- Leave `print` statements in tests

---

## Manual Testing

### UI Testing with Playwright MCP

For UI changes, verify with actual browser testing:

1. Launch the app:
   ```bash
   flutter run -d chrome --web-port=8090
   ```

2. Use Playwright MCP to:
   - Navigate to screens
   - Interact with UI elements
   - Take screenshots
   - Verify user flows

3. Note: Flutter web renders to canvas, so use accessibility labels/semantics for targeting elements.

### Recording Flow Testing

Test the core recording flow manually:

1. Start a new recording
2. Speak for 10+ seconds
3. Observe real-time transcription
4. Stop recording
5. Verify recording appears in list
6. Verify markdown file saved to vault
7. Play back audio

### Cross-Platform Testing

Test on each target platform:

- **macOS**: Primary development platform
- **Android**: Test on physical device or emulator
- **iOS**: Test on simulator (requires Xcode)
- **Web**: Test in Chrome for Playwright

---

## Coverage

Generate coverage report:

```bash
flutter test --coverage
# Coverage data in coverage/lcov.info

# Generate HTML report (requires lcov)
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## Troubleshooting

### Tests Won't Run

```bash
# Clean and reinstall dependencies
flutter clean && flutter pub get

# Regenerate code
flutter pub run build_runner build --delete-conflicting-outputs
```

### Widget Tests Crash

- Missing `ProviderScope` wrapper
- Missing `MaterialApp` wrapper
- Async operations not properly handled

### Flaky Tests

- Check for race conditions
- Use `await tester.pumpAndSettle()` for animations
- Mock external dependencies

---

**Last Updated:** December 8, 2025
