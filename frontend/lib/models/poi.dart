import 'package:latlong2/latlong.dart';

/// 景點 POI（對應後端 /api/v1/pois 的 GeoJSON feature）。
class Poi {
  final String id;
  final String name;
  final String? nameEn;
  final String category;
  final String categoryLabel;
  final LatLng point;

  Poi({
    required this.id,
    required this.name,
    required this.category,
    required this.categoryLabel,
    required this.point,
    this.nameEn,
  });

  factory Poi.fromFeature(Map<String, dynamic> feature) {
    final props = (feature['properties'] as Map<String, dynamic>?) ?? const {};
    final coords = ((feature['geometry'] as Map<String, dynamic>?)?['coordinates'] as List?) ?? const [0, 0];
    return Poi(
      id: props['osm_id']?.toString() ?? props['name']?.toString() ?? '',
      name: (props['name'] as String?) ?? '',
      nameEn: props['name_en'] as String?,
      category: (props['category'] as String?) ?? 'other',
      categoryLabel: (props['category_label'] as String?) ?? '其他',
      point: LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
    );
  }
}
