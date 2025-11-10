import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:app/core/models/title_generation_models.dart';
import 'package:app/core/providers/title_generation_provider.dart';
import 'package:app/core/providers/feature_flags_provider.dart';
import 'package:app/core/providers/backend_health_provider.dart';
import 'package:app/core/widgets/gemma_model_download_card.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/features/recorder/models/whisper_models.dart';
import 'package:app/features/recorder/providers/omi_providers.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/screens/device_pairing_screen.dart';
import 'package:app/features/recorder/utils/platform_utils.dart';
import 'package:app/features/recorder/widgets/whisper_model_download_card.dart';
import 'package:app/features/settings/widgets/git_sync_settings_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _geminiApiKeyController = TextEditingController();
  final TextEditingController _huggingFaceTokenController =
      TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _obscureApiKey = true;
  bool _obscureGeminiApiKey = true;
  bool _obscureHuggingFaceToken = true;
  bool _hasApiKey = false;
  bool _hasGeminiApiKey = false;
  bool _hasHuggingFaceToken = false;
  String _syncFolderPath = '';

  // Local Whisper settings
  TranscriptionMode _transcriptionMode = TranscriptionMode.api;
  WhisperModelType _preferredModel = WhisperModelType.base;
  bool _autoTranscribe = false;
  bool _autoPauseRecording = false;
  bool _audioDebugOverlay = false;
  String _storageInfo = '0 MB used';

  // Title Generation settings
  TitleModelMode _titleMode = TitleModelMode.api;
  GemmaModelType _preferredGemmaModel = GemmaModelType.gemma1b;
  String _gemmaStorageInfo = '0 MB used';

  // Feature toggles
  bool _omiEnabled = false;
  bool _aiChatEnabled = false;
  String _aiServerUrl = 'http://localhost:8080';
  final TextEditingController _aiServerUrlController = TextEditingController();

  // Subfolder names
  String _capturesFolderName = 'captures';
  String _spacesFolderName = 'spaces';
  final TextEditingController _capturesFolderNameController =
      TextEditingController();
  final TextEditingController _spacesFolderNameController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _geminiApiKeyController.dispose();
    _huggingFaceTokenController.dispose();
    _aiServerUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    setState(() => _isLoading = true);

    final storageService = ref.read(storageServiceProvider);

    // Load OpenAI API key
    final apiKey = await storageService.getOpenAIApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      _apiKeyController.text = apiKey;
      _hasApiKey = true;
    }

    // Load Gemini API key
    final geminiApiKey = await storageService.getGeminiApiKey();
    if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
      _geminiApiKeyController.text = geminiApiKey;
      _hasGeminiApiKey = true;
    }

    // Load HuggingFace token
    final huggingFaceToken = await storageService.getHuggingFaceToken();
    if (huggingFaceToken != null && huggingFaceToken.isNotEmpty) {
      _huggingFaceTokenController.text = huggingFaceToken;
      _hasHuggingFaceToken = true;
    }

    // Load Parachute folder path and subfolder names
    final fileSystemService = FileSystemService();
    await fileSystemService.initialize(); // Ensure it's initialized
    _syncFolderPath = await fileSystemService.getRootPathDisplay();
    _capturesFolderName = fileSystemService.getCapturesFolderName();
    _spacesFolderName = fileSystemService.getSpacesFolderName();
    _capturesFolderNameController.text = _capturesFolderName;
    _spacesFolderNameController.text = _spacesFolderName;

    // Load feature toggles
    final featureFlagsService = ref.read(featureFlagsServiceProvider);
    _omiEnabled = await featureFlagsService.isOmiEnabled();
    _aiChatEnabled = await featureFlagsService.isAiChatEnabled();
    _aiServerUrl = await featureFlagsService.getAiServerUrl();
    _aiServerUrlController.text = _aiServerUrl;

    // Load local whisper settings
    await _loadLocalWhisperSettings();

    setState(() => _isLoading = false);
  }

  Future<void> _loadLocalWhisperSettings() async {
    final storageService = ref.read(storageServiceProvider);
    final modelManager = ref.read(whisperModelManagerProvider);

    // Load transcription mode
    final modeString = await storageService.getTranscriptionMode();
    _transcriptionMode =
        TranscriptionMode.fromString(modeString) ?? TranscriptionMode.api;

    // Load preferred model
    final modelString = await storageService.getPreferredWhisperModel();
    _preferredModel =
        WhisperModelType.fromString(modelString ?? 'base') ??
        WhisperModelType.base;

    // Load auto-transcribe setting
    _autoTranscribe = await storageService.getAutoTranscribe();

    // Load auto-pause recording setting
    _autoPauseRecording = await storageService.getAutoPauseRecording();

    // Load audio debug overlay setting
    _audioDebugOverlay = await storageService.getAudioDebugOverlay();

    // Load storage info
    _storageInfo = await modelManager.getStorageInfo();

    // Load Title Generation settings
    await _loadTitleGenerationSettings();
  }

  Future<void> _loadTitleGenerationSettings() async {
    final storageService = ref.read(storageServiceProvider);
    final gemmaManager = ref.read(gemmaModelManagerProvider);

    // Load title generation mode
    final modeString = await storageService.getTitleGenerationMode();
    _titleMode = TitleModelMode.fromString(modeString) ?? TitleModelMode.api;

    // Load preferred Gemma model
    final modelString = await storageService.getPreferredGemmaModel();
    _preferredGemmaModel =
        GemmaModelType.fromString(modelString ?? 'gemma-3-1b') ??
        GemmaModelType.gemma1b;

    // Load storage info
    _gemmaStorageInfo = await gemmaManager.getStorageInfo();
  }

  Future<void> _saveApiKey() async {
    final apiKey = _apiKeyController.text.trim();

    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an API key'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Basic validation: OpenAI keys start with 'sk-'
    if (!apiKey.startsWith('sk-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid API key format. OpenAI keys start with "sk-"'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final success = await ref
        .read(storageServiceProvider)
        .saveOpenAIApiKey(apiKey);

    setState(() => _isSaving = false);

    if (success) {
      setState(() => _hasApiKey = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API key saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save API key'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteApiKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete API Key?'),
        content: const Text(
          'Are you sure you want to remove your OpenAI API key? '
          'You won\'t be able to use transcription until you add a new key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref
          .read(storageServiceProvider)
          .deleteOpenAIApiKey();
      if (success) {
        _apiKeyController.clear();
        setState(() => _hasApiKey = false);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('API key deleted')));
        }
      }
    }
  }

  Future<void> _saveGeminiApiKey() async {
    final apiKey = _geminiApiKeyController.text.trim();

    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a Gemini API key'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final success = await ref
        .read(storageServiceProvider)
        .saveGeminiApiKey(apiKey);

    setState(() => _isSaving = false);

    if (success) {
      setState(() => _hasGeminiApiKey = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gemini API key saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save Gemini API key'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteGeminiApiKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Gemini API Key?'),
        content: const Text(
          'Are you sure you want to remove your Gemini API key? '
          'Title generation will fall back to simple extraction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref
          .read(storageServiceProvider)
          .deleteGeminiApiKey();
      if (success) {
        _geminiApiKeyController.clear();
        setState(() => _hasGeminiApiKey = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gemini API key deleted')),
          );
        }
      }
    }
  }

  Future<void> _saveHuggingFaceToken() async {
    final token = _huggingFaceTokenController.text.trim();

    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a HuggingFace token'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final success = await ref
          .read(storageServiceProvider)
          .saveHuggingFaceToken(token);

      if (success) {
        setState(() => _hasHuggingFaceToken = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('HuggingFace token saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteHuggingFaceToken() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete HuggingFace Token?'),
        content: const Text(
          'Are you sure you want to remove your HuggingFace token? '
          'You will not be able to download Gemma models until you add a new token.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref
          .read(storageServiceProvider)
          .deleteHuggingFaceToken();
      if (success) {
        _huggingFaceTokenController.clear();
        setState(() => _hasHuggingFaceToken = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('HuggingFace token deleted')),
          );
        }
      }
    }
  }

  Future<void> _openApiKeyHelp() async {
    final url = Uri.parse('https://platform.openai.com/api-keys');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openParachuteFolder() async {
    try {
      final fileSystemService = FileSystemService();
      final folderPath = await fileSystemService.getRootPath();

      // Use url_launcher to open the folder in the system's file manager
      final uri = Uri.file(folderPath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open folder'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSubfolderNames() async {
    final newCapturesName = _capturesFolderNameController.text.trim();
    final newSpacesName = _spacesFolderNameController.text.trim();

    // Validate folder names
    if (newCapturesName.isEmpty || newSpacesName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder names cannot be empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (newCapturesName.contains('/') || newSpacesName.contains('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder names cannot contain slashes'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (newCapturesName == newSpacesName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder names must be different'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final fileSystemService = FileSystemService();
      final success = await fileSystemService.setSubfolderNames(
        capturesFolderName: newCapturesName,
        spacesFolderName: newSpacesName,
      );

      if (success && mounted) {
        setState(() {
          _capturesFolderName = newCapturesName;
          _spacesFolderName = newSpacesName;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subfolder names updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update subfolder names'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _chooseSyncFolder() async {
    // Show warning dialog first
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Parachute Folder'),
        content: const Text(
          'Changing the folder location will move all your recordings, transcripts, '
          'and AI spaces to the new location. This may take a while.\n\n'
          'Make sure you have enough space in the new location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final fileSystemService = FileSystemService();
      final success = await fileSystemService.setRootPath(selectedDirectory);

      if (success) {
        final displayPath = await fileSystemService.getRootPathDisplay();
        setState(() => _syncFolderPath = displayPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Parachute folder updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update Parachute folder'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _setTranscriptionMode(TranscriptionMode mode) async {
    await ref.read(storageServiceProvider).setTranscriptionMode(mode.name);
    setState(() => _transcriptionMode = mode);
  }

  Future<void> _setPreferredModel(WhisperModelType model) async {
    await ref
        .read(storageServiceProvider)
        .setPreferredWhisperModel(model.modelName);
    setState(() => _preferredModel = model);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${model.displayName} model set as active'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _setAutoTranscribe(bool enabled) async {
    await ref.read(storageServiceProvider).setAutoTranscribe(enabled);
    setState(() => _autoTranscribe = enabled);
  }

  Future<void> _setAutoPauseRecording(bool enabled) async {
    await ref.read(storageServiceProvider).setAutoPauseRecording(enabled);
    setState(() => _autoPauseRecording = enabled);
  }

  Future<void> _setAudioDebugOverlay(bool enabled) async {
    await ref.read(storageServiceProvider).setAudioDebugOverlay(enabled);
    setState(() => _audioDebugOverlay = enabled);
  }

  Future<void> _refreshWhisperStorage() async {
    final modelManager = ref.read(whisperModelManagerProvider);
    final newStorageInfo = await modelManager.getStorageInfo();
    if (mounted) {
      setState(() => _storageInfo = newStorageInfo);
    }
  }

  Future<void> _refreshGemmaStorage() async {
    final gemmaManager = ref.read(gemmaModelManagerProvider);
    final newStorageInfo = await gemmaManager.getStorageInfo();
    if (mounted) {
      setState(() => _gemmaStorageInfo = newStorageInfo);
    }
  }

  Future<void> _setTitleMode(TitleModelMode mode) async {
    await ref.read(storageServiceProvider).setTitleGenerationMode(mode.name);
    setState(() => _titleMode = mode);
  }

  Future<void> _setPreferredGemmaModel(GemmaModelType model) async {
    await ref
        .read(storageServiceProvider)
        .setPreferredGemmaModel(model.modelName);
    setState(() => _preferredGemmaModel = model);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${model.displayName} model set as active'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Feature toggle methods
  Future<void> _setOmiEnabled(bool enabled) async {
    final featureFlagsService = ref.read(featureFlagsServiceProvider);
    await featureFlagsService.setOmiEnabled(enabled);
    setState(() => _omiEnabled = enabled);

    // Invalidate the provider to update the UI
    ref.invalidate(omiEnabledNotifierProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Omi device integration enabled'
                : 'Omi device integration disabled',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _setAiChatEnabled(bool enabled) async {
    final featureFlagsService = ref.read(featureFlagsServiceProvider);
    await featureFlagsService.setAiChatEnabled(enabled);
    setState(() => _aiChatEnabled = enabled);

    // Invalidate the provider to update the navigation
    ref.invalidate(aiChatEnabledNotifierProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'AI Chat enabled - restart app to see changes'
                : 'AI Chat disabled - restart app to see changes',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _setAiServerUrl(String url) async {
    final featureFlagsService = ref.read(featureFlagsServiceProvider);
    await featureFlagsService.setAiServerUrl(url);
    setState(() => _aiServerUrl = url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI server URL updated'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildServerStatusIndicator() {
    final healthAsync = ref.watch(serverHealthProvider(_aiServerUrl));

    return healthAsync.when(
      data: (health) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: health.isHealthy
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: health.isHealthy ? Colors.green : Colors.red,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                health.isHealthy ? Icons.check_circle : Icons.error,
                color: health.isHealthy ? Colors.green[700] : Colors.red[700],
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      health.isHealthy
                          ? 'Server Connected'
                          : 'Server Unavailable',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: health.isHealthy
                            ? Colors.green[900]
                            : Colors.red[900],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      health.displayMessage,
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue, width: 1),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Checking server status...',
              style: TextStyle(fontSize: 12, color: Colors.blue[700]),
            ),
          ],
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange[700], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Error checking server: $error',
                style: TextStyle(fontSize: 11, color: Colors.orange[900]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOmiDeviceCard() {
    final connectedDeviceAsync = ref.watch(connectedOmiDeviceProvider);
    final connectedDevice = connectedDeviceAsync.value;
    final firmwareService = ref.watch(omiFirmwareServiceProvider);
    final isConnected = connectedDevice != null;
    final batteryLevelAsync = ref.watch(omiBatteryLevelProvider);
    final batteryLevel = batteryLevelAsync.valueOrNull ?? -1;

    // If firmware update is in progress, show that status instead of connection state
    final isFirmwareUpdating = firmwareService.isUpdating;
    final displayConnected = isConnected || isFirmwareUpdating;

    return InkWell(
      onTap: isFirmwareUpdating
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DevicePairingScreen(),
                ),
              );
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: displayConnected
              ? (isFirmwareUpdating
                    ? Colors.blue.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1))
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: displayConnected
                ? (isFirmwareUpdating ? Colors.blue : Colors.green)
                : Colors.grey,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isFirmwareUpdating
                  ? Icons.system_update_alt
                  : (isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
              color: displayConnected
                  ? (isFirmwareUpdating ? Colors.blue : Colors.green)
                  : Colors.grey[600],
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFirmwareUpdating
                        ? 'Updating Firmware'
                        : (isConnected ? 'Connected' : 'Not Connected'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: displayConnected
                          ? (isFirmwareUpdating ? Colors.blue : Colors.green)
                          : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isFirmwareUpdating
                        ? firmwareService.updateStatus
                        : (isConnected
                              ? connectedDevice.name
                              : 'Tap to pair your device'),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (isConnected &&
                      connectedDevice.firmwareRevision != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Firmware: ${connectedDevice.firmwareRevision}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                  if (isConnected && batteryLevel >= 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _getBatteryIcon(batteryLevel),
                          size: 14,
                          color: _getBatteryColor(batteryLevel),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Battery: $batteryLevel%',
                          style: TextStyle(
                            fontSize: 11,
                            color: _getBatteryColor(batteryLevel),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildFirmwareUpdateCard() {
    final connectedDeviceAsync = ref.watch(connectedOmiDeviceProvider);
    final connectedDevice = connectedDeviceAsync.value;
    final isConnected = connectedDevice != null;
    final firmwareService = ref.watch(omiFirmwareServiceProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.system_update, color: Colors.blue[700], size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Firmware Update',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue[900],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isConnected
                          ? 'Update your device firmware over-the-air'
                          : 'Connect a device to check for updates',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (isConnected) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Latest: ${firmwareService.getLatestFirmwareVersion()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (isConnected) ...[
            const SizedBox(height: 16),
            if (firmwareService.isUpdating) ...[
              Column(
                children: [
                  LinearProgressIndicator(
                    value: firmwareService.updateProgress / 100,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    firmwareService.updateStatus,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Progress: ${firmwareService.updateProgress}%',
                    style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red[700], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'DO NOT close this app or disconnect your device!\nClosing the app during update may brick your device.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red[900],
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _checkFirmwareUpdate();
                      },
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Check for Updates'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  IconData _getBatteryIcon(int level) {
    if (level > 90) return Icons.battery_full;
    if (level > 60) return Icons.battery_5_bar;
    if (level > 40) return Icons.battery_4_bar;
    if (level > 20) return Icons.battery_2_bar;
    return Icons.battery_1_bar;
  }

  Color _getBatteryColor(int level) {
    if (level > 20) return Colors.green;
    if (level > 10) return Colors.orange;
    return Colors.red;
  }

  Future<void> _checkFirmwareUpdate() async {
    final connectedDeviceAsync = ref.read(connectedOmiDeviceProvider);
    final connectedDevice = connectedDeviceAsync.value;

    if (connectedDevice == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No device connected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final firmwareService = ref.read(omiFirmwareServiceProvider);

    try {
      // Check if update is available
      final updateAvailable = await firmwareService.isUpdateAvailable(
        connectedDevice,
      );

      if (!updateAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your device is already up to date!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }

      // Show confirmation dialog
      if (mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Firmware Update Available'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current version: ${connectedDevice.firmwareRevision ?? "Unknown"}',
                ),
                Text(
                  'Latest version: ${firmwareService.getLatestFirmwareVersion()}',
                ),
                const SizedBox(height: 16),
                const Text(
                  'This update will:\n'
                  '• Improve device performance\n'
                  '• Fix bugs and issues\n'
                  '• Add new features',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Keep your device nearby and do not disconnect during the update process (2-5 minutes).',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Update Now'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
      }

      // Start firmware update
      await firmwareService.startFirmwareUpdate(
        device: connectedDevice,
        onProgress: (progress) {
          setState(() {}); // Trigger rebuild to show progress
        },
        onComplete: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Firmware update completed successfully! Device will reboot.',
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 5),
              ),
            );
          }
        },
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Firmware update failed: $error'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking for updates: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firmwareService = ref.watch(omiFirmwareServiceProvider);
    final isFirmwareUpdating = firmwareService.isUpdating;

    return PopScope(
      canPop: !isFirmwareUpdating,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // Show warning if user tries to navigate away during firmware update
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Cannot navigate away during firmware update! '
              'Interrupting the update may brick your device.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings'), centerTitle: true),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // === DEVICE INTEGRATION SECTION ===
                  if (PlatformUtils.shouldShowOmiFeatures) ...[
                    const Text(
                      '🎧 Device Integration',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connect Bluetooth devices like Omi wearables',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 16),

                    // Omi Enable Toggle
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _omiEnabled
                            ? Colors.blue.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _omiEnabled ? Colors.blue : Colors.grey,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bluetooth,
                            color: _omiEnabled
                                ? Colors.blue[700]
                                : Colors.grey[600],
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Enable Omi Device',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _omiEnabled
                                      ? 'Omi device support is enabled'
                                      : 'Enable to connect Omi wearable',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _omiEnabled,
                            onChanged: _setOmiEnabled,
                            activeColor: Colors.blue,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 32),
                  ],

                  // === AI CHAT SERVER SECTION ===
                  const Text(
                    '💬 AI Chat Server',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enable AI conversations with Claude (requires backend server)',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 16),

                  // AI Chat Enable Toggle
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _aiChatEnabled
                          ? Colors.purple.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _aiChatEnabled ? Colors.purple : Colors.grey,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.chat_bubble,
                              color: _aiChatEnabled
                                  ? Colors.purple[700]
                                  : Colors.grey[600],
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Enable AI Chat',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _aiChatEnabled
                                        ? 'AI Chat tab is visible'
                                        : 'Enable to show AI Chat tab',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _aiChatEnabled,
                              onChanged: _setAiChatEnabled,
                              activeColor: Colors.purple,
                            ),
                          ],
                        ),

                        // Server URL input (shown when enabled)
                        if (_aiChatEnabled) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _aiServerUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Server URL',
                              hintText: 'http://localhost:8080',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.link),
                            ),
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    _setAiServerUrl(
                                      _aiServerUrlController.text.trim(),
                                    );
                                  },
                                  icon: const Icon(Icons.save),
                                  label: const Text('Save Server URL'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  // Trigger health check by invalidating provider
                                  ref.invalidate(
                                    serverHealthProvider(_aiServerUrl),
                                  );
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Test'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Server Status Indicator
                          _buildServerStatusIndicator(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 32),

                  // === STORAGE SECTION ===
                  const Text(
                    '📁 Storage',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Parachute Folder Section
                  const Text(
                    'Parachute Folder',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All your recordings, transcripts, and AI spaces are stored here. '
                    'Choose a location you can sync with iCloud, Syncthing, Dropbox, etc.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.folder_open, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            const Text(
                              'Current folder',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _syncFolderPath,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _chooseSyncFolder,
                                icon: const Icon(Icons.folder, size: 18),
                                label: const Text('Change Location'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _openParachuteFolder,
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('Open'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[700],
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Subfolder Names Section
                  const Text(
                    'Subfolder Names',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Customize folder names to work with Obsidian, Logseq, or any markdown-based vault',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade400, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.folder_special, color: Colors.grey[700]),
                            const SizedBox(width: 8),
                            const Text(
                              'Recordings folder name',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _capturesFolderNameController,
                          decoration: InputDecoration(
                            hintText: 'e.g., captures, notes, recordings',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            prefixIcon: const Icon(Icons.mic, size: 18),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              color: Colors.grey[700],
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'AI spaces folder name',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _spacesFolderNameController,
                          decoration: InputDecoration(
                            hintText: 'e.g., spaces, ai-chats, conversations',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            prefixIcon: const Icon(Icons.chat_bubble, size: 18),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  // Reset to defaults
                                  _capturesFolderNameController.text =
                                      'captures';
                                  _spacesFolderNameController.text = 'spaces';
                                },
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Reset to Defaults'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _saveSubfolderNames,
                                icon: const Icon(Icons.save, size: 18),
                                label: const Text('Save Names'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.blue[700],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Example: Use "Parachute Captures" and "Parachute Spaces" '
                                  'to avoid conflicts with your existing note folders',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 32),

                  // Git Sync Section
                  const Text(
                    'Git Sync',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const GitSyncSettingsCard(),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 32),

                  // Omi Device Section (only show if enabled)
                  if (PlatformUtils.shouldShowOmiFeatures && _omiEnabled) ...[
                    const Text(
                      'Omi Device Pairing',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connect your Omi wearable device to record with a button tap',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    _buildOmiDeviceCard(),
                    const SizedBox(height: 16),
                    _buildFirmwareUpdateCard(),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 32),
                  ],

                  // Transcription Settings Header
                  const Text(
                    'Transcription',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),

                  // Transcription Mode Selector
                  const Text(
                    'Transcription Mode',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose how to transcribe your recordings',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 16),

                  // Mode selector cards
                  Row(
                    children: [
                      Expanded(child: _buildModeCard(TranscriptionMode.api)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildModeCard(TranscriptionMode.local)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Auto-transcribe toggle
                  SwitchListTile(
                    title: const Text('Auto-transcribe recordings'),
                    subtitle: const Text(
                      'Automatically transcribe after recording stops',
                    ),
                    value: _autoTranscribe,
                    onChanged: _setAutoTranscribe,
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),

                  // Auto-pause toggle (VAD-based chunking)
                  SwitchListTile(
                    title: const Text('Auto-pause recording'),
                    subtitle: const Text(
                      'Automatically detect silence and segment recordings',
                    ),
                    value: _autoPauseRecording,
                    onChanged: _setAutoPauseRecording,
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                  ),

                  const SizedBox(height: 16),

                  // Audio debug overlay toggle
                  SwitchListTile(
                    title: const Text('Audio debug overlay'),
                    subtitle: const Text(
                      'Show real-time audio levels and noise filtering graph',
                    ),
                    value: _audioDebugOverlay,
                    onChanged: _setAudioDebugOverlay,
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                  ),

                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 32),

                  // Local Whisper Models Section (only show if local mode selected)
                  if (_transcriptionMode == TranscriptionMode.local) ...[
                    const Text(
                      'Local Whisper Models',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Download models for offline transcription. Smaller models are faster but less accurate.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 16),

                    // Storage info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.storage, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          Text(
                            'Storage: $_storageInfo',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Model cards
                    ...WhisperModelType.values.map(
                      (model) => WhisperModelDownloadCard(
                        modelType: model,
                        isPreferred: model == _preferredModel,
                        onSetPreferred: () => _setPreferredModel(model),
                        onDownloadComplete: () => _refreshWhisperStorage(),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 32),
                  ],

                  // Title Generation Settings Header
                  const Text(
                    'Title Generation',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),

                  // Title Generation Mode Selector
                  const Text(
                    'Title Generation Mode',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose how to generate titles for your recordings',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 16),

                  // Mode selector cards
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildTitleModeCard(TitleModelMode.api),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTitleModeCard(TitleModelMode.local),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildTitleModeCard(TitleModelMode.disabled),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 32),

                  // Local Gemma Models Section (only show if local mode selected)
                  if (_titleMode == TitleModelMode.local) ...[
                    const Text(
                      'Local Gemma Models',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Download models for offline title generation. Smaller models are faster but may be less creative.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 16),

                    // Storage info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.storage, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          Text(
                            'Storage: $_gemmaStorageInfo',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Model cards
                    ...GemmaModelType.values.map(
                      (model) => GemmaModelDownloadCard(
                        modelType: model,
                        isPreferred: model == _preferredGemmaModel,
                        onSetPreferred: () => _setPreferredGemmaModel(model),
                        onDownloadComplete: () => _refreshGemmaStorage(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // HuggingFace Token Section
                    const Text(
                      'HuggingFace Token',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Required for downloading Gemma models. You must:',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.blue[700],
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Setup Steps:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[900],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '1. Create a HuggingFace account (free)\n'
                            '2. Accept the license for each Gemma model\n'
                            '3. Generate a read-only access token\n'
                            '4. Paste the token below',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // HuggingFace Token Input
                    TextField(
                      controller: _huggingFaceTokenController,
                      decoration: InputDecoration(
                        labelText: 'HuggingFace Token',
                        hintText: 'hf_...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureHuggingFaceToken
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureHuggingFaceToken =
                                  !_obscureHuggingFaceToken;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscureHuggingFaceToken,
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                    const SizedBox(height: 16),

                    // HuggingFace Token Actions
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _saveHuggingFaceToken,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_isSaving ? 'Saving...' : 'Save Token'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        if (_hasHuggingFaceToken) ...[
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _deleteHuggingFaceToken,
                            icon: const Icon(Icons.delete),
                            label: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Help links
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final url = Uri.parse(
                              'https://huggingface.co/settings/tokens',
                            );
                            if (await canLaunchUrl(url)) {
                              await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          icon: const Icon(Icons.vpn_key),
                          label: const Text('Step 3: Create HuggingFace token'),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            'Step 2: Accept license for each model:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        ...GemmaModelType.values.map(
                          (model) => Padding(
                            padding: const EdgeInsets.only(left: 24),
                            child: TextButton.icon(
                              onPressed: () async {
                                final url = Uri.parse(model.huggingFaceUrl);
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(
                                    url,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              icon: Icon(
                                Icons.open_in_new,
                                size: 14,
                                color: Colors.blue[700],
                              ),
                              label: Text(
                                model.displayName,
                                style: const TextStyle(fontSize: 12),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 32),
                  ],

                  // Gemini API Configuration (only show if API mode selected)
                  if (_titleMode == TitleModelMode.api) ...[
                    const Text(
                      'Gemini API Configuration',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use Google Gemini 2.5 Flash Lite API to generate intelligent titles.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 16),

                    // Gemini API Key Input
                    TextField(
                      controller: _geminiApiKeyController,
                      decoration: InputDecoration(
                        labelText: 'Gemini API Key',
                        hintText: 'Enter your Gemini API key',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureGeminiApiKey
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureGeminiApiKey = !_obscureGeminiApiKey;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscureGeminiApiKey,
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                    const SizedBox(height: 16),

                    // Gemini API Key Actions
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _saveGeminiApiKey,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_isSaving ? 'Saving...' : 'Save Key'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        if (_hasGeminiApiKey) ...[
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _deleteGeminiApiKey,
                            icon: const Icon(Icons.delete),
                            label: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Help link for Gemini API
                    TextButton.icon(
                      onPressed: () async {
                        final url = Uri.parse(
                          'https://aistudio.google.com/app/apikey',
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      icon: const Icon(Icons.help_outline),
                      label: const Text('Get a Gemini API key'),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 32),
                  ],

                  // OpenAI API Header (only show if API mode selected)
                  if (_transcriptionMode == TranscriptionMode.api) ...[
                    const Text(
                      'OpenAI API Configuration',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Configure your OpenAI API key to enable AI-powered transcription',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 24),

                    // Status Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _hasApiKey
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _hasApiKey ? Colors.green : Colors.orange,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _hasApiKey ? Icons.check_circle : Icons.warning,
                            color: _hasApiKey ? Colors.green : Colors.orange,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _hasApiKey
                                      ? 'API Key Configured'
                                      : 'No API Key',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _hasApiKey
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _hasApiKey
                                      ? 'Transcription is enabled'
                                      : 'Add an API key to enable transcription',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // API Key Input
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _obscureApiKey,
                      decoration: InputDecoration(
                        labelText: 'OpenAI API Key',
                        hintText: 'sk-...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureApiKey
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() => _obscureApiKey = !_obscureApiKey);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _saveApiKey,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_isSaving ? 'Saving...' : 'Save'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        if (_hasApiKey) ...[
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _deleteApiKey,
                            icon: const Icon(Icons.delete),
                            label: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Help Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              const Text(
                                'How to get an API key',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '1. Visit platform.openai.com/api-keys\n'
                            '2. Sign in or create an account\n'
                            '3. Click "Create new secret key"\n'
                            '4. Copy the key (starts with "sk-")\n'
                            '5. Paste it above and tap Save',
                            style: TextStyle(fontSize: 14, height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _openApiKeyHelp,
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Open OpenAI Dashboard'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Pricing Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.attach_money, color: Colors.grey[700]),
                              const SizedBox(width: 8),
                              const Text(
                                'Pricing',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Transcription costs \$0.006 per minute\n'
                            '• 1 min recording = \$0.006\n'
                            '• 10 min recording = \$0.06\n'
                            '• 1 hour recording = \$0.36',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ], // Close the if (_transcriptionMode == TranscriptionMode.api) block
                ],
              ),
      ),
    );
  }

  Widget _buildModeCard(TranscriptionMode mode) {
    final isSelected = _transcriptionMode == mode;

    return InkWell(
      onTap: () => _setTranscriptionMode(mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  mode == TranscriptionMode.api
                      ? Icons.cloud
                      : Icons.phone_android,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mode.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[800],
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              mode.description,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleModeCard(TitleModelMode mode) {
    final isSelected = _titleMode == mode;

    return InkWell(
      onTap: () => _setTitleMode(mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  mode == TitleModelMode.api
                      ? Icons.cloud
                      : Icons.phone_android,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mode.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[800],
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              mode.description,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
