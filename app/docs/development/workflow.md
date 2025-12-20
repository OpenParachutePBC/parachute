# Parachute - Development Workflow

**Last Updated:** December 8, 2025

This document describes the day-to-day development workflow for Parachute.

---

## Daily Development

### Starting Work

```bash
# Run the app
flutter run -d macos    # macOS
flutter run -d android  # Android
flutter run -d chrome --web-port=8090  # Web (for Playwright testing)

# Run tests
flutter test
```

### Hot Reload

- Changes to Dart files: Press `r` for hot reload, `R` for hot restart
- Changes to pubspec.yaml: Stop and `flutter run` again
- Changes to assets: Press `R` for hot restart

---

## Git Workflow

### Branch Strategy

```
main              → Production-ready code (protected)
feature/xyz       → Feature branches
bugfix/xyz        → Bug fix branches
docs/xyz          → Documentation updates
```

### Working on a Feature

```bash
# Start from main
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/sphere-management

# Make changes, commit frequently
git add .
git commit -m "feat: implement sphere linking"

# Push to remote
git push origin feature/sphere-management

# Create PR to main when complete
```

### Commit Message Convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add sphere management screen
fix: resolve recording persistence issue
docs: update CLAUDE.md with new patterns
refactor: simplify transcription service
test: add VAD unit tests
chore: update dependencies
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style (formatting, no logic change)
- `refactor`: Code change without adding features or fixing bugs
- `test`: Adding or updating tests
- `chore`: Maintenance (deps, configs, etc.)

---

## Code Organization

### Project Structure

```
parachute/
├── lib/
│   ├── main.dart                # Entry point
│   ├── core/                    # App-wide concerns
│   │   ├── constants/           # App constants
│   │   ├── theme/               # Light/dark themes, design tokens
│   │   ├── providers/           # Core Riverpod providers
│   │   ├── services/            # Core services (file system, etc.)
│   │   └── widgets/             # Reusable widgets
│   ├── features/                # Feature-first organization
│   │   ├── recorder/            # Voice recording feature
│   │   │   ├── screens/         # UI screens
│   │   │   ├── widgets/         # Feature-specific widgets
│   │   │   ├── providers/       # Riverpod providers
│   │   │   ├── services/        # Recording, transcription, VAD
│   │   │   └── models/          # Data models
│   │   ├── settings/            # Settings screen
│   │   └── onboarding/          # Onboarding flow
│   └── services/                # Platform-specific services
│       ├── parakeet_service.dart    # iOS/macOS transcription
│       └── sherpa_onnx_service.dart # Android transcription
├── test/                        # Unit tests
├── ios/, android/, macos/, linux/, windows/, web/  # Platform code
├── assets/                      # Firmware, models, icons
└── docs/                        # Documentation
```

**Principles:**
- Feature-first (not layer-first) organization
- Each feature is self-contained
- Shared code only when used by 2+ features
- Riverpod providers co-located with features

---

## Testing Strategy

### Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/features/recorder/services/vad/simple_vad_test.dart

# Run with coverage
flutter test --coverage
```

### Test Structure

```dart
// test/features/recorder/services/vad/simple_vad_test.dart
void main() {
  group('SimpleVAD', () {
    test('detects speech for high-energy samples', () {
      // Given
      final vad = SimpleVAD();
      final samples = generateHighEnergySamples();

      // When
      final result = vad.processFrame(samples);

      // Then
      expect(result, isTrue);
    });
  });
}
```

### Widget Tests

```dart
testWidgets('Recording card displays title', (WidgetTester tester) async {
  // Given
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: RecordingCard(recording: mockRecording)),
    ),
  );

  // When
  await tester.pump();

  // Then
  expect(find.text('Test Recording'), findsOneWidget);
});
```

---

## Debugging

### Flutter DevTools

```bash
# Run app
flutter run

# Open DevTools (click link in terminal or)
flutter pub global activate devtools
flutter pub global run devtools
```

### Print Debugging

```dart
import 'package:flutter/foundation.dart';

debugPrint('State updated: $state');
```

### VSCode Debugging

1. Set breakpoint (click left of line number)
2. F5 to start debugging
3. Use Debug Console

---

## Common Tasks

### Adding a New Screen

1. Create screen in `lib/features/[feature]/screens/`
2. Create provider in `lib/features/[feature]/providers/`
3. Add route if using navigation
4. Create widgets if needed
5. Write widget tests

### Adding a New Service

1. Create service in `lib/features/[feature]/services/` or `lib/core/services/`
2. Create provider to expose it
3. Write unit tests
4. Document in feature's CLAUDE.md if complex

### Adding a New Dependency

```bash
# Add to pubspec.yaml
flutter pub add package_name

# Or edit pubspec.yaml directly and run
flutter pub get
```

---

## Troubleshooting

### App Won't Build

**Check:**
- Dependencies installed: `flutter pub get`
- Generated files up to date: `flutter pub run build_runner build`
- No syntax errors: `flutter analyze`
- Clear cache if needed: `flutter clean && flutter pub get`

### Tests Failing

1. Run tests locally to reproduce
2. Check for missing ProviderScope in widget tests
3. Verify mocks are set up correctly
4. Check async operations are properly awaited

### Platform-Specific Issues

**macOS:**
- Check entitlements in `macos/Runner/DebugProfile.entitlements`
- Verify code signing settings

**Android:**
- Check permissions in `AndroidManifest.xml`
- Verify minSdkVersion compatibility

**iOS:**
- Check Info.plist for required permissions
- Verify provisioning profiles

---

## Best Practices

### Code Quality

- Run tests before committing
- Run linter: `flutter analyze`
- Format code: `dart format lib/`
- Review your own changes before pushing

### Commits

- Commit frequently (small, logical changes)
- Write clear commit messages
- Don't commit secrets or large files
- Don't commit generated files (they're gitignored)

### Documentation

- Update CLAUDE.md when making architectural changes
- Comment complex logic
- Update README if adding new setup steps

---

**Last Updated:** December 8, 2025
