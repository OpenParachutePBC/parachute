import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:app/core/providers/feature_flags_provider.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/providers/omi_providers.dart';
import 'package:app/features/recorder/screens/recording_detail_screen.dart';
import 'package:app/features/recorder/screens/simple_recording_screen.dart';
import 'package:app/features/recorder/utils/platform_utils.dart';
import 'package:app/features/settings/screens/settings_screen.dart';
import 'package:app/features/recorder/widgets/recording_card.dart';
import 'package:app/features/recorder/widgets/model_download_banner.dart';
import 'package:app/core/widgets/git_sync_status_indicator.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  List<Recording> _recordings = [];
  bool _isLoading = true;
  bool _isGridView = true; // Toggle between grid and list view

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecordings();

    // Auto-reconnect to Omi device if supported on this platform AND enabled
    if (PlatformUtils.shouldShowOmiFeatures) {
      _attemptAutoReconnectIfEnabled();
    }
  }

  /// Check if Omi is enabled before attempting auto-reconnect
  Future<void> _attemptAutoReconnectIfEnabled() async {
    final omiEnabled = await ref.read(omiEnabledProvider.future);
    if (omiEnabled) {
      _attemptAutoReconnect();
    }
  }

  /// Attempt to auto-reconnect to the last paired Omi device
  Future<void> _attemptAutoReconnect() async {
    try {
      // Check if auto-reconnect is enabled
      final autoReconnectEnabled = await ref.read(
        autoReconnectEnabledProvider.future,
      );
      if (!autoReconnectEnabled) {
        debugPrint('[HomeScreen] Auto-reconnect is disabled');
        return;
      }

      // Get last paired device
      final lastDevice = await ref.read(lastPairedDeviceProvider.future);
      if (lastDevice == null) {
        debugPrint('[HomeScreen] No previously paired device found');
        return;
      }

      debugPrint(
        '[HomeScreen] Attempting auto-reconnect to: ${lastDevice.name} (${lastDevice.id})',
      );

      // Attempt reconnection
      final bluetoothService = ref.read(omiBluetoothServiceProvider);
      final connection = await bluetoothService.reconnectToDevice(
        lastDevice.id,
      );

      if (connection != null) {
        debugPrint('[HomeScreen] ✅ Auto-reconnect successful!');

        // Start listening for button events
        final captureService = ref.read(omiCaptureServiceProvider);
        await captureService.startListening();
      } else {
        debugPrint('[HomeScreen] ⚠️ Auto-reconnect failed - device not found');
      }
    } catch (e) {
      debugPrint('[HomeScreen] Auto-reconnect error: $e');
      // Don't show error to user - auto-reconnect failure is non-critical
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

    // Refresh when screen gains focus
    if (ModalRoute.of(context)?.isCurrent == true) {
      _refreshRecordings();
    }
  }

  Future<void> _loadRecordings() async {
    final storageService = ref.read(storageServiceProvider);
    final recordings = await storageService.getRecordings();
    if (mounted) {
      setState(() {
        _recordings = recordings;
        _isLoading = false;
      });
    }
  }

  void _refreshRecordings() {
    setState(() {
      _isLoading = true;
    });
    _loadRecordings();
  }

  Future<void> _startRecording() async {
    // Use new simple recording screen with manual pause/resume
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SimpleRecordingScreen()),
    );
    // Always refresh when returning from recording flow
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

  /// Build Omi device connection status indicator
  Widget _buildOmiConnectionIndicator() {
    final connectedDeviceAsync = ref.watch(connectedOmiDeviceProvider);
    final connectedDevice = connectedDeviceAsync.value;
    final isConnected = connectedDevice != null;

    return IconButton(
      icon: Icon(
        isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
        color: isConnected ? Colors.green : Colors.grey,
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
    // Watch for recordings refresh trigger (e.g., from Omi recordings)
    ref.listen(recordingsRefreshTriggerProvider, (previous, next) {
      if (previous != next && mounted) {
        debugPrint('[HomeScreen] Recordings refresh triggered');
        _refreshRecordings();
      }
    });

    // Check if Omi is enabled
    final omiEnabledAsync = ref.watch(omiEnabledProvider);
    final omiEnabled = omiEnabledAsync.value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        elevation: 0,
        actions: [
          // View toggle (grid/list)
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
            tooltip: _isGridView ? 'List view' : 'Grid view',
          ),
          // Git sync status indicator
          const GitSyncStatusIndicator(),
          // Omi device connection indicator (only if platform supports AND feature enabled)
          if (PlatformUtils.shouldShowOmiFeatures && omiEnabled) ...[
            _buildOmiConnectionIndicator(),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.settings),
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
          // Model download banner (shows when downloading)
          const ModelDownloadBanner(),

          // Main content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _recordings.isEmpty
                ? _buildEmptyState()
                : _isGridView
                ? _buildRecordingsGrid()
                : _buildRecordingsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startRecording,
        child: const Icon(Icons.mic),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mic_none,
            size: 80,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No recordings yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the microphone button to start recording',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingsGrid() {
    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      padding: const EdgeInsets.all(12),
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
      padding: const EdgeInsets.all(12),
      itemCount: _recordings.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
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
