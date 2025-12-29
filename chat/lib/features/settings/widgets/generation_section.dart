import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/feature_flags_provider.dart';
import '../models/generation_backend.dart';
import '../services/generation_service.dart';
import './settings_section_header.dart';

/// Provider for the generation service
final generationServiceProvider = Provider<GenerationService>((ref) {
  final baseUrl = ref.watch(aiServerUrlProvider).valueOrNull ?? 'http://localhost:3333';
  return GenerationService(baseUrl: baseUrl);
});

/// Provider for image backends
final imageBackendsProvider = FutureProvider<GenerationBackendsResponse>((ref) async {
  final service = ref.watch(generationServiceProvider);
  return service.getBackends('image');
});

/// Generation settings section for image/audio/etc backends
class GenerationSection extends ConsumerStatefulWidget {
  const GenerationSection({super.key});

  @override
  ConsumerState<GenerationSection> createState() => _GenerationSectionState();
}

class _GenerationSectionState extends ConsumerState<GenerationSection> {
  String? _selectedBackend;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backendsAsync = ref.watch(imageBackendsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Image Generation',
          subtitle: 'Configure backends for AI image generation',
          icon: Icons.image,
        ),
        SizedBox(height: Spacing.lg),

        backendsAsync.when(
          data: (response) {
            _selectedBackend ??= response.defaultBackend;
            return _buildBackendsList(response, isDark);
          },
          loading: () => Center(
            child: Padding(
              padding: EdgeInsets.all(Spacing.xl),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                ),
              ),
            ),
          ),
          error: (error, stack) => _buildErrorState(error.toString(), isDark),
        ),

        SizedBox(height: Spacing.lg),
      ],
    );
  }

  Widget _buildBackendsList(GenerationBackendsResponse response, bool isDark) {
    return Column(
      children: [
        // Default backend selector
        _buildDefaultSelector(response, isDark),
        SizedBox(height: Spacing.lg),

        // Backend cards
        ...response.backends.map((backend) => Padding(
              padding: EdgeInsets.only(bottom: Spacing.md),
              child: _buildBackendCard(backend, isDark),
            )),

        if (_errorMessage != null) ...[
          SizedBox(height: Spacing.md),
          Container(
            padding: EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: BrandColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: BrandColors.error),
            ),
            child: Row(
              children: [
                Icon(Icons.error, color: BrandColors.error, size: 20),
                SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: BrandColors.error,
                      fontSize: TypographyTokens.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDefaultSelector(GenerationBackendsResponse response, bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.star,
            color: BrandColors.warning,
            size: 20,
          ),
          SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Default Backend',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: TypographyTokens.bodyMedium,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                Text(
                  'Used when no backend is specified',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ),
          DropdownButton<String>(
            value: _selectedBackend,
            underline: const SizedBox(),
            dropdownColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
            items: response.backends.map((b) {
              final displayName = b.info?.displayName ?? b.name;
              return DropdownMenuItem(
                value: b.name,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      b.available ? Icons.check_circle : Icons.warning,
                      color: b.available ? BrandColors.success : BrandColors.warning,
                      size: 16,
                    ),
                    SizedBox(width: Spacing.sm),
                    Text(
                      displayName,
                      style: TextStyle(
                        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: _isLoading ? null : (value) => _setDefaultBackend(value!),
          ),
        ],
      ),
    );
  }

  Widget _buildBackendCard(GenerationBackend backend, bool isDark) {
    final isDefault = backend.name == _selectedBackend;
    final displayName = backend.info?.displayName ?? backend.name;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isDefault
              ? BrandColors.forest
              : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood)
                  .withValues(alpha: 0.3),
          width: isDefault ? 2 : 1,
        ),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(horizontal: Spacing.md),
        childrenPadding: EdgeInsets.all(Spacing.md),
        leading: Icon(
          backend.available ? Icons.check_circle : Icons.warning,
          color: backend.available ? BrandColors.success : BrandColors.warning,
        ),
        title: Row(
          children: [
            Text(
              displayName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: TypographyTokens.bodyMedium,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            if (isDefault) ...[
              SizedBox(width: Spacing.sm),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: Spacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: BrandColors.forest.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(
                  'DEFAULT',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall - 2,
                    fontWeight: FontWeight.bold,
                    color: BrandColors.forest,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          backend.info?.description ?? (backend.available ? 'Available' : 'Not configured'),
          style: TextStyle(
            fontSize: TypographyTokens.labelSmall,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
        children: [
          _buildBackendSettings(backend, isDark),
        ],
      ),
    );
  }

  Widget _buildBackendSettings(GenerationBackend backend, bool isDark) {
    if (backend.name == 'mflux') {
      return _buildMfluxSettings(backend, isDark);
    } else if (backend.name == 'nano-banana') {
      return _buildNanoBananaSettings(backend, isDark);
    }
    return const SizedBox.shrink();
  }

  Widget _buildMfluxSettings(GenerationBackend backend, bool isDark) {
    final models = backend.info?.supportedModels ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status
        _buildStatusBadge(backend, isDark),
        SizedBox(height: Spacing.md),

        // Requirements
        if (backend.info?.requirements.isNotEmpty ?? false) ...[
          Text(
            'Requirements:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: TypographyTokens.bodySmall,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
          SizedBox(height: Spacing.xs),
          ...backend.info!.requirements.map((req) => Padding(
                padding: EdgeInsets.only(left: Spacing.md, bottom: Spacing.xs),
                child: Row(
                  children: [
                    Icon(Icons.chevron_right, size: 16, color: BrandColors.driftwood),
                    SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        req,
                        style: TextStyle(
                          fontSize: TypographyTokens.labelSmall,
                          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          SizedBox(height: Spacing.md),
        ],

        // Model selection
        if (models.isNotEmpty) ...[
          Text(
            'Model:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: TypographyTokens.bodySmall,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
          SizedBox(height: Spacing.sm),
          ...models.map((model) => RadioListTile<String>(
                value: model.id,
                groupValue: backend.model ?? 'schnell',
                onChanged: (value) => _updateBackendConfig(
                  backend.name,
                  {'model': value},
                ),
                title: Text(
                  model.name,
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                subtitle: Text(
                  model.description,
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              )),
        ],

        // Install instructions - always show setup guide for mflux
        SizedBox(height: Spacing.md),
        Container(
          padding: EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: backend.available
                ? BrandColors.forest.withValues(alpha: 0.1)
                : BrandColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: backend.available ? BrandColors.forest : BrandColors.warning,
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                backend.available ? 'mflux is installed' : 'Setup mflux (local image generation)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              SizedBox(height: Spacing.sm),
              if (!backend.available) ...[
                Text(
                  'Step 1: Install mflux',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
                SizedBox(height: Spacing.xs),
                _buildCodeBlock('uv tool install mflux', isDark),
                SizedBox(height: Spacing.md),
                Text(
                  'Step 2: Pre-download model (optional but recommended)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
                SizedBox(height: Spacing.xs),
                _buildCodeBlock('mflux-save --path ~/.mflux/schnell_8bit --model schnell --quantize 8', isDark),
                SizedBox(height: Spacing.sm),
                Text(
                  'This downloads ~12GB and saves a quantized version for faster loading.',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    fontStyle: FontStyle.italic,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
              ] else ...[
                Text(
                  'Ready to generate images locally on your Mac.',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNanoBananaSettings(GenerationBackend backend, bool isDark) {
    final models = backend.info?.supportedModels ?? [];
    final apiKeyController = TextEditingController(text: backend.apiKey ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status
        _buildStatusBadge(backend, isDark),
        SizedBox(height: Spacing.md),

        // API Key
        Text(
          'Gemini API Key:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: TypographyTokens.bodySmall,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        SizedBox(height: Spacing.sm),
        TextField(
          controller: apiKeyController,
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'Enter your Gemini API key',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: const Icon(Icons.save),
              onPressed: () => _updateBackendConfig(
                backend.name,
                {'api_key': apiKeyController.text.trim()},
              ),
            ),
          ),
        ),
        SizedBox(height: Spacing.sm),
        TextButton.icon(
          onPressed: () {
            // Open API key page
          },
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Get API key from Google AI Studio'),
          style: TextButton.styleFrom(
            foregroundColor: BrandColors.turquoise,
            padding: EdgeInsets.zero,
          ),
        ),
        SizedBox(height: Spacing.md),

        // Model selection
        if (models.isNotEmpty) ...[
          Text(
            'Model:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: TypographyTokens.bodySmall,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
          SizedBox(height: Spacing.sm),
          ...models.map((model) => RadioListTile<String>(
                value: model.id,
                groupValue: backend.model ?? 'gemini-2.5-flash-image',
                onChanged: (value) => _updateBackendConfig(
                  backend.name,
                  {'model': value},
                ),
                title: Text(
                  model.name,
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                subtitle: Text(
                  model.description,
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              )),
        ],
      ],
    );
  }

  Widget _buildCodeBlock(String code, bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.cream,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: SelectableText(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: TypographyTokens.labelSmall,
          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(GenerationBackend backend, bool isDark) {
    final isAvailable = backend.available;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: (isAvailable ? BrandColors.success : BrandColors.warning).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: isAvailable ? BrandColors.success : BrandColors.warning,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isAvailable ? Icons.check_circle : Icons.warning,
            color: isAvailable ? BrandColors.success : BrandColors.warning,
            size: 16,
          ),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              isAvailable ? 'Ready to use' : (backend.availabilityError ?? 'Not configured'),
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: isAvailable ? BrandColors.success : BrandColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error, bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: BrandColors.error),
      ),
      child: Column(
        children: [
          Icon(Icons.error, color: BrandColors.error, size: 48),
          SizedBox(height: Spacing.md),
          Text(
            'Failed to load backends',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: TypographyTokens.bodyMedium,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
          SizedBox(height: Spacing.sm),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
          SizedBox(height: Spacing.md),
          FilledButton.icon(
            onPressed: () => ref.invalidate(imageBackendsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.turquoise,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setDefaultBackend(String backendName) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(generationServiceProvider);
      await service.setDefaultBackend('image', backendName);
      setState(() => _selectedBackend = backendName);
      ref.invalidate(imageBackendsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Default set to $backendName'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateBackendConfig(String name, Map<String, dynamic> config) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(generationServiceProvider);
      await service.updateBackend('image', name, config);
      ref.invalidate(imageBackendsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settings saved'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
