import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/services/search/bm25_search_service.dart';
import 'package:app/core/services/search/bm25_index_manager.dart';
import 'package:app/features/recorder/providers/service_providers.dart';

/// Provider for BM25SearchService
///
/// Provides BM25 keyword search functionality for recordings.
/// The service maintains an in-memory index that can be rebuilt quickly.
///
/// **Usage:**
/// ```dart
/// final searchService = ref.read(bm25SearchServiceProvider);
/// final results = await searchService.search('project alpha', limit: 20);
/// ```
final bm25SearchServiceProvider = Provider<BM25SearchService>((ref) {
  return BM25SearchService();
});

/// Provider for BM25IndexManager
///
/// Manages the lifecycle of the BM25 index, including building,
/// rebuilding, and invalidation.
///
/// **Usage:**
/// ```dart
/// final indexManager = ref.read(bm25IndexManagerProvider);
/// await indexManager.ensureIndexReady();
/// ```
final bm25IndexManagerProvider = Provider<BM25IndexManager>((ref) {
  final searchService = ref.watch(bm25SearchServiceProvider);
  final storageService = ref.watch(storageServiceProvider);
  return BM25IndexManager(searchService, storageService);
});
