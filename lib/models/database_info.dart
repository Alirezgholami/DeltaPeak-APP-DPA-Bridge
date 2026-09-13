class DatabaseInfo {
  const DatabaseInfo({required this.values});
  final Map<String, String> values;

  String get version => values['database_version'] ?? 'نامشخص';
  String get sourceFile => values['database_source_file'] ?? 'نامشخص';
  String get sourceSha256 => values['database_source_sha256'] ?? 'نامشخص';
  String get schemaVersion => values['schema_version'] ?? 'نامشخص';
  String get datasetRevision => values['dataset_revision'] ?? 'نامشخص';
  int get sourceRecordCount => int.tryParse(values['source_record_count'] ?? '') ?? 0;
  int get recordCount => int.tryParse(values['record_count'] ?? '') ?? 0;
  int get controlledExclusionCount => int.tryParse(values['controlled_exclusion_count'] ?? '') ?? 0;
  int get routeScaffoldCount => int.tryParse(values['route_scaffold_count'] ?? '') ?? 0;
  int get officialProvinceCount => int.tryParse(values['official_province_count'] ?? '') ?? 0;
  int get provinceLabelCount => int.tryParse(values['province_label_count'] ?? '') ?? 0;
  int get officialProvinceRecordCount => int.tryParse(values['official_province_record_count'] ?? '') ?? 0;
  int get ambiguousRecordCount => int.tryParse(values['cross_province_or_ambiguous_record_count'] ?? '') ?? 0;
  String get generatedAtUtc => values['generated_at_utc'] ?? 'نامشخص';
  String get generatedAtJalali => values['generated_at_jalali'] ?? 'نامشخص';
}
