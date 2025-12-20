import 'dart:io';
import 'dart:math';
import '../../../core/services/logger_service.dart';

/// Service for generating and tracking unique para IDs.
///
/// Para IDs are 6-character alphanumeric identifiers used to uniquely
/// identify journal entries. They are stored in a simple text file
/// for persistence and loaded into memory for O(1) lookups.
///
/// Format: lowercase alphanumeric, e.g., "abc123", "x7k2m9"
class ParaIdService {
  static const String _fileName = 'uuids.txt';
  static const String _dirName = '.parachute';
  static const int _idLength = 6;
  static const String _charset = 'abcdefghijklmnopqrstuvwxyz0123456789';

  final String _vaultPath;
  final Set<String> _existingIds = {};
  final Random _random = Random.secure();
  final _log = logger.createLogger('ParaIdService');

  bool _initialized = false;
  File? _idsFile;

  ParaIdService({required String vaultPath}) : _vaultPath = vaultPath;

  /// Whether the service has been initialized
  bool get isInitialized => _initialized;

  /// Number of tracked IDs
  int get idCount => _existingIds.length;

  /// Path to the IDs file
  String get idsFilePath => '$_vaultPath/$_dirName/$_fileName';

  /// Initialize the service by loading existing IDs from disk
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final dir = Directory('$_vaultPath/$_dirName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _idsFile = File(idsFilePath);

      if (await _idsFile!.exists()) {
        final contents = await _idsFile!.readAsString();
        final ids = contents
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('#'));

        _existingIds.addAll(ids);
        _log.info('Loaded ${_existingIds.length} existing para IDs');
      } else {
        await _idsFile!.create();
        _log.info('Created new para IDs file');
      }

      _initialized = true;
    } catch (e, st) {
      _log.error('Failed to initialize ParaIdService', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Generate a new unique para ID
  ///
  /// Generates a random 6-character alphanumeric ID, checks for uniqueness,
  /// and persists it to the tracking file.
  Future<String> generate() async {
    _ensureInitialized();

    String id;
    int attempts = 0;
    const maxAttempts = 100;

    do {
      id = _generateRandomId();
      attempts++;
      if (attempts > maxAttempts) {
        throw StateError('Failed to generate unique ID after $maxAttempts attempts');
      }
    } while (_existingIds.contains(id));

    // Add to memory
    _existingIds.add(id);

    // Persist to file (append-only)
    try {
      await _idsFile!.writeAsString('$id\n', mode: FileMode.append);
      _log.debug('Generated new para ID', data: {'id': id});
    } catch (e, st) {
      // Rollback memory if file write fails
      _existingIds.remove(id);
      _log.error('Failed to persist para ID', error: e, stackTrace: st);
      rethrow;
    }

    return id;
  }

  /// Check if an ID exists
  bool exists(String id) {
    _ensureInitialized();
    return _existingIds.contains(id.toLowerCase());
  }

  /// Register an existing ID (used when parsing existing journal files)
  ///
  /// Returns true if the ID was newly registered, false if it already existed.
  Future<bool> register(String id) async {
    _ensureInitialized();

    final normalizedId = id.toLowerCase();
    if (_existingIds.contains(normalizedId)) {
      return false;
    }

    _existingIds.add(normalizedId);

    try {
      await _idsFile!.writeAsString('$normalizedId\n', mode: FileMode.append);
      _log.debug('Registered existing para ID', data: {'id': normalizedId});
      return true;
    } catch (e, st) {
      _existingIds.remove(normalizedId);
      _log.error('Failed to register para ID', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Validate a para ID format
  static bool isValidFormat(String id) {
    if (id.length != _idLength) return false;
    return id.toLowerCase().split('').every((char) => _charset.contains(char));
  }

  /// Parse a para ID from an H1 line
  ///
  /// Expected format: `# para:abc123 Title here`
  /// Returns the ID if found, null otherwise.
  static String? parseFromH1(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('# para:')) return null;

    final afterPrefix = trimmed.substring(7); // Skip "# para:"
    if (afterPrefix.length < _idLength) return null;

    final id = afterPrefix.substring(0, _idLength);
    if (!isValidFormat(id)) return null;

    return id.toLowerCase();
  }

  /// Extract the title from an H1 line (everything after the para ID)
  ///
  /// Expected format: `# para:abc123 Title here`
  /// Returns the title portion, or empty string if no title.
  static String parseTitleFromH1(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('# para:')) return trimmed.substring(2); // Regular H1

    final afterPrefix = trimmed.substring(7); // Skip "# para:"
    if (afterPrefix.length <= _idLength) return '';

    // Skip the ID and any following whitespace
    return afterPrefix.substring(_idLength).trimLeft();
  }

  /// Format an H1 line with para ID
  static String formatH1(String id, String title) {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      return '# para:$id';
    }
    return '# para:$id $trimmedTitle';
  }

  String _generateRandomId() {
    return List.generate(
      _idLength,
      (_) => _charset[_random.nextInt(_charset.length)],
    ).join();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('ParaIdService not initialized. Call initialize() first.');
    }
  }
}
