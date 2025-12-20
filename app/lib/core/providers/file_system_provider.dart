import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/services/file_system_service.dart';

/// Provider for the FileSystemService singleton
final fileSystemServiceProvider = Provider<FileSystemService>((ref) {
  return FileSystemService();
});
