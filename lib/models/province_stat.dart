class ProvinceStat {
  const ProvinceStat({
    required this.province,
    required this.totalRecords,
    required this.elevationCount,
    required this.countyCount,
    required this.coordinateCount,
    required this.trailheadElevationCount,
    required this.elevationGainCount,
    required this.routeLengthCount,
    required this.routeCountFilled,
    required this.trailheadCount,
  });

  final String province;
  final int totalRecords;
  final int elevationCount;
  final int countyCount;
  final int coordinateCount;
  final int trailheadElevationCount;
  final int elevationGainCount;
  final int routeLengthCount;
  final int routeCountFilled;
  final int trailheadCount;

  bool get isCrossProvince =>
      province.contains('/') || province.startsWith('چنداستانی');

  factory ProvinceStat.fromMap(Map<String, Object?> map) => ProvinceStat(
        province: map['province'] as String,
        totalRecords: (map['total_records'] as num?)?.toInt() ?? 0,
        elevationCount: (map['elevation_count'] as num?)?.toInt() ?? 0,
        countyCount: (map['county_count'] as num?)?.toInt() ?? 0,
        coordinateCount: (map['coordinate_count'] as num?)?.toInt() ?? 0,
        trailheadElevationCount:
            (map['trailhead_elevation_count'] as num?)?.toInt() ?? 0,
        elevationGainCount:
            (map['elevation_gain_count'] as num?)?.toInt() ?? 0,
        routeLengthCount:
            (map['route_length_count'] as num?)?.toInt() ?? 0,
        routeCountFilled:
            (map['route_count_filled'] as num?)?.toInt() ?? 0,
        trailheadCount: (map['trailhead_count'] as num?)?.toInt() ?? 0,
      );
}
