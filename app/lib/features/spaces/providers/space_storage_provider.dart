import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/space_storage_service.dart';

/// Provider for the local space storage service
final spaceStorageServiceProvider = Provider<SpaceStorageService>((ref) {
  return SpaceStorageService();
});
