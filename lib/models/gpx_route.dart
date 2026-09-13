class GpxRoute {
  const GpxRoute({
    required this.routeId,
    required this.peakId,
    required this.name,
    this.gpxFilePath,
    this.routeLengthKm,
    this.elevationGainM,
    this.trailhead,
    this.trailheadLatitude,
    this.trailheadLongitude,
    this.trailheadElevationM,
    this.sourceOwner,
    this.sourceUrl,
    this.priceIrr = 0,
    this.currency = 'IRR',
    this.publicationStatus = 'draft',
    this.downloadCount = 0,
    this.routeCountHint = 1,
    this.difficulty,
    this.estimatedDuration,
    this.bestSeason,
    this.routeType,
    this.fileSha256,
    this.dataFlags,
    this.version = 1,
    this.isDeleted = false,
    this.updatedAtJalali,
  });

  final String routeId;
  final String peakId;
  final String name;
  final String? gpxFilePath;
  final double? routeLengthKm;
  final int? elevationGainM;
  final String? trailhead;
  final double? trailheadLatitude;
  final double? trailheadLongitude;
  final int? trailheadElevationM;
  final String? sourceOwner;
  final String? sourceUrl;
  final int priceIrr;
  final String currency;
  final String publicationStatus;
  final int downloadCount;
  final int routeCountHint;
  final String? difficulty;
  final String? estimatedDuration;
  final String? bestSeason;
  final String? routeType;
  final String? fileSha256;
  final String? dataFlags;
  final int version;
  final bool isDeleted;
  final String? updatedAtJalali;

  bool get hasFile => gpxFilePath != null && gpxFilePath!.trim().isNotEmpty;
  bool get isPublished => publicationStatus == 'published';
  bool get isFree => priceIrr <= 0;

  factory GpxRoute.fromMap(Map<String, Object?> map) => GpxRoute(
        routeId: map['route_id'] as String,
        peakId: map['peak_id'] as String,
        name: map['name'] as String,
        gpxFilePath: map['gpx_file_path'] as String?,
        routeLengthKm: (map['route_length_km'] as num?)?.toDouble(),
        elevationGainM: (map['elevation_gain_m'] as num?)?.toInt(),
        trailhead: map['trailhead'] as String?,
        trailheadLatitude: (map['trailhead_latitude'] as num?)?.toDouble(),
        trailheadLongitude: (map['trailhead_longitude'] as num?)?.toDouble(),
        trailheadElevationM: (map['trailhead_elevation_m'] as num?)?.toInt(),
        sourceOwner: map['source_owner'] as String?,
        sourceUrl: map['source_url'] as String?,
        priceIrr: (map['price_irr'] as num?)?.toInt() ?? 0,
        currency: map['currency'] as String? ?? 'IRR',
        publicationStatus: map['publication_status'] as String? ?? 'draft',
        downloadCount: (map['download_count'] as num?)?.toInt() ?? 0,
        routeCountHint: (map['route_count_hint'] as num?)?.toInt() ?? 1,
        difficulty: map['difficulty'] as String?,
        estimatedDuration: map['estimated_duration'] as String?,
        bestSeason: map['best_season'] as String?,
        routeType: map['route_type'] as String?,
        fileSha256: map['file_sha256'] as String?,
        dataFlags: map['data_flags'] as String?,
        version: (map['version'] as num?)?.toInt() ?? 1,
        isDeleted: (map['is_deleted'] as num?)?.toInt() == 1,
        updatedAtJalali: map['updated_at_jalali'] as String?,
      );
}
