/// Model for generation backend configuration
class GenerationBackend {
  final String name;
  final bool enabled;
  final bool isDefault;
  final bool available;
  final String? availabilityError;
  final String? model;
  final String? apiKey;
  final int? steps;
  final int? quantize;
  final GenerationBackendInfo? info;

  const GenerationBackend({
    required this.name,
    this.enabled = true,
    this.isDefault = false,
    this.available = false,
    this.availabilityError,
    this.model,
    this.apiKey,
    this.steps,
    this.quantize,
    this.info,
  });

  factory GenerationBackend.fromJson(Map<String, dynamic> json) {
    return GenerationBackend(
      name: json['name'] as String,
      enabled: json['enabled'] as bool? ?? true,
      isDefault: json['isDefault'] as bool? ?? false,
      available: json['available'] as bool? ?? false,
      availabilityError: json['availabilityError'] as String?,
      model: json['model'] as String?,
      apiKey: json['api_key'] as String?,
      steps: json['steps'] as int?,
      quantize: json['quantize'] as int?,
      info: json['info'] != null
          ? GenerationBackendInfo.fromJson(json['info'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toConfigJson() {
    final config = <String, dynamic>{
      'enabled': enabled,
    };
    if (model != null) config['model'] = model;
    if (apiKey != null && apiKey!.isNotEmpty) config['api_key'] = apiKey;
    if (steps != null) config['steps'] = steps;
    if (quantize != null) config['quantize'] = quantize;
    return config;
  }
}

/// Backend metadata/info
class GenerationBackendInfo {
  final String name;
  final String displayName;
  final String description;
  final String type;
  final List<String> requirements;
  final List<SupportedModel> supportedModels;
  final String? defaultModel;

  const GenerationBackendInfo({
    required this.name,
    required this.displayName,
    required this.description,
    required this.type,
    this.requirements = const [],
    this.supportedModels = const [],
    this.defaultModel,
  });

  factory GenerationBackendInfo.fromJson(Map<String, dynamic> json) {
    return GenerationBackendInfo(
      name: json['name'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'image',
      requirements: (json['requirements'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      supportedModels: (json['supportedModels'] as List<dynamic>?)
              ?.map((e) => SupportedModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      defaultModel: json['defaultModel'] as String?,
    );
  }
}

/// Supported model within a backend
class SupportedModel {
  final String id;
  final String name;
  final String description;
  final int? defaultSteps;

  const SupportedModel({
    required this.id,
    required this.name,
    required this.description,
    this.defaultSteps,
  });

  factory SupportedModel.fromJson(Map<String, dynamic> json) {
    return SupportedModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      defaultSteps: json['defaultSteps'] as int?,
    );
  }
}

/// Response from the backends list endpoint
class GenerationBackendsResponse {
  final String type;
  final String? defaultBackend;
  final List<GenerationBackend> backends;

  const GenerationBackendsResponse({
    required this.type,
    this.defaultBackend,
    required this.backends,
  });

  factory GenerationBackendsResponse.fromJson(Map<String, dynamic> json) {
    return GenerationBackendsResponse(
      type: json['type'] as String,
      defaultBackend: json['defaultBackend'] as String?,
      backends: (json['backends'] as List<dynamic>?)
              ?.map((e) => GenerationBackend.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
