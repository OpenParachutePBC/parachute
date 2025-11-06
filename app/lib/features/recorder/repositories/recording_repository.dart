import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/services/storage_service.dart';

/// Repository for managing recording data access
///
/// This class follows the Repository Pattern, separating data access logic
/// from business logic. It provides a clean API for CRUD operations on recordings.
class RecordingRepository {
  final StorageService _storageService;

  RecordingRepository(this._storageService);

  /// Retrieves all recordings
  Future<List<Recording>> getAllRecordings() async {
    return await _storageService.getRecordings();
  }

  /// Retrieves a single recording by ID
  Future<Recording?> getRecordingById(String id) async {
    return await _storageService.getRecording(id);
  }

  /// Saves a new recording and returns the recording ID (timestamp)
  /// Returns null if save fails
  Future<String?> saveRecording(Recording recording) async {
    return await _storageService.saveRecording(recording);
  }

  /// Updates an existing recording
  Future<bool> updateRecording(Recording recording) async {
    return await _storageService.updateRecording(recording);
  }

  /// Deletes a recording by ID
  Future<bool> deleteRecording(String id) async {
    return await _storageService.deleteRecording(id);
  }

  /// Clears all recordings (for testing/reset purposes)
  Future<void> clearAll() async {
    return await _storageService.clearAllRecordings();
  }
}
