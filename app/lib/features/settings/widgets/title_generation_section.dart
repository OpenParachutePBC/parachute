import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/core/models/title_generation_models.dart';
import 'package:app/core/providers/title_generation_provider.dart';
import 'package:app/core/widgets/gemma_model_download_card.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import './settings_section_header.dart';

/// Title Generation settings section
class TitleGenerationSection extends ConsumerStatefulWidget {
  const TitleGenerationSection({super.key});

  @override
  ConsumerState<TitleGenerationSection> createState() =>
      _TitleGenerationSectionState();
}

class _TitleGenerationSectionState
    extends ConsumerState<TitleGenerationSection> {
  TitleModelMode _titleMode = TitleModelMode.api;
  GemmaModelType _preferredGemmaModel = GemmaModelType.gemma1b;
  String _gemmaStorageInfo = '0 MB used';

  // Ollama settings (desktop)
  String _ollamaModel = 'gemma2:2b';
  List<String> _availableOllamaModels = [];
  bool _ollamaAvailable = false;

  // Gemini API
  final TextEditingController _geminiApiKeyController = TextEditingController();
  bool _obscureGeminiApiKey = true;
  bool _hasGeminiApiKey = false;
  bool _isSaving = false;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _geminiApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
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

    // Load Gemini API key
    final geminiApiKey = await storageService.getGeminiApiKey();
    if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
      _geminiApiKeyController.text = geminiApiKey;
      _hasGeminiApiKey = true;
    }

    // Load Ollama settings (desktop only)
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      await _loadOllamaSettings();
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOllamaSettings() async {
    final storageService = ref.read(storageServiceProvider);
    final ollamaService = ref.read(ollamaCleanupServiceProvider);

    final model = await storageService.getOllamaModel();
    _ollamaModel = model ?? 'gemma2:2b';

    try {
      _ollamaAvailable = await ollamaService.isAvailable();
      if (_ollamaAvailable) {
        _availableOllamaModels = await ollamaService.getAvailableModels();
      }
    } catch (e) {
      debugPrint('[Settings] Failed to check Ollama availability: $e');
      _ollamaAvailable = false;
      _availableOllamaModels = [];
    }

    if (mounted) {
      setState(() {});
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
          backgroundColor: BrandColors.success,
        ),
      );
    }
  }

  Future<void> _setOllamaModel(String model) async {
    await ref.read(storageServiceProvider).setOllamaModel(model);
    setState(() => _ollamaModel = model);
  }

  Future<void> _refreshGemmaStorage() async {
    final gemmaManager = ref.read(gemmaModelManagerProvider);
    final newStorageInfo = await gemmaManager.getStorageInfo();
    if (mounted) {
      setState(() => _gemmaStorageInfo = newStorageInfo);
    }
  }

  Future<void> _saveGeminiApiKey() async {
    final apiKey = _geminiApiKeyController.text.trim();

    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a Gemini API key'),
          backgroundColor: BrandColors.warning,
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
          SnackBar(
            content: const Text('Gemini API key saved successfully!'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save Gemini API key'),
            backgroundColor: BrandColors.error,
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
            style: TextButton.styleFrom(foregroundColor: BrandColors.error),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop =
        Platform.isMacOS || Platform.isLinux || Platform.isWindows;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Title Generation',
          icon: Icons.title,
        ),
        SizedBox(height: Spacing.xl),

        // Title Generation Mode Selector
        const SettingsSubsectionHeader(
          title: 'Title Generation Mode',
          subtitle: 'Choose how to generate titles for your recordings',
        ),
        SizedBox(height: Spacing.lg),

        // Mode selector cards
        Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildTitleModeCard(TitleModelMode.api, isDark)),
                SizedBox(width: Spacing.md),
                Expanded(child: _buildTitleModeCard(TitleModelMode.local, isDark)),
              ],
            ),
            SizedBox(height: Spacing.md),
            _buildTitleModeCard(TitleModelMode.disabled, isDark),
          ],
        ),
        SizedBox(height: Spacing.xxl),
        const Divider(),
        SizedBox(height: Spacing.xxl),

        // Local Gemma Models Section (mobile only)
        if (_titleMode == TitleModelMode.local &&
            (Platform.isAndroid || Platform.isIOS)) ...[
          _buildGemmaSection(isDark),
          SizedBox(height: Spacing.lg),
        ],

        // Ollama Configuration (desktop only)
        if (isDesktop) ...[
          _buildOllamaSection(isDark),
          SizedBox(height: Spacing.lg),
        ],

        // Gemini API Configuration (when API mode selected)
        if (_titleMode == TitleModelMode.api) ...[
          _buildGeminiSection(isDark),
          SizedBox(height: Spacing.lg),
        ],
      ],
    );
  }

  Widget _buildTitleModeCard(TitleModelMode mode, bool isDark) {
    final isSelected = _titleMode == mode;
    final isDesktop =
        Platform.isMacOS || Platform.isLinux || Platform.isWindows;
    final isDisabled = isDesktop && mode == TitleModelMode.local;

    return InkWell(
      onTap: isDisabled ? null : () => _setTitleMode(mode),
      borderRadius: BorderRadius.circular(Radii.md),
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Container(
          padding: EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: isSelected
                ? BrandColors.forest.withValues(alpha: 0.1)
                : (isDark
                      ? BrandColors.nightSurfaceElevated
                      : BrandColors.stone.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: isSelected
                  ? BrandColors.forest
                  : (isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood)
                      .withValues(alpha: 0.3),
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
                        : mode == TitleModelMode.disabled
                        ? Icons.timer
                        : Icons.phone_android,
                    color: isSelected
                        ? BrandColors.forest
                        : (isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood),
                  ),
                  SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      mode.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? BrandColors.forest
                            : (isDark
                                  ? BrandColors.nightText
                                  : BrandColors.charcoal),
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: BrandColors.forest, size: 20),
                ],
              ),
              SizedBox(height: Spacing.sm),
              Text(
                mode.getDescription(
                  Platform.isMacOS || Platform.isLinux || Platform.isWindows,
                ),
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGemmaSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSubsectionHeader(
          title: 'Local Gemma Models',
          subtitle:
              'Download models for offline title generation. Smaller models are faster but may be less creative.',
        ),
        SizedBox(height: Spacing.lg),

        // Storage info
        Container(
          padding: EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: BrandColors.turquoise.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              Icon(Icons.storage, color: BrandColors.turquoiseDeep),
              SizedBox(width: Spacing.sm),
              Text(
                'Storage: $_gemmaStorageInfo',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        SizedBox(height: Spacing.lg),

        // Model cards
        ...GemmaModelType.values.map(
          (model) => GemmaModelDownloadCard(
            modelType: model,
            isPreferred: model == _preferredGemmaModel,
            onSetPreferred: () => _setPreferredGemmaModel(model),
            onDownloadComplete: () => _refreshGemmaStorage(),
          ),
        ),
      ],
    );
  }

  Widget _buildOllamaSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSubsectionHeader(
          title: 'Ollama Configuration',
          subtitle:
              'Desktop transcription cleanup uses Ollama for local LLM processing',
        ),
        SizedBox(height: Spacing.lg),

        Container(
          padding: EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: _ollamaAvailable
                ? BrandColors.success.withValues(alpha: 0.1)
                : BrandColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: _ollamaAvailable ? BrandColors.success : BrandColors.warning,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _ollamaAvailable ? Icons.check_circle : Icons.warning,
                    color: _ollamaAvailable
                        ? BrandColors.success
                        : BrandColors.warning,
                    size: 28,
                  ),
                  SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _ollamaAvailable
                              ? 'Ollama Connected'
                              : 'Ollama Not Found',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: TypographyTokens.bodyLarge,
                            color: _ollamaAvailable
                                ? BrandColors.success
                                : BrandColors.warning,
                          ),
                        ),
                        SizedBox(height: Spacing.xs),
                        Text(
                          _ollamaAvailable
                              ? '${_availableOllamaModels.length} models available'
                              : 'Please install Ollama to use transcript cleanup',
                          style: TextStyle(
                            fontSize: TypographyTokens.bodySmall,
                            color: isDark
                                ? BrandColors.nightTextSecondary
                                : BrandColors.driftwood,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _loadOllamaSettings,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.turquoise,
                    ),
                  ),
                ],
              ),

              // Installation instructions
              if (!_ollamaAvailable) ...[
                SizedBox(height: Spacing.lg),
                const Divider(),
                SizedBox(height: Spacing.lg),
                _buildOllamaInstallInstructions(isDark),
                SizedBox(height: Spacing.md),
                TextButton.icon(
                  onPressed: () async {
                    final url = Uri.parse('https://ollama.com');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Visit ollama.com'),
                ),
              ],

              // Model selection
              if (_ollamaAvailable && _availableOllamaModels.isNotEmpty) ...[
                SizedBox(height: Spacing.lg),
                const Divider(),
                SizedBox(height: Spacing.lg),
                Text(
                  'Select Model for Transcript Cleanup',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: TypographyTokens.bodyMedium,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                SizedBox(height: Spacing.md),
                _buildOllamaModelList(isDark),
                SizedBox(height: Spacing.md),
                SettingsInfoBanner(
                  message: 'Selected model: $_ollamaModel',
                  color: BrandColors.turquoise,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOllamaInstallInstructions(bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.stone.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.terminal,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
                size: 16,
              ),
              SizedBox(width: Spacing.sm),
              Text(
                'Installation Instructions',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  fontSize: TypographyTokens.bodySmall,
                ),
              ),
            ],
          ),
          SizedBox(height: Spacing.md),
          Text(
            '1. Install Ollama:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              fontSize: TypographyTokens.bodySmall,
            ),
          ),
          SizedBox(height: Spacing.xs),
          Container(
            padding: EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              color: BrandColors.ink,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(
              Platform.isMacOS
                  ? 'brew install ollama'
                  : Platform.isLinux
                  ? 'curl -fsSL https://ollama.com/install.sh | sh'
                  : 'Download from https://ollama.com',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: TypographyTokens.labelSmall,
                color: BrandColors.softWhite,
              ),
            ),
          ),
          SizedBox(height: Spacing.md),
          Text(
            '2. Pull a model (recommended):',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              fontSize: TypographyTokens.bodySmall,
            ),
          ),
          SizedBox(height: Spacing.xs),
          Container(
            padding: EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              color: BrandColors.ink,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(
              'ollama pull llama3.2:1b',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: TypographyTokens.labelSmall,
                color: BrandColors.softWhite,
              ),
            ),
          ),
          SizedBox(height: Spacing.sm),
          Text(
            'Other options: llama3.2:3b, qwen2.5:3b, phi4:3.8b',
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOllamaModelList(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood)
              .withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        children: _availableOllamaModels.map((model) {
          final isSelected = _ollamaModel == model;
          return InkWell(
            onTap: () => _setOllamaModel(model),
            child: Container(
              padding: EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: isSelected
                    ? BrandColors.turquoise.withValues(alpha: 0.1)
                    : null,
                border: Border(
                  bottom: BorderSide(
                    color: (isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood)
                        .withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? BrandColors.turquoise
                        : (isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood),
                    size: 20,
                  ),
                  SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      model,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: TypographyTokens.bodySmall,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? BrandColors.turquoiseDeep
                            : (isDark
                                  ? BrandColors.nightText
                                  : BrandColors.charcoal),
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: BrandColors.success, size: 18),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGeminiSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSubsectionHeader(
          title: 'Gemini API Configuration',
          subtitle:
              'Use Google Gemini 2.5 Flash Lite API to generate intelligent titles.',
        ),
        SizedBox(height: Spacing.lg),

        // Gemini API Key Input
        TextField(
          controller: _geminiApiKeyController,
          decoration: InputDecoration(
            labelText: 'Gemini API Key',
            hintText: 'Enter your Gemini API key',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureGeminiApiKey ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () {
                setState(() => _obscureGeminiApiKey = !_obscureGeminiApiKey);
              },
            ),
          ),
          obscureText: _obscureGeminiApiKey,
          autocorrect: false,
          enableSuggestions: false,
        ),
        SizedBox(height: Spacing.lg),

        // Gemini API Key Actions
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveGeminiApiKey,
                icon: _isSaving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            BrandColors.softWhite,
                          ),
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Saving...' : 'Save Key'),
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.forest,
                  padding: EdgeInsets.symmetric(vertical: Spacing.md),
                ),
              ),
            ),
            if (_hasGeminiApiKey) ...[
              SizedBox(width: Spacing.md),
              FilledButton.icon(
                onPressed: _deleteGeminiApiKey,
                icon: const Icon(Icons.delete),
                label: const Text('Delete'),
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.error,
                  padding: EdgeInsets.symmetric(vertical: Spacing.md),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: Spacing.md),

        // Help link for Gemini API
        TextButton.icon(
          onPressed: () async {
            final url = Uri.parse('https://aistudio.google.com/app/apikey');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          icon: const Icon(Icons.help_outline),
          label: const Text('Get a Gemini API key'),
        ),
      ],
    );
  }
}
