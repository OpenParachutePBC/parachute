import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/providers/embedding_provider.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/embedding/mobile_embedding_service.dart';

void main() {
  group('embedding_provider', () {
    group('mobileEmbeddingServiceProvider', () {
      test('creates MobileEmbeddingService instance', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final service = container.read(mobileEmbeddingServiceProvider);

        expect(service, isA<MobileEmbeddingService>());
        expect(service.dimensions, 256);
      });

      test('disposes service when container is disposed', () async {
        final container = ProviderContainer();

        final service = container.read(mobileEmbeddingServiceProvider);

        // Dispose container (should dispose service)
        container.dispose();

        // After disposal, service should not be usable
        final isReady = await service.isReady();
        expect(isReady, false);
      });
    });

    group('desktopEmbeddingServiceProvider', () {
      test('creates DesktopEmbeddingService instance', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final service = container.read(desktopEmbeddingServiceProvider);

        expect(service, isA<EmbeddingService>());
        expect(service.dimensions, 256);
      });
    });

    group('embeddingServiceProvider', () {
      test('returns mobile service on Android/iOS', () {
        if (!Platform.isAndroid && !Platform.isIOS) {
          // Skip if not on mobile platform
          return;
        }

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final service = container.read(embeddingServiceProvider);

        expect(service, isA<MobileEmbeddingService>());
      });

      test('returns desktop service on desktop platforms', () {
        if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) {
          // Skip if not on desktop platform
          return;
        }

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final service = container.read(embeddingServiceProvider);

        expect(service, isA<EmbeddingService>());
        expect(service.dimensions, 256);
      });
    });

    group('embeddingModelManagerProvider', () {
      test('creates manager with correct service', () {
        if (!Platform.isAndroid && !Platform.isIOS) {
          // Skip if not on mobile platform
          return;
        }

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final manager = container.read(embeddingModelManagerProvider);

        expect(manager.dimensions, 256);
      });

      test('disposes manager when container is disposed', () async {
        if (!Platform.isAndroid && !Platform.isIOS) {
          // Skip if not on mobile platform
          return;
        }

        final container = ProviderContainer();

        final manager = container.read(embeddingModelManagerProvider);

        // Dispose container (should dispose manager and service)
        container.dispose();

        // After disposal, manager should not be usable
        final isReady = await manager.isReady();
        expect(isReady, false);
      });
    });

    group('embeddingDimensionsProvider', () {
      test('returns correct dimensions for mobile (256)', () {
        if (!Platform.isAndroid && !Platform.isIOS) {
          // Skip if not on mobile platform
          return;
        }

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final dimensions = container.read(embeddingDimensionsProvider);

        expect(dimensions, 256);
      });
    });
  });
}
