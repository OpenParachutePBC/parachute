class Space {
  final String id;
  final String userId;
  final String name;
  final String path;
  final String? icon;
  final String? color;
  final DateTime createdAt;
  final DateTime updatedAt;

  Space({
    required this.id,
    required this.userId,
    required this.name,
    required this.path,
    this.icon,
    this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Space.fromJson(Map<String, dynamic> json) {
    // Support both backend format (snake_case) and local format (camelCase)
    return Space(
      id: json['id'] as String,
      userId: (json['userId'] ?? json['user_id'] ?? 'local') as String,
      name: json['name'] as String,
      path: json['path'] as String,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      createdAt: DateTime.parse(
        (json['createdAt'] ?? json['created_at']) as String,
      ),
      updatedAt: DateTime.parse(
        (json['updatedAt'] ?? json['updated_at']) as String,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'path': path,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Space copyWith({
    String? id,
    String? userId,
    String? name,
    String? path,
    String? icon,
    String? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Space(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      path: path ?? this.path,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
