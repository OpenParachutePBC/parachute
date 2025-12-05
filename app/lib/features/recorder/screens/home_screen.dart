import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:app/core/providers/feature_flags_provider.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/providers/omi_providers.dart';
import 'package:app/features/recorder/screens/recording_detail_screen.dart';
import 'package:app/features/recorder/screens/simple_recording_screen.dart';
import 'package:app/features/recorder/utils/platform_utils.dart';
import 'package:app/features/settings/screens/settings_screen.dart';
import 'package:app/features/recorder/widgets/recording_card.dart';
import 'package:app/features/recorder/widgets/model_download_banner.dart';
import 'package:app/features/search/screens/search_debug_screen.dart';

/// Home screen for Parachute - voice capture hub
///
/// "Think naturally" - A calm space to capture and review your thoughts.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  List<Recording> _recordings = [];
  bool _isLoading = true;
  bool _isGridView = true;
  bool _showOrphaned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecordings();
    _startFilesystemWatcher();

    if (PlatformUtils.shouldShowOmiFeatures) {
      _attemptAutoReconnectIfEnabled();
    }
  }

  Future<void> _startFilesystemWatcher() async {
    final storageService = ref.read(storageServiceProvider);
    await storageService.startWatchingFilesystem(
      onChange: () {
        if (mounted) {
          debugPrint(
            '[HomeScreen] External filesystem change detected, refreshing...',
          );
          _refreshRecordings();
        }
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(storageServiceProvider).stopWatchingFilesystem();
    super.dispose();
  }

  Future<void> _attemptAutoReconnectIfEnabled() async {
    final omiEnabled = await ref.read(omiEnabledProvider.future);
    if (omiEnabled) {
      _attemptAutoReconnect();
    }
  }

  Future<void> _attemptAutoReconnect() async {
    try {
      final autoReconnectEnabled = await ref.read(
        autoReconnectEnabledProvider.future,
      );
      if (!autoReconnectEnabled) {
        debugPrint('[HomeScreen] Auto-reconnect is disabled');
        return;
      }

      final lastDevice = await ref.read(lastPairedDeviceProvider.future);
      if (lastDevice == null) {
        debugPrint('[HomeScreen] No previously paired device found');
        return;
      }

      debugPrint(
        '[HomeScreen] Attempting auto-reconnect to: ${lastDevice.name} (${lastDevice.id})',
      );

      final bluetoothService = ref.read(omiBluetoothServiceProvider);
      final connection = await bluetoothService.reconnectToDevice(
        lastDevice.id,
      );

      if (connection != null) {
        debugPrint('[HomeScreen] Auto-reconnect successful!');
        final captureService = ref.read(omiCaptureServiceProvider);
        await captureService.startListening();
      } else {
        debugPrint('[HomeScreen] Auto-reconnect failed - device not found');
      }
    } catch (e) {
      debugPrint('[HomeScreen] Auto-reconnect error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshRecordings();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == true) {
      _refreshRecordings();
    }
  }

  Future<void> _loadRecordings() async {
    final storageService = ref.read(storageServiceProvider);
    final recordings = await storageService.getRecordings(
      includeOrphaned: _showOrphaned,
    );
    if (mounted) {
      setState(() {
        _recordings = recordings;
        _isLoading = false;
      });
    }
  }

  void _refreshRecordings({bool forceRefresh = false}) {
    if (forceRefresh) {
      ref.read(storageServiceProvider).forceRefresh();
    }
    setState(() {
      _isLoading = true;
    });
    _loadRecordings();
  }

  Future<void> _startRecording() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SimpleRecordingScreen()),
    );
    _refreshRecordings();
  }

  void _openRecordingDetail(Recording recording) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => RecordingDetailScreen(recording: recording),
          ),
        )
        .then((_) => _refreshRecordings());
  }

  Widget _buildOmiConnectionIndicator() {
    final connectedDeviceAsync = ref.watch(connectedOmiDeviceProvider);
    final connectedDevice = connectedDeviceAsync.value;
    final isConnected = connectedDevice != null;

    return IconButton(
      icon: Icon(
        isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
        color: isConnected ? BrandColors.success : BrandColors.driftwood,
        size: 20,
      ),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
      },
      tooltip: isConnected
          ? 'Omi: ${connectedDevice.name}'
          : 'Omi: Not connected',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(recordingsRefreshTriggerProvider, (previous, next) {
      if (previous != next && mounted) {
        debugPrint('[HomeScreen] Recordings refresh triggered');
        _refreshRecordings();
      }
    });

    final omiEnabledAsync = ref.watch(omiEnabledProvider);
    final omiEnabled = omiEnabledAsync.value ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      appBar: AppBar(
        title: const Text('Notes'),
        elevation: 0,
        actions: [
          // Search button (debug)
          IconButton(
            icon: Icon(
              Icons.search,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SearchDebugScreen(),
                ),
              );
            },
            tooltip: 'Search (Debug)',
          ),
          // Refresh button
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
            onPressed: _isLoading
                ? null
                : () => _refreshRecordings(forceRefresh: true),
            tooltip: 'Refresh',
          ),
          // View toggle
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_agenda_outlined : Icons.grid_view,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
            tooltip: _isGridView ? 'List view' : 'Grid view',
          ),
          // More options
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            onSelected: (value) {
              if (value == 'toggle_orphaned') {
                setState(() {
                  _showOrphaned = !_showOrphaned;
                });
                _refreshRecordings();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_orphaned',
                child: Row(
                  children: [
                    Icon(
                      _showOrphaned
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                      color: BrandColors.forest,
                    ),
                    SizedBox(width: Spacing.md),
                    const Text('Show failed transcriptions'),
                  ],
                ),
              ),
            ],
          ),
          // Omi indicator
          if (PlatformUtils.shouldShowOmiFeatures && omiEnabled) ...[
            _buildOmiConnectionIndicator(),
            SizedBox(width: Spacing.sm),
          ],
          // Settings
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          const ModelDownloadBanner(),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: BrandColors.turquoise,
                      strokeWidth: 2,
                    ),
                  )
                : _recordings.isEmpty
                ? _buildEmptyState(isDark)
                : _isGridView
                ? _buildRecordingsGrid()
                : _buildRecordingsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startRecording,
        elevation: Elevation.medium,
        child: const Icon(Icons.mic),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Gentle icon with breathing room
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.forestDeep.withValues(alpha: 0.3)
                    : BrandColors.forestMist.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mic_none_rounded,
                size: 56,
                color: isDark
                    ? BrandColors.nightForest.withValues(alpha: 0.7)
                    : BrandColors.forest.withValues(alpha: 0.5),
              ),
            ),
            SizedBox(height: Spacing.xxl),
            Text(
              'Capture your thoughts',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: isDark
                    ? BrandColors.nightText.withValues(alpha: 0.8)
                    : BrandColors.charcoal.withValues(alpha: 0.8),
              ),
            ),
            SizedBox(height: Spacing.sm),
            Text(
              'Tap the microphone to start recording',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingsGrid() {
    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: Spacing.md,
      crossAxisSpacing: Spacing.md,
      padding: EdgeInsets.all(Spacing.lg),
      itemCount: _recordings.length,
      itemBuilder: (context, index) {
        final recording = _recordings[index];
        return RecordingCard(
          recording: recording,
          onTap: () => _openRecordingDetail(recording),
          onDeleted: _refreshRecordings,
        );
      },
    );
  }

  Widget _buildRecordingsList() {
    return ListView.separated(
      padding: EdgeInsets.all(Spacing.lg),
      itemCount: _recordings.length,
      separatorBuilder: (context, index) => SizedBox(height: Spacing.md),
      itemBuilder: (context, index) {
        final recording = _recordings[index];
        return RecordingCard(
          recording: recording,
          onTap: () => _openRecordingDetail(recording),
          onDeleted: _refreshRecordings,
        );
      },
    );
  }
}
