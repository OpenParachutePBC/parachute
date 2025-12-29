class TableQueryResult {
  final String tableName;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final int rowCount;

  TableQueryResult({
    required this.tableName,
    required this.columns,
    required this.rows,
    required this.rowCount,
  });

  factory TableQueryResult.fromJson(Map<String, dynamic> json) {
    return TableQueryResult(
      tableName: json['table_name'] as String? ?? '',
      columns: (json['columns'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      rows: (json['rows'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      rowCount: json['row_count'] as int? ?? 0,
    );
  }

  bool get isEmpty => rows.isEmpty;
  bool get isNotEmpty => rows.isNotEmpty;
}
