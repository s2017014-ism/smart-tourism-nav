import 'package:latlong2/latlong.dart';

/// 後端 RouteResponse 的前端模型。
class RoutePlan {
  final double distanceM;
  final double durationS;
  final List<LatLng> points;
  final List<RouteStep> steps;

  RoutePlan({
    required this.distanceM,
    required this.durationS,
    required this.points,
    required this.steps,
  });

  factory RoutePlan.fromJson(Map<String, dynamic> json) {
    final geometry = (json['geometry'] as Map<String, dynamic>?)?['coordinates'] as List?;
    final points = <LatLng>[];
    if (geometry != null) {
      for (final c in geometry) {
        final pair = c as List;
        points.add(LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()));
      }
    }

    final steps = <RouteStep>[];
    for (final s in (json['steps'] as List? ?? const [])) {
      steps.add(RouteStep.fromJson(s as Map<String, dynamic>));
    }

    return RoutePlan(
      distanceM: (json['distance_m'] as num).toDouble(),
      durationS: (json['duration_s'] as num).toDouble(),
      points: points,
      steps: steps,
    );
  }

  String get distanceText {
    if (distanceM >= 1000) return '${(distanceM / 1000).toStringAsFixed(2)} 公里';
    return '${distanceM.toStringAsFixed(0)} 公尺';
  }

  String get durationText {
    final minutes = (durationS / 60).round();
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return '$h 小時 $m 分';
    }
    return '$minutes 分鐘';
  }
}

class RouteStep {
  final String instruction;
  final double distanceM;
  final double durationS;

  RouteStep({
    required this.instruction,
    required this.distanceM,
    required this.durationS,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) => RouteStep(
        instruction: json['instruction'] as String? ?? '',
        distanceM: (json['distance_m'] as num?)?.toDouble() ?? 0,
        durationS: (json['duration_s'] as num?)?.toDouble() ?? 0,
      );
}
