class MapLinks {
  static Uri organicMaps({
    required double latitude,
    required double longitude,
    required String name,
  }) {
    final lat = latitude.toStringAsFixed(6);
    final lon = longitude.toStringAsFixed(6);
    final encodedName = Uri.encodeQueryComponent(name.trim().isEmpty ? 'Peak' : name.trim());
    return Uri.parse('https://omaps.app/map?v=1&ll=$lat,$lon&n=$encodedName');
  }
}
