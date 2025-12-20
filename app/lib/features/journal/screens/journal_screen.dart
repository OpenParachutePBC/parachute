import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/services/file_system_service.dart';
import '../../../core/providers/file_system_provider.dart';
import '../../recorder/providers/service_providers.dart';
import '../../recorder/widgets/playback_controls.dart';
import '../models/journal_day.dart';
import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import '../widgets/journal_entry_row.dart';
import '../widgets/journal_input_bar.dart';
import '../widgets/mini_audio_player.dart';
import '../../settings/screens/settings_screen.dart';

/// Main journal screen showing today's journal entries
///
/// The daily journal is the home for captures - voice notes, typed thoughts,
/// and links to longer recordings.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final ScrollController _scrollController = ScrollController();

  // Editing state
  String? _editingEntryId;
  String? _editingEntryContent;
  String? _editingEntryTitle;

  // Track entry pending transcription (for streaming audio)
  String? _pendingTranscriptionEntryId;

  // Guard to prevent multiple rapid audio plays
  bool _isPlayingAudio = false;

  // Flag to scroll to bottom after new entry is added
  bool _shouldScrollToBottom = false;

  // Track entries that are actively transcribing
  final Set<String> _transcribingEntryIds = {};

  // Audio playback state
  String? _currentlyPlayingAudioPath;
  String? _currentlyPlayingTitle;

  // Draft caching
  Timer? _draftSaveTimer;
  static const _draftKeyPrefix = 'journal_draft_';

  // Local journal cache to avoid loading flash on updates
  JournalDay? _cachedJournal;
  DateTime? _cachedJournalDate;

  @override
  void initState() {
    super.initState();
    // Check for any pending drafts on startup
    _checkForPendingDrafts();
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Check if there are any pending drafts and offer to restore them
  Future<void> _checkForPendingDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_draftKeyPrefix));
    if (keys.isNotEmpty) {
      debugPrint('[JournalScreen] Found ${keys.length} pending draft(s)');
    }
  }

  /// Save draft for an entry (debounced)
  void _saveDraftDebounced(String entryId, String? content, String? title) {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _saveDraft(entryId, content, title);
    });
  }

  /// Save draft immediately
  Future<void> _saveDraft(String entryId, String? content, String? title) async {
    if (content == null && title == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = '$_draftKeyPrefix$entryId';

    // Store as simple format: title|||content
    final draftValue = '${title ?? ''}|||${content ?? ''}';
    await prefs.setString(key, draftValue);
    debugPrint('[JournalScreen] Draft saved for entry $entryId');
  }

  /// Load draft for an entry
  Future<({String? title, String? content})?> _loadDraft(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_draftKeyPrefix$entryId';
    final draftValue = prefs.getString(key);

    if (draftValue == null) return null;

    final parts = draftValue.split('|||');
    if (parts.length != 2) return null;

    final title = parts[0].isEmpty ? null : parts[0];
    final content = parts[1].isEmpty ? null : parts[1];

    // Only return if there's actual draft content
    if (title == null && content == null) return null;

    debugPrint('[JournalScreen] Draft loaded for entry $entryId');
    return (title: title, content: content);
  }

  /// Clear draft for an entry
  Future<void> _clearDraft(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_draftKeyPrefix$entryId';
    await prefs.remove(key);
    debugPrint('[JournalScreen] Draft cleared for entry $entryId');
  }

  Future<void> _refreshJournal() async {
    ref.invalidate(selectedJournalProvider);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // Use a small delay to ensure layout is complete before scrolling
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the selected date and its journal
    final selectedDate = ref.watch(selectedJournalDateProvider);
    final journalAsync = ref.watch(selectedJournalProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Check if viewing today
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;

    // Clear cache if date changed
    if (_cachedJournalDate != null &&
        (_cachedJournalDate!.year != selectedDate.year ||
            _cachedJournalDate!.month != selectedDate.month ||
            _cachedJournalDate!.day != selectedDate.day)) {
      _cachedJournal = null;
      _cachedJournalDate = null;
    }

    // Update cache when data is available
    journalAsync.whenData((journal) {
      _cachedJournal = journal;
      _cachedJournalDate = selectedDate;
    });

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context, selectedDate, isToday, journalAsync),

            // Journal entries - use cached data during loading to avoid flash
            Expanded(
              child: journalAsync.when(
                data: (journal) => _buildJournalContent(context, journal),
                loading: () {
                  // Use cached journal if available to avoid loading flash
                  if (_cachedJournal != null) {
                    return _buildJournalContent(context, _cachedJournal!);
                  }
                  return const Center(child: CircularProgressIndicator());
                },
                error: (error, stack) => _buildErrorState(context, error),
              ),
            ),

            // Mini audio player (shows when playing)
            MiniAudioPlayer(
              currentAudioPath: _currentlyPlayingAudioPath,
              entryTitle: _currentlyPlayingTitle,
              onStop: () {
                setState(() {
                  _currentlyPlayingAudioPath = null;
                  _currentlyPlayingTitle = null;
                });
              },
            ),

            // Input bar at bottom (only show for today)
            if (isToday)
              JournalInputBar(
                onTextSubmitted: (text) => _addTextEntry(text),
                onVoiceRecorded: (transcript, audioPath, duration) =>
                    _addVoiceEntry(transcript, audioPath, duration),
                onTranscriptReady: (transcript) => _updatePendingTranscription(transcript),
              ),
          ],
        ),
      ),
    );
  }

  /// Add text entry
  Future<void> _addTextEntry(String text) async {
    debugPrint('[JournalScreen] Adding text entry...');

    try {
      final service = await ref.read(journalServiceFutureProvider.future);
      final result = await service.addTextEntry(content: text);

      debugPrint('[JournalScreen] Entry added, updating cache...');

      // Update cache immediately for instant UI feedback
      setState(() {
        _cachedJournal = result.journal;
        _shouldScrollToBottom = true;
      });

      // Also refresh provider in background (won't cause loading flash due to cache)
      ref.invalidate(selectedJournalProvider);
      ref.read(journalRefreshTriggerProvider.notifier).state++;
    } catch (e, st) {
      debugPrint('[JournalScreen] Error adding text entry: $e');
      debugPrint('$st');
    }
  }

  /// Add voice entry
  /// With streaming: transcript may be empty initially, then updated via _updatePendingTranscription
  Future<void> _addVoiceEntry(
    String transcript,
    String audioPath,
    int duration,
  ) async {
    debugPrint('[JournalScreen] Adding voice entry...');

    try {
      final service = await ref.read(journalServiceFutureProvider.future);
      final result = await service.addVoiceEntry(
        transcript: transcript,
        audioPath: audioPath,
        durationSeconds: duration,
      );

      // Track if this entry needs transcription update (empty transcript)
      if (transcript.isEmpty) {
        _pendingTranscriptionEntryId = result.entry.id;
        debugPrint('[JournalScreen] Entry ${result.entry.id} pending transcription');
      }

      debugPrint('[JournalScreen] Voice entry added, updating cache...');

      // Update cache immediately for instant UI feedback
      setState(() {
        _cachedJournal = result.journal;
        _shouldScrollToBottom = true;
      });

      // Also refresh provider in background (won't cause loading flash due to cache)
      ref.invalidate(selectedJournalProvider);
      ref.read(journalRefreshTriggerProvider.notifier).state++;
    } catch (e, st) {
      debugPrint('[JournalScreen] Error adding voice entry: $e');
      debugPrint('$st');
    }
  }

  /// Update the pending entry with transcription result (streaming audio)
  Future<void> _updatePendingTranscription(String transcript) async {
    if (_pendingTranscriptionEntryId == null) {
      debugPrint('[JournalScreen] No pending entry to update');
      return;
    }

    final entryId = _pendingTranscriptionEntryId!;
    _pendingTranscriptionEntryId = null; // Clear early to prevent duplicate updates
    debugPrint('[JournalScreen] Updating entry $entryId with transcript...');

    try {
      final service = await ref.read(journalServiceFutureProvider.future);
      final selectedDate = ref.read(selectedJournalDateProvider);

      // Find the existing entry to preserve its metadata
      final existingEntry = _cachedJournal?.getEntry(entryId);
      final entry = JournalEntry(
        id: entryId,
        title: existingEntry?.title ?? _formatTime(DateTime.now()),
        content: transcript,
        type: JournalEntryType.voice,
        createdAt: existingEntry?.createdAt ?? DateTime.now(),
        audioPath: existingEntry?.audioPath,
        durationSeconds: existingEntry?.durationSeconds,
      );

      await service.updateEntry(selectedDate, entry);
      debugPrint('[JournalScreen] Transcription update complete');

      // Update cache immediately to avoid loading flash
      if (_cachedJournal != null) {
        setState(() {
          _cachedJournal = _cachedJournal!.updateEntry(entry);
        });
      }

      // Also refresh provider in background
      ref.invalidate(selectedJournalProvider);
    } catch (e, st) {
      debugPrint('[JournalScreen] Error updating transcription: $e');
      debugPrint('$st');
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Play audio for a journal entry (inline in list view)
  ///
  /// Shows mini player with playback controls while audio is playing.
  Future<void> _playAudio(String relativePath, {String? entryTitle}) async {
    // Guard against multiple rapid taps
    if (_isPlayingAudio) {
      debugPrint('[JournalScreen] Audio play already in progress, ignoring');
      return;
    }

    _isPlayingAudio = true;
    debugPrint('[JournalScreen] Playing audio: $relativePath');

    try {
      final audioService = ref.read(audioServiceProvider);

      // Ensure audio service is initialized
      await audioService.initialize();

      // Construct full path from relative path
      final fullPath = await _getFullAudioPath(relativePath);
      debugPrint('[JournalScreen] Full audio path: $fullPath');

      // Check if file exists and has content
      final file = File(fullPath);
      if (!await file.exists()) {
        debugPrint('[JournalScreen] ERROR: Audio file does not exist at: $fullPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Audio file not found'),
                  Text(
                    relativePath,
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
              backgroundColor: BrandColors.error,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final fileSize = await file.length();
      debugPrint('[JournalScreen] Audio file size: $fileSize bytes');

      if (fileSize == 0) {
        debugPrint('[JournalScreen] ERROR: Audio file is empty!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audio file is empty'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final success = await audioService.playRecording(fullPath);
      debugPrint('[JournalScreen] playRecording returned: $success');

      if (success) {
        // Update state to show mini player
        setState(() {
          _currentlyPlayingAudioPath = fullPath;
          _currentlyPlayingTitle = entryTitle ?? 'Audio';
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not play audio file'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[JournalScreen] Error playing audio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing audio: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      // Reset after a short delay to allow the audio to start
      Future.delayed(const Duration(milliseconds: 500), () {
        _isPlayingAudio = false;
      });
    }
  }

  Widget _buildHeader(
    BuildContext context,
    DateTime selectedDate,
    bool isToday,
    AsyncValue<JournalDay> journalAsync,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Format the display date
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final displayDate = '${months[selectedDate.month - 1]} ${selectedDate.day}, ${selectedDate.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        border: Border(
          bottom: BorderSide(
            color: isDark ? BrandColors.charcoal : BrandColors.stone,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Date navigation (left arrow)
          IconButton(
            icon: Icon(
              Icons.chevron_left,
              color: isDark ? BrandColors.driftwood : BrandColors.charcoal,
            ),
            onPressed: () {
              ref.read(selectedJournalDateProvider.notifier).state =
                  selectedDate.subtract(const Duration(days: 1));
            },
          ),

          Expanded(
            child: GestureDetector(
              onTap: () => _showDatePicker(context),
              child: Column(
                children: [
                  if (isToday)
                    Text(
                      'Today',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: BrandColors.forest,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    displayDate,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isDark ? BrandColors.softWhite : BrandColors.ink,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          // Date navigation (right arrow) - disabled if today
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: isToday
                  ? (isDark ? BrandColors.charcoal : BrandColors.stone)
                  : (isDark ? BrandColors.driftwood : BrandColors.charcoal),
            ),
            onPressed: isToday
                ? null
                : () {
                    ref.read(selectedJournalDateProvider.notifier).state =
                        selectedDate.add(const Duration(days: 1));
                  },
          ),

          // Refresh button (desktop only - mobile uses pull-to-refresh)
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: isDark ? BrandColors.driftwood : BrandColors.charcoal,
              ),
              tooltip: 'Refresh',
              onPressed: _refreshJournal,
            ),

          // Settings button
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: isDark ? BrandColors.driftwood : BrandColors.charcoal,
            ),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showDatePicker(BuildContext context) async {
    final selectedDate = ref.read(selectedJournalDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(selectedJournalDateProvider.notifier).state = picked;
    }
  }

  Widget _buildJournalContent(BuildContext context, JournalDay journal) {
    // Check if viewing today
    final selectedDate = ref.read(selectedJournalDateProvider);
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Handle scroll to bottom after new entry is added
    if (_shouldScrollToBottom) {
      _shouldScrollToBottom = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }

    if (journal.isEmpty) {
      return _buildEmptyState(context, isToday);
    }

    return RefreshIndicator(
      onRefresh: _refreshJournal,
      color: BrandColors.forest,
      child: GestureDetector(
        // Tap empty space to save and deselect editing
        onTap: () {
          if (_editingEntryId != null) {
            _saveCurrentEdit();
          }
        },
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: journal.entries.length,
          itemBuilder: (context, index) {
            final entry = journal.entries[index];
            final isEditing = _editingEntryId == entry.id;

            return Column(
              children: [
                // Subtle divider between entries (except first)
                if (index > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: isDark
                          ? BrandColors.charcoal.withValues(alpha: 0.3)
                          : BrandColors.stone.withValues(alpha: 0.3),
                    ),
                  ),

                JournalEntryRow(
                  entry: entry,
                  audioPath: journal.getAudioPath(entry.id),
                  isEditing: isEditing,
                  // Show transcribing for both manual transcribe and background transcription
                  isTranscribing: _transcribingEntryIds.contains(entry.id) ||
                      _pendingTranscriptionEntryId == entry.id,
                  onTap: () => _handleEntryTap(entry),
                  onLongPress: () => _showEntryActions(context, journal, entry),
                  onPlayAudio: (path) => _playAudio(path, entryTitle: entry.title),
                  onTranscribe: () => _handleTranscribe(entry, journal),
                  onContentChanged: (content) => _handleContentChanged(entry.id, content),
                  onTitleChanged: (title) => _handleTitleChanged(entry.id, title),
                  onEditingComplete: _saveCurrentEdit,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _handleEntryTap(JournalEntry entry) async {
    // Don't edit preamble/imported markdown
    if (entry.id == 'preamble' || entry.id.startsWith('plain_')) {
      _showEntryDetail(context, entry);
      return;
    }

    // If already editing this entry, do nothing (let TextField handle taps)
    if (_editingEntryId == entry.id) {
      return;
    }

    // If editing another entry, save it first
    if (_editingEntryId != null) {
      _saveCurrentEdit();
    }

    // Check for existing draft
    final draft = await _loadDraft(entry.id);
    final hasUnsavedDraft = draft != null &&
        ((draft.content != null && draft.content != entry.content) ||
         (draft.title != null && draft.title != entry.title));

    // Start editing this entry
    setState(() {
      _editingEntryId = entry.id;
      // Use draft content if available, otherwise use entry content
      if (hasUnsavedDraft) {
        _editingEntryContent = draft.content ?? entry.content;
        _editingEntryTitle = draft.title ?? entry.title;
      } else {
        _editingEntryContent = entry.content;
        _editingEntryTitle = entry.title;
      }
    });

    // Notify user if draft was restored
    if (hasUnsavedDraft && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.restore, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Text('Draft restored'),
            ],
          ),
          backgroundColor: BrandColors.forest,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  Future<void> _saveCurrentEdit() async {
    if (_editingEntryId == null) return;

    // Cancel any pending draft save
    _draftSaveTimer?.cancel();

    final entryId = _editingEntryId!;
    final newContent = _editingEntryContent;
    final newTitle = _editingEntryTitle;

    // Clear editing state first
    setState(() {
      _editingEntryId = null;
      _editingEntryContent = null;
      _editingEntryTitle = null;
    });

    // Only save if we have content changes
    if (newContent == null && newTitle == null) {
      // Clear draft even if no changes to save
      await _clearDraft(entryId);
      return;
    }

    try {
      final service = await ref.read(journalServiceFutureProvider.future);
      final selectedDate = ref.read(selectedJournalDateProvider);

      // Get current journal to find the entry
      final journal = await service.loadDay(selectedDate);
      final entry = journal.entries.firstWhere(
        (e) => e.id == entryId,
        orElse: () => throw Exception('Entry not found'),
      );

      // Create updated entry
      final updatedEntry = entry.copyWith(
        content: newContent ?? entry.content,
        title: newTitle ?? entry.title,
      );

      await service.updateEntry(selectedDate, updatedEntry);
      debugPrint('[JournalScreen] Saved edit for entry $entryId');

      // Clear the draft after successful save
      await _clearDraft(entryId);

      // Show saved indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Text('Saved'),
              ],
            ),
            backgroundColor: BrandColors.forest,
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }

      // Refresh
      ref.invalidate(selectedJournalProvider);
    } catch (e) {
      debugPrint('[JournalScreen] Error saving edit: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: BrandColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _handleContentChanged(String entryId, String newContent) {
    if (_editingEntryId == entryId) {
      _editingEntryContent = newContent;
      // Save draft in background (debounced)
      _saveDraftDebounced(entryId, newContent, _editingEntryTitle);
    }
  }

  void _handleTitleChanged(String entryId, String newTitle) {
    if (_editingEntryId == entryId) {
      _editingEntryTitle = newTitle;
      // Save draft in background (debounced)
      _saveDraftDebounced(entryId, _editingEntryContent, newTitle);
    }
  }

  /// Handle transcription request for an entry
  Future<void> _handleTranscribe(JournalEntry entry, JournalDay journal) async {
    if (_transcribingEntryIds.contains(entry.id)) return;

    // Get the audio path from assets
    final audioPath = journal.getAudioPath(entry.id);
    if (audioPath == null) {
      debugPrint('[JournalScreen] No audio path found for entry ${entry.id}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio file not found'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Mark as transcribing
    setState(() {
      _transcribingEntryIds.add(entry.id);
    });

    debugPrint('[JournalScreen] Starting transcription for entry ${entry.id}');

    try {
      // Get the full audio path
      final fileSystemService = ref.read(fileSystemServiceProvider);
      final vaultPath = await fileSystemService.getRootPath();
      final fullAudioPath = '$vaultPath/$audioPath';

      // Check if file exists
      final audioFile = File(fullAudioPath);
      if (!await audioFile.exists()) {
        throw Exception('Audio file not found at $fullAudioPath');
      }

      // Transcribe
      final postProcessingService = ref.read(recordingPostProcessingProvider);
      final result = await postProcessingService.process(audioPath: fullAudioPath);
      final transcript = result.transcript;

      debugPrint('[JournalScreen] Transcription complete: ${transcript.length} chars');

      if (transcript.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No speech detected in recording'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Update the entry with the transcript
        final service = await ref.read(journalServiceFutureProvider.future);
        final selectedDate = ref.read(selectedJournalDateProvider);
        final updatedEntry = entry.copyWith(content: transcript);
        await service.updateEntry(selectedDate, updatedEntry);

        // Update cache immediately to show the transcription
        if (mounted && _cachedJournal != null) {
          setState(() {
            _cachedJournal = _cachedJournal!.updateEntry(updatedEntry);
          });
        }

        // Refresh the journal provider in background
        ref.invalidate(selectedJournalProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Text('Transcription complete'),
                ],
              ),
              backgroundColor: BrandColors.forest,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[JournalScreen] Transcription failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcription failed: $e'),
            backgroundColor: BrandColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _transcribingEntryIds.remove(entry.id);
        });
      }
    }
  }

  void _showEntryActions(
    BuildContext context,
    JournalDay journal,
    JournalEntry entry,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? BrandColors.charcoal : BrandColors.stone,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),

            // Actions
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('View details'),
              onTap: () {
                Navigator.pop(context);
                _showEntryDetail(context, entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _editingEntryId = entry.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: BrandColors.error),
              title: Text('Delete', style: TextStyle(color: BrandColors.error)),
              onTap: () {
                Navigator.pop(context);
                _deleteEntry(context, journal, entry);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isToday) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isToday ? Icons.wb_sunny_outlined : Icons.history,
              size: 64,
              color: isDark ? BrandColors.driftwood : BrandColors.stone,
            ),
            const SizedBox(height: 16),
            Text(
              isToday ? 'Start your day' : 'No entries',
              style: theme.textTheme.titleLarge?.copyWith(
                color: isDark ? BrandColors.softWhite : BrandColors.charcoal,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isToday
                  ? 'Capture a thought, record a voice note,\nor just write something down.'
                  : 'No journal entries for this day.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: BrandColors.driftwood,
              ),
              textAlign: TextAlign.center,
            ),
            if (!isToday) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () {
                  // Go to today
                  ref.read(selectedJournalDateProvider.notifier).state = DateTime.now();
                },
                icon: const Icon(Icons.today),
                label: const Text('Go to Today'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: BrandColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(
                color: isDark ? BrandColors.softWhite : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: BrandColors.driftwood,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshJournal,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEntryDetail(BuildContext context, JournalEntry entry) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? BrandColors.charcoal : BrandColors.stone,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Type icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getEntryColor(entry.type).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getEntryIcon(entry.type),
                        color: _getEntryColor(entry.type),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title.isNotEmpty ? entry.title : 'Untitled',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: isDark ? BrandColors.softWhite : BrandColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (entry.durationSeconds != null && entry.durationSeconds! > 0)
                            Text(
                              _formatDuration(entry.durationSeconds!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: BrandColors.driftwood,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: BrandColors.driftwood,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Audio player for voice entries
              if (entry.hasAudio)
                _buildAudioPlayer(context, entry, isDark),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.content.isNotEmpty)
                        SelectableText(
                          entry.content,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: isDark ? BrandColors.stone : BrandColors.charcoal,
                            height: 1.6,
                          ),
                        )
                      else if (entry.isLinked && entry.linkedFilePath != null)
                        _buildLinkedFileInfo(context, entry.linkedFilePath!)
                      else
                        Text(
                          'No content',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: BrandColors.driftwood,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioPlayer(BuildContext context, JournalEntry entry, bool isDark) {
    final audioPath = entry.audioPath;
    if (audioPath == null) return const SizedBox.shrink();

    // Use FutureBuilder to resolve the full path
    return FutureBuilder<String>(
      future: _getFullAudioPath(audioPath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Audio not available',
              style: TextStyle(color: BrandColors.driftwood),
            ),
          );
        }

        final fullPath = snapshot.data!;
        final duration = Duration(seconds: entry.durationSeconds ?? 0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: PlaybackControls(
            filePath: fullPath,
            duration: duration,
          ),
        );
      },
    );
  }

  Future<String> _getFullAudioPath(String relativePath) async {
    final fileSystem = FileSystemService();
    final vaultPath = await fileSystem.getRootPath();
    return '$vaultPath/$relativePath';
  }

  Widget _buildLinkedFileInfo(BuildContext context, String filePath) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BrandColors.forestMist.withValues(alpha: isDark ? 0.2 : 1.0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            color: BrandColors.forest,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Linked File',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: BrandColors.forest,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  filePath.split('/').last,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? BrandColors.softWhite : BrandColors.ink,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.open_in_new,
            color: BrandColors.forest,
            size: 20,
          ),
        ],
      ),
    );
  }

  IconData _getEntryIcon(JournalEntryType type) {
    switch (type) {
      case JournalEntryType.voice:
        return Icons.mic;
      case JournalEntryType.linked:
        return Icons.link;
      case JournalEntryType.text:
        return Icons.edit_note;
    }
  }

  Color _getEntryColor(JournalEntryType type) {
    switch (type) {
      case JournalEntryType.voice:
        return BrandColors.turquoise;
      case JournalEntryType.linked:
        return BrandColors.forest;
      case JournalEntryType.text:
        return BrandColors.driftwood;
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '$minutes min ${secs > 0 ? '$secs sec' : ''}';
    }
    return '$secs sec';
  }

  Future<void> _deleteEntry(
    BuildContext context,
    JournalDay journal,
    JournalEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: BrandColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      debugPrint('[JournalScreen] Deleting entry...');

      try {
        final service = await ref.read(journalServiceFutureProvider.future);
        await service.deleteEntry(journal.date, entry.id);
        debugPrint('[JournalScreen] Entry deleted successfully');

        // Refresh to show changes
        ref.invalidate(selectedJournalProvider);
        ref.read(journalRefreshTriggerProvider.notifier).state++;
      } catch (e, st) {
        debugPrint('[JournalScreen] Error deleting entry: $e');
        debugPrint('$st');
      }
    }
  }
}
