class Peak {
  const Peak({
    required this.id,
    required this.name,
    required this.province,
    this.aliases,
    this.elevation,
    this.mapElevation,
    this.reportedElevations,
    this.sourceOccurrenceCount,
    this.county,
    this.district,
    this.latitude,
    this.longitude,
    this.coordinateSource,
    this.route,
    this.trailhead,
    this.trailheadElevationM,
    this.elevationGainM,
    this.routeLengthKm,
    this.ascentTime,
    this.roundtripTime,
    this.difficulty,
    this.bestSeason,
    this.guideRequired,
    this.routeStatus,
    this.localAlias,
    this.routeCount = 0,
    this.mountainRange,
    this.description,
    this.status,
    this.source,
    this.rawTextSample,
    this.sourceUrl,
    this.dataFlags,
    this.dataQualityStatus = 'incomplete',
    this.favorite = false,
    this.isDeleted = false,
    this.updatedAtJalali,
  });

  final String id;
  final String name;
  final String province;
  final String? aliases;
  final int? elevation;
  final int? mapElevation;
  final String? reportedElevations;
  final int? sourceOccurrenceCount;
  final String? county;
  final String? district;
  final double? latitude;
  final double? longitude;
  final String? coordinateSource;
  final String? route;
  final String? trailhead;
  final int? trailheadElevationM;
  final int? elevationGainM;
  final double? routeLengthKm;
  final String? ascentTime;
  final String? roundtripTime;
  final String? difficulty;
  final String? bestSeason;
  final String? guideRequired;
  final String? routeStatus;
  final String? localAlias;
  final int routeCount;
  final String? mountainRange;
  final String? description;
  final String? status;
  final String? source;
  final String? rawTextSample;
  final String? sourceUrl;
  final String? dataFlags;
  final String dataQualityStatus;
  final bool favorite;
  final bool isDeleted;
  final String? updatedAtJalali;

  bool get hasCoordinates => latitude != null && longitude != null;
  bool get hasRoute => route != null && route!.trim().isNotEmpty;
  bool get needsReview => dataQualityStatus == 'needs_review' || (dataFlags?.trim().isNotEmpty ?? false);
  bool get isComplete => dataQualityStatus == 'complete';

  factory Peak.fromMap(Map<String, Object?> map) => Peak(
        id: map['id'] as String,
        name: map['name'] as String,
        province: map['province'] as String,
        aliases: map['aliases'] as String?,
        elevation: (map['elevation'] as num?)?.toInt(),
        mapElevation: (map['map_elevation'] as num?)?.toInt(),
        reportedElevations: map['reported_elevations'] as String?,
        sourceOccurrenceCount: (map['source_occurrence_count'] as num?)?.toInt(),
        county: map['county'] as String?,
        district: map['district'] as String?,
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        coordinateSource: map['coordinate_source'] as String?,
        route: map['route'] as String?,
        trailhead: map['trailhead'] as String?,
        trailheadElevationM: (map['trailhead_elevation_m'] as num?)?.toInt(),
        elevationGainM: (map['elevation_gain_m'] as num?)?.toInt(),
        routeLengthKm: (map['route_length_km'] as num?)?.toDouble(),
        ascentTime: map['ascent_time'] as String?,
        roundtripTime: map['roundtrip_time'] as String?,
        difficulty: map['difficulty'] as String?,
        bestSeason: map['best_season'] as String?,
        guideRequired: map['guide_required'] as String?,
        routeStatus: map['route_status'] as String?,
        localAlias: map['local_alias'] as String?,
        routeCount: (map['route_count'] as num?)?.toInt() ?? 0,
        mountainRange: map['mountain_range'] as String?,
        description: map['description'] as String?,
        status: map['status'] as String?,
        source: map['source'] as String?,
        rawTextSample: map['raw_text_sample'] as String?,
        sourceUrl: map['source_url'] as String?,
        dataFlags: map['data_flags'] as String?,
        dataQualityStatus: map['data_quality_status'] as String? ?? 'incomplete',
        favorite: (map['favorite'] as num?)?.toInt() == 1,
        isDeleted: (map['is_deleted'] as num?)?.toInt() == 1,
        updatedAtJalali: map['updated_at_jalali'] as String?,
      );

  Map<String, Object?> toEditableMap() => {
        'province': province,
        'name': name,
        'aliases': aliases,
        'elevation': elevation,
        'map_elevation': mapElevation,
        'reported_elevations': reportedElevations,
        'source_occurrence_count': sourceOccurrenceCount,
        'source': source,
        'raw_text_sample': rawTextSample,
        'source_url': sourceUrl,
        'status': status,
        'county': county,
        'district': district,
        'latitude': latitude,
        'longitude': longitude,
        'coordinate_source': coordinateSource,
        'route': route,
        'trailhead': trailhead,
        'trailhead_elevation_m': trailheadElevationM,
        'elevation_gain_m': elevationGainM,
        'route_length_km': routeLengthKm,
        'ascent_time': ascentTime,
        'roundtrip_time': roundtripTime,
        'difficulty': difficulty,
        'best_season': bestSeason,
        'guide_required': guideRequired,
        'route_status': routeStatus,
        'local_alias': localAlias,
        'route_count': routeCount,
        'mountain_range': mountainRange,
        'description': description,
        'data_flags': dataFlags,
        'data_quality_status': dataQualityStatus,
      };
}
