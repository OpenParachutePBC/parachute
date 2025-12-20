import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../../../core/services/logger_service.dart';

/// Type of para ID, used for categorizing IDs in the registry.
enum ParaIdType {
  entry,    // Journal entries
  message,  // Chat messages
  asset,    // Media files
  session,  // Chat sessions
}

/// Registry entry for a para ID (stored in ids.jsonl).
class ParaIdEntry {
  final String id;
  final ParaIdType type;
  final DateTime created;
  final String? path;

  ParaIdEntry({
    required this.id,
    required this.type,
    required this.created,
    this.path,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'created': created.toIso8601String(),
    if (path != null) 'path': path,
  };

  factory ParaIdEntry.fromJson(Map<String, dynamic> json) => ParaIdEntry(
    id: json['id'] as String,
    type: ParaIdType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => ParaIdType.entry,
    ),
    created: DateTime.parse(json['created'] as String),
    path: json['path'] as String?,
  );

  String toJsonLine() => jsonEncode(toJson());
}

/// Service for generating and tracking unique para IDs.
///
/// Para IDs are alphanumeric identifiers used to uniquely identify content:
/// - Journal entries: `# para:abc123def456 Title`
/// - Chat messages: `### para:abc123def456 User | timestamp`
/// - Assets: `assets/2025-12/para_abc123def456_audio.wav`
/// - Sessions: `session_id: "para:abc123def456"`
///
/// New IDs are 12 characters (36^12 = 4.7 quintillion combinations).
/// Legacy 6-character IDs are still supported for backwards compatibility.
///
/// Registry stored in `.parachute/ids.jsonl` (JSONL format, append-only).
/// Legacy `uuids.txt` is read for backwards compatibility.
class ParaIdService {
  static const String _legacyFileName = 'uuids.txt';
  static const String _registryFileName = 'ids.jsonl';
  static const String _dirName = '.parachute';

  /// New IDs are 12 characters for more headroom
  static const int _newIdLength = 12;

  /// Legacy IDs were 6 characters
  static const int _legacyIdLength = 6;

  /// Valid ID lengths (for parsing)
  static const List<int> _validLengths = [_legacyIdLength, _newIdLength];

  static const String _charset = 'abcdefghijklmnopqrstuvwxyz0123456789';

  final String _vaultPath;
  final Set<String> _existingIds = {};
  final Map<String, ParaIdEntry> _registry = {};
  final Random _random = Random.secure();
  final _log = logger.createLogger('ParaIdService');

  bool _initialized = false;
  File? _registryFile;
  File? _legacyFile;

  ParaIdService({required String vaultPath}) : _vaultPath = vaultPath;

  /// Whether the service has been initialized
  bool get isInitialized => _initialized;

  /// Number of tracked IDs
  int get idCount => _existingIds.length;

  /// Path to the registry file
  String get registryFilePath => '$_vaultPath/$_dirName/$_registryFileName';

  /// Path to the legacy IDs file
  String get legacyFilePath => '$_vaultPath/$_dirName/$_legacyFileName';

  /// Initialize the service by loading existing IDs from disk
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final dir = Directory('$_vaultPath/$_dirName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _registryFile = File(registryFilePath);
      _legacyFile = File(legacyFilePath);

      // Load legacy uuids.txt for backwards compatibility
      await _loadLegacyIds();

      // Load new registry (ids.jsonl)
      await _loadRegistry();

      _log.info('Loaded ${_existingIds.length} para IDs (${_registry.length} with metadata)');

      _initialized = true;
    } catch (e, st) {
      _log.error('Failed to initialize ParaIdService', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Load legacy uuids.txt file
  Future<void> _loadLegacyIds() async {
    if (!await _legacyFile!.exists()) return;

    try {
      final contents = await _legacyFile!.readAsString();
      final ids = contents
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'));

      for (final id in ids) {
        _existingIds.add(id.toLowerCase());
      }
      _log.debug('Loaded ${ids.length} IDs from legacy uuids.txt');
    } catch (e) {
      _log.warn('Failed to load legacy uuids.txt', error: e);
    }
  }

  /// Load ids.jsonl registry
  Future<void> _loadRegistry() async {
    if (!await _registryFile!.exists()) {
      await _registryFile!.create();
      return;
    }

    try {
      final contents = await _registryFile!.readAsString();
      final lines = contents
          .split('\n')
          .where((line) => line.trim().isNotEmpty);

      for (final line in lines) {
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final entry = ParaIdEntry.fromJson(json);
          _existingIds.add(entry.id.toLowerCase());
          _registry[entry.id.toLowerCase()] = entry;
        } catch (e) {
          _log.warn('Invalid registry line', error: e, data: {'line': line});
        }
      }
    } catch (e) {
      _log.warn('Failed to load ids.jsonl', error: e);
    }
  }

  /// Generate a new unique para ID
  ///
  /// Generates a random 12-character alphanumeric ID, checks for uniqueness,
  /// and persists it to the registry.
  ///
  /// [type] - The type of content this ID is for (entry, message, asset, session)
  /// [path] - Optional path to the file this ID is associated with
  Future<String> generate({
    ParaIdType type = ParaIdType.entry,
    String? path,
  }) async {
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

    // Create registry entry
    final entry = ParaIdEntry(
      id: id,
      type: type,
      created: DateTime.now(),
      path: path,
    );

    // Add to memory
    _existingIds.add(id);
    _registry[id] = entry;

    // Persist to JSONL registry (append-only)
    try {
      await _registryFile!.writeAsString('${entry.toJsonLine()}\n', mode: FileMode.append);
      _log.debug('Generated new para ID', data: {'id': id, 'type': type.name});
    } catch (e, st) {
      // Rollback memory if file write fails
      _existingIds.remove(id);
      _registry.remove(id);
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

  /// Get registry entry for an ID
  ParaIdEntry? getEntry(String id) {
    _ensureInitialized();
    return _registry[id.toLowerCase()];
  }

  /// Get all entries of a specific type
  List<ParaIdEntry> getEntriesByType(ParaIdType type) {
    _ensureInitialized();
    return _registry.values.where((e) => e.type == type).toList();
  }

  /// Register an existing ID (used when parsing existing files)
  ///
  /// Returns true if the ID was newly registered, false if it already existed.
  Future<bool> register(
    String id, {
    ParaIdType type = ParaIdType.entry,
    String? path,
  }) async {
    _ensureInitialized();

    final normalizedId = id.toLowerCase();
    if (_existingIds.contains(normalizedId)) {
      return false;
    }

    final entry = ParaIdEntry(
      id: normalizedId,
      type: type,
      created: DateTime.now(),
      path: path,
    );

    _existingIds.add(normalizedId);
    _registry[normalizedId] = entry;

    try {
      await _registryFile!.writeAsString('${entry.toJsonLine()}\n', mode: FileMode.append);
      _log.debug('Registered existing para ID', data: {'id': normalizedId, 'type': type.name});
      return true;
    } catch (e, st) {
      _existingIds.remove(normalizedId);
      _registry.remove(normalizedId);
      _log.error('Failed to register para ID', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Update the path for an existing ID
  Future<void> updatePath(String id, String path) async {
    _ensureInitialized();

    final normalizedId = id.toLowerCase();
    final existing = _registry[normalizedId];
    if (existing == null) {
      throw StateError('ID not found: $id');
    }

    // Create updated entry
    final updated = ParaIdEntry(
      id: existing.id,
      type: existing.type,
      created: existing.created,
      path: path,
    );

    _registry[normalizedId] = updated;

    // Append updated entry (registry is append-only, duplicates resolved on load)
    try {
      await _registryFile!.writeAsString('${updated.toJsonLine()}\n', mode: FileMode.append);
      _log.debug('Updated para ID path', data: {'id': normalizedId, 'path': path});
    } catch (e, st) {
      _log.error('Failed to update para ID path', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Validate a para ID format (accepts both 6 and 12 char IDs)
  static bool isValidFormat(String id) {
    if (!_validLengths.contains(id.length)) return false;
    return id.toLowerCase().split('').every((char) => _charset.contains(char));
  }

  /// Check if an ID is the new 12-char format
  static bool isNewFormat(String id) {
    return id.length == _newIdLength && isValidFormat(id);
  }

  /// Check if an ID is the legacy 6-char format
  static bool isLegacyFormat(String id) {
    return id.length == _legacyIdLength && isValidFormat(id);
  }

  /// Parse a para ID from an H1 line (journal entries)
  ///
  /// Expected format: `# para:abc123def456 Title here`
  /// Returns the ID if found, null otherwise.
  /// Supports both 6-char and 12-char IDs.
  static String? parseFromH1(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('# para:')) return null;

    final afterPrefix = trimmed.substring(7); // Skip "# para:"

    // Try 12-char first (new format), then 6-char (legacy)
    for (final length in [_newIdLength, _legacyIdLength]) {
      if (afterPrefix.length >= length) {
        final potentialId = afterPrefix.substring(0, length);
        if (isValidFormat(potentialId)) {
          // Check that next char (if exists) is whitespace or end of string
          if (afterPrefix.length == length ||
              afterPrefix[length] == ' ' ||
              afterPrefix[length] == '\t') {
            return potentialId.toLowerCase();
          }
        }
      }
    }

    return null;
  }

  /// Parse a para ID from an H3 line (chat messages)
  ///
  /// Expected format: `### para:abc123def456 User | timestamp`
  /// Returns the ID if found, null otherwise.
  static String? parseFromH3(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('### para:')) return null;

    final afterPrefix = trimmed.substring(9); // Skip "### para:"

    // Try 12-char first (new format), then 6-char (legacy)
    for (final length in [_newIdLength, _legacyIdLength]) {
      if (afterPrefix.length >= length) {
        final potentialId = afterPrefix.substring(0, length);
        if (isValidFormat(potentialId)) {
          // Check that next char (if exists) is whitespace
          if (afterPrefix.length == length ||
              afterPrefix[length] == ' ' ||
              afterPrefix[length] == '\t') {
            return potentialId.toLowerCase();
          }
        }
      }
    }

    return null;
  }

  /// Extract the title from an H1 line (everything after the para ID)
  ///
  /// Expected format: `# para:abc123def456 Title here`
  /// Returns the title portion, or empty string if no title.
  static String parseTitleFromH1(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('# para:')) {
      // Regular H1 without para ID
      return trimmed.length > 2 ? trimmed.substring(2) : '';
    }

    final afterPrefix = trimmed.substring(7); // Skip "# para:"

    // Find where the ID ends
    for (final length in [_newIdLength, _legacyIdLength]) {
      if (afterPrefix.length >= length) {
        final potentialId = afterPrefix.substring(0, length);
        if (isValidFormat(potentialId)) {
          if (afterPrefix.length <= length) return '';
          return afterPrefix.substring(length).trimLeft();
        }
      }
    }

    return afterPrefix;
  }

  /// Parse role and timestamp from an H3 chat message line
  ///
  /// Expected format: `### para:abc123def456 User | timestamp`
  /// or legacy: `### User | timestamp`
  /// Returns (role, timestamp) tuple, or null if parsing fails.
  static (String role, String timestamp)? parseMessageHeader(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('### ')) return null;

    String afterHeader = trimmed.substring(4); // Skip "### "

    // Check if it has a para ID
    if (afterHeader.startsWith('para:')) {
      afterHeader = afterHeader.substring(5); // Skip "para:"

      // Skip the ID
      for (final length in [_newIdLength, _legacyIdLength]) {
        if (afterHeader.length >= length) {
          final potentialId = afterHeader.substring(0, length);
          if (isValidFormat(potentialId)) {
            afterHeader = afterHeader.substring(length).trimLeft();
            break;
          }
        }
      }
    }

    // Now parse "Role | timestamp"
    final pipeIndex = afterHeader.indexOf(' | ');
    if (pipeIndex == -1) return null;

    final role = afterHeader.substring(0, pipeIndex).trim();
    final timestamp = afterHeader.substring(pipeIndex + 3).trim();

    return (role, timestamp);
  }

  /// Format an H1 line with para ID (for journal entries)
  static String formatH1(String id, String title) {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      return '# para:$id';
    }
    return '# para:$id $trimmedTitle';
  }

  /// Format an H3 line with para ID (for chat messages)
  static String formatH3(String id, String role, String timestamp) {
    return '### para:$id $role | $timestamp';
  }

  /// Format an H3 line without para ID (legacy format)
  static String formatH3Legacy(String role, String timestamp) {
    return '### $role | $timestamp';
  }

  String _generateRandomId() {
    return List.generate(
      _newIdLength,
      (_) => _charset[_random.nextInt(_charset.length)],
    ).join();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('ParaIdService not initialized. Call initialize() first.');
    }
  }
}
