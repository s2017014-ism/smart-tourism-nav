import 'package:latlong2/latlong.dart';

/// 多模態路線中的一段。
class TransitLeg {
  final String mode; // "walk" | "bus"
  final String? route;
  final String? fromName;
  final String? toName;
  final int numStops;
  final double distanceM;
  final double durationS;
  final List<LatLng> points;
  final List<LatLng> stopCoords;

  TransitLeg({
    required this.mode,
    required this.route,
    required this.fromName,
    required this.toName,
    required this.numStops,
    required this.distanceM,
    required this.durationS,
    required this.points,
    required this.stopCoords,
  });

  factory TransitLeg.fromJson(Map<String, dynamic> j) {
    final coords = (j['geometry'] as Map<String, dynamic>?)?['coordinates'] as List? ?? const [];
    final stopCoords = (j['stop_coords'] as List? ?? const [])
        .map((c) => LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    return TransitLeg(
      mode: j['mode'] as String? ?? 'walk',
      route: j['route'] as String?,
      fromName: j['from_name'] as String?,
      toName: j['to_name'] as String?,
      numStops: (j['num_stops'] as num?)?.toInt() ?? 0,
      distanceM: (j['distance_m'] as num?)?.toDouble() ?? 0,
      durationS: (j['duration_s'] as num?)?.toDouble() ?? 0,
      points: coords
          .map((c) => LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList(),
      stopCoords: stopCoords,
    );
  }
}

/// 走 + 公車多模態路線。
class TransitPlan {
  final String mode;
  final double totalDistanceM;
  final double totalDurationS;
  final int numTransfers;
  final String departureTime;
  final List<TransitLeg> legs;
  final List<LatLng> points;

  TransitPlan({
    required this.mode,
    required this.totalDistanceM,
    required this.totalDurationS,
    required this.numTransfers,
    required this.departureTime,
    required this.legs,
    required this.points,
  });

  factory TransitPlan.fromJson(Map<String, dynamic> json) {
    final coords = (json['geometry'] as Map<String, dynamic>?)?['coordinates'] as List? ?? const [];
    return TransitPlan(
      mode: json['mode'] as String? ?? 'walk',
      totalDistanceM: (json['total_distance_m'] as num?)?.toDouble() ?? 0,
      totalDurationS: (json['total_duration_s'] as num?)?.toDouble() ?? 0,
      numTransfers: (json['num_transfers'] as num?)?.toInt() ?? 0,
      departureTime: json['departure_time'] as String? ?? '',
      legs: (json['legs'] as List? ?? const [])
          .map((l) => TransitLeg.fromJson(l as Map<String, dynamic>))
          .toList(),
      points: coords
          .map((c) => LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList(),
    );
  }

  String get distanceText => totalDistanceM >= 1000
      ? '${(totalDistanceM / 1000).toStringAsFixed(2)} 公里'
      : '${totalDistanceM.toStringAsFixed(0)} 公尺';

  String get durationText {
    final m = (totalDurationS / 60).round();
    return m >= 60 ? '${m ~/ 60} 小時 ${m % 60} 分' : '$m 分鐘';
  }

  String get modeText => switch (mode) {
        'bus' => '全程公車',
        'mixed' => '走 + 公車',
        _ => '步行',
      };
}
