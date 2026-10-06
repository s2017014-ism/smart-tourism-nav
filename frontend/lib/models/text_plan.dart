import 'itinerary.dart';

/// `/api/v1/plan-from-text` 的結果：解析出的意圖 + 行程。
class TextPlanResult {
  final String source; // "llm" | "rules"
  final String model;
  final String summary;
  final List<String> categories;
  final bool avoidStairs;
  final bool avoidSteep;
  final double? durationHours;
  final ItineraryPlan? itinerary;
  final String note;

  TextPlanResult({
    required this.source,
    required this.model,
    required this.summary,
    required this.categories,
    required this.avoidStairs,
    required this.avoidSteep,
    required this.durationHours,
    required this.itinerary,
    required this.note,
  });

  factory TextPlanResult.fromJson(Map<String, dynamic> j) {
    final intent = ((j['intent'] as Map?) ?? const {}).cast<String, dynamic>();
    final it = j['itinerary'];
    return TextPlanResult(
      source: j['source'] as String? ?? 'rules',
      model: j['model'] as String? ?? '',
      summary: intent['summary'] as String? ?? '',
      categories: (intent['categories'] as List? ?? const []).map((e) => e.toString()).toList(),
      avoidStairs: intent['avoid_stairs'] as bool? ?? false,
      avoidSteep: intent['avoid_steep'] as bool? ?? false,
      durationHours: (intent['duration_hours'] as num?)?.toDouble(),
      itinerary: it == null ? null : ItineraryPlan.fromJson((it as Map).cast<String, dynamic>()),
      note: j['note'] as String? ?? '',
    );
  }

  String get sourceText =>
      source == 'llm' ? 'LLM${model.isNotEmpty ? '（$model）' : ''}' : '規則式（未設定 LLM 金鑰）';
}
