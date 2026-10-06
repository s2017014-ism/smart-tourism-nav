/// 目前天氣（Open-Meteo）。
class Weather {
  final double? temperatureC;
  final double? apparentC;
  final int weatherCode;
  final String description;
  final bool isRaining;
  final double precipitationMm;
  final double? uvIndex;

  Weather({
    required this.temperatureC,
    required this.apparentC,
    required this.weatherCode,
    required this.description,
    required this.isRaining,
    required this.precipitationMm,
    required this.uvIndex,
  });

  factory Weather.fromJson(Map<String, dynamic> j) => Weather(
        temperatureC: (j['temperature_c'] as num?)?.toDouble(),
        apparentC: (j['apparent_c'] as num?)?.toDouble(),
        weatherCode: (j['weather_code'] as num?)?.toInt() ?? -1,
        description: j['description'] as String? ?? '',
        isRaining: j['is_raining'] as bool? ?? false,
        precipitationMm: (j['precipitation_mm'] as num?)?.toDouble() ?? 0,
        uvIndex: (j['uv_index'] as num?)?.toDouble(),
      );

  String get icon {
    if (isRaining) return '🌧';
    switch (weatherCode) {
      case 0:
      case 1:
        return '☀️';
      case 2:
        return '⛅';
      case 3:
        return '☁️';
      case 45:
      case 48:
        return '🌫';
      default:
        return '🌤';
    }
  }

  String get label {
    final t = temperatureC != null ? '${temperatureC!.round()}°C' : '';
    return '$icon $description $t'.trim();
  }
}
