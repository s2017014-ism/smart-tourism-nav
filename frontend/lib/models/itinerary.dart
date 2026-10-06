import 'package:latlong2/latlong.dart';

/// 行程中的一站。
class ItineraryStop {
  final int order;
  final String name;
  final String category;
  final String categoryLabel;
  final LatLng point;
  final String arrival;
  final String departure;
  final int dwellMin;
  final double travelFromPrevM;

  ItineraryStop({
    required this.order,
    required this.name,
    required this.category,
    required this.categoryLabel,
    required this.point,
    required this.arrival,
    required this.departure,
    required this.dwellMin,
    required this.travelFromPrevM,
  });

  factory ItineraryStop.fromJson(Map<String, dynamic> j) => ItineraryStop(
        order: (j['order'] as num).toInt(),
        name: j['name'] as String,
        category: j['category'] as String? ?? 'other',
        categoryLabel: j['category_label'] as String? ?? '其他',
        point: LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        arrival: j['arrival'] as String? ?? '',
        departure: j['departure'] as String? ?? '',
        dwellMin: (j['dwell_min'] as num?)?.toInt() ?? 0,
        travelFromPrevM: (j['travel_from_prev_m'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'order': order,
        'name': name,
        'category': category,
        'category_label': categoryLabel,
        'lat': point.latitude,
        'lng': point.longitude,
        'arrival': arrival,
        'departure': departure,
        'dwell_min': dwellMin,
        'travel_from_prev_m': travelFromPrevM,
      };
}

/// 整趟行程。
class ItineraryPlan {
  final List<ItineraryStop> stops;
  final double totalDistanceM;
  final double totalDurationMin;
  final List<LatLng> points;
  final List<String> skipped;

  ItineraryPlan({
    required this.stops,
    required this.totalDistanceM,
    required this.totalDurationMin,
    required this.points,
    required this.skipped,
  });

  factory ItineraryPlan.fromJson(Map<String, dynamic> json) {
    final coords = (json['geometry'] as Map<String, dynamic>?)?['coordinates'] as List? ?? const [];
    return ItineraryPlan(
      stops: (json['stops'] as List? ?? const [])
          .map((s) => ItineraryStop.fromJson(s as Map<String, dynamic>))
          .toList(),
      totalDistanceM: (json['total_distance_m'] as num?)?.toDouble() ?? 0,
      totalDurationMin: (json['total_duration_min'] as num?)?.toDouble() ?? 0,
      points: coords
          .map((c) => LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList(),
      skipped: (json['skipped'] as List? ?? const []).map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'num_visited': stops.length,
        'total_distance_m': totalDistanceM,
        'total_duration_min': totalDurationMin,
        'geometry': {
          'type': 'LineString',
          'coordinates': points.map((p) => [p.longitude, p.latitude]).toList(),
        },
        'stops': stops.map((s) => s.toJson()).toList(),
        'skipped': skipped,
      };

  String get distanceText => totalDistanceM >= 1000
      ? '${(totalDistanceM / 1000).toStringAsFixed(2)} 公里'
      : '${totalDistanceM.toStringAsFixed(0)} 公尺';

  String get durationText {
    final m = totalDurationMin.round();
    if (m >= 60) return '${m ~/ 60} 小時 ${m % 60} 分';
    return '$m 分鐘';
  }
}
