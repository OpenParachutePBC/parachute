class FileInfo {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;
  final String? extension;
  final bool isMarkdown;
  final bool isAudio;
  final String? downloadUrl;

  FileInfo({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
    this.extension,
    required this.isMarkdown,
    required this.isAudio,
    this.downloadUrl,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    // Handle size - could be int or string from JSON
    final sizeValue = json['size'];
    final size = sizeValue is int ? sizeValue : int.parse(sizeValue.toString());

    return FileInfo(
      name: json['name'] as String,
      path: json['path'] as String,
      isDirectory: json['isDirectory'] as bool,
      size: size,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      extension: json['extension'] as String?,
      isMarkdown: json['isMarkdown'] as bool,
      isAudio: json['isAudio'] as bool,
      downloadUrl: json['downloadUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'isDirectory': isDirectory,
      'size': size,
      'modifiedAt': modifiedAt.toIso8601String(),
      'extension': extension,
      'isMarkdown': isMarkdown,
      'isAudio': isAudio,
      'downloadUrl': downloadUrl,
    };
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class BrowseResult {
  final String path;
  final String parent;
  final List<FileInfo> files;
  final List<FileInfo> directories;

  BrowseResult({
    required this.path,
    required this.parent,
    required this.files,
    required this.directories,
  });

  factory BrowseResult.fromJson(Map<String, dynamic> json) {
    final filesList = json['files'] as List<dynamic>?;
    final directoriesList = json['directories'] as List<dynamic>?;

    return BrowseResult(
      path: json['path'] as String,
      parent: json['parent'] as String,
      files: filesList != null
          ? filesList
                .map((f) => FileInfo.fromJson(f as Map<String, dynamic>))
                .toList()
          : [],
      directories: directoriesList != null
          ? directoriesList
                .map((d) => FileInfo.fromJson(d as Map<String, dynamic>))
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'parent': parent,
      'files': files.map((f) => f.toJson()).toList(),
      'directories': directories.map((d) => d.toJson()).toList(),
    };
  }

  bool get isRoot => path.isEmpty;
}
