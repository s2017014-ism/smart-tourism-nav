import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models/itinerary.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';
import '../models/text_plan.dart';
import '../models/transit_plan.dart';
import '../models/weather.dart';

/// 與 FastAPI 後端溝通。
class ApiClient {
  final http.Client _client;

  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  Future<RoutePlan> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    bool avoidStairs = false,
    double? maxSlopePct,
    bool avoidRain = false,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/v1/route');

    final body = jsonEncode({
      'origin': {'lat': origin.latitude, 'lng': origin.longitude},
      'destination': {'lat': destination.latitude, 'lng': destination.longitude},
      'preferences': {
        'avoid_stairs': avoidStairs,
        'max_slope_pct': maxSlopePct,
        'avoid_rain': avoidRain,
      },
    });

    final resp = await _client
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw Exception('後端回應 ${resp.statusCode}：${resp.body}');
    }

    return RoutePlan.fromJson(jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }

  Future<List<Poi>> fetchPois({int limit = 1000}) async {
    final uri = Uri.parse('$apiBaseUrl/api/v1/pois?limit=$limit');
    final resp = await _client.get(uri).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw Exception('後端回應 ${resp.statusCode}');
    }

    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final features = (json['features'] as List?) ?? const [];
    return features
        .map((f) => Poi.fromFeature(f as Map<String, dynamic>))
        .where((p) => p.name.isNotEmpty)
        .toList();
  }

  Future<ItineraryPlan> fetchItinerary({
    required LatLng start,
    required String departureTime,
    required double durationHours,
    required List<String> categories,
    List<String> mustVisit = const [],
    int maxCandidates = 25,
    int maxFoodStops = 2,
    double radiusM = 4000,
    int dwellMinutes = 30,
    bool avoidStairs = false,
    double? maxSlopePct,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/v1/itinerary');
    final body = jsonEncode({
      'start': {'lat': start.latitude, 'lng': start.longitude},
      'departure_time': departureTime,
      'duration_hours': durationHours,
      'categories': categories,
      'must_visit': mustVisit,
      'max_candidates': maxCandidates,
      'max_food_stops': maxFoodStops,
      'radius_m': radiusM,
      'dwell_minutes': dwellMinutes,
      'preferences': {'avoid_stairs': avoidStairs, 'max_slope_pct': maxSlopePct},
    });

    final resp = await _client
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 240));

    if (resp.statusCode != 200) {
      throw Exception('後端回應 ${resp.statusCode}：${resp.body}');
    }

    return ItineraryPlan.fromJson(
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<TransitPlan> fetchTransitRoute({
    required LatLng origin,
    required LatLng destination,
    bool avoidStairs = false,
    double? maxSlopePct,
    bool avoidRain = false,
    String? departureTime,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/api/v1/transit-route');
    final body = jsonEncode({
      'origin': {'lat': origin.latitude, 'lng': origin.longitude},
      'destination': {'lat': destination.latitude, 'lng': destination.longitude},
      'preferences': {
        'avoid_stairs': avoidStairs,
        'max_slope_pct': maxSlopePct,
        'avoid_rain': avoidRain,
      },
      'departure_time': departureTime,
    });
    final resp = await _client
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 300));
    if (resp.statusCode != 200) {
      throw Exception('後端回應 ${resp.statusCode}：${resp.body}');
    }
    return TransitPlan.fromJson(jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }

  Future<TextPlanResult> planFromText(String text, {LatLng? start}) async {
    final uri = Uri.parse('$apiBaseUrl/api/v1/plan-from-text');
    final body = jsonEncode({
      'text': text,
      if (start != null) 'start': {'lat': start.latitude, 'lng': start.longitude},
    });
    final resp = await _client
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(minutes: 5));
    if (resp.statusCode != 200) {
      throw Exception('後端回應 ${resp.statusCode}：${resp.body}');
    }
    return TextPlanResult.fromJson(jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }

  Future<Weather> fetchWeather({double? lat, double? lng}) async {
    final q = (lat != null && lng != null) ? '?lat=$lat&lon=$lng' : '';
    final resp = await _client
        .get(Uri.parse('$apiBaseUrl/api/v1/weather$q'))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('後端回應 ${resp.statusCode}');
    }
    return Weather.fromJson(jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }

  Future<bool> health() async {
    try {
      final resp = await _client
          .get(Uri.parse('$apiBaseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
