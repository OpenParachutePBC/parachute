/// A quick action prompt loaded from prompts.yaml
class QuickPrompt {
  final String name;
  final String description;
  final String icon;
  final String prompt;

  const QuickPrompt({
    required this.name,
    required this.description,
    required this.icon,
    required this.prompt,
  });

  factory QuickPrompt.fromYaml(Map<String, dynamic> yaml) {
    return QuickPrompt(
      name: yaml['name'] as String? ?? 'Unnamed',
      description: yaml['description'] as String? ?? '',
      icon: yaml['icon'] as String? ?? 'chat',
      prompt: yaml['prompt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toYaml() => {
        'name': name,
        'description': description,
        'icon': icon,
        'prompt': prompt,
      };

  @override
  String toString() => 'QuickPrompt($name)';
}
