import 'itinerary.dart';

/// 使用者儲存的行程（含產生時的設定，可還原）。
class SavedItinerary {
  final String id;
  final String name;
  final DateTime createdAt;
  final ItineraryPlan plan;
  final Map<String, dynamic> settings;

  SavedItinerary({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.plan,
    required this.settings,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'plan': plan.toJson(),
        'settings': settings,
      };

  factory SavedItinerary.fromJson(Map<String, dynamic> j) => SavedItinerary(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        plan: ItineraryPlan.fromJson((j['plan'] as Map).cast<String, dynamic>()),
        settings: ((j['settings'] as Map?) ?? const {}).cast<String, dynamic>(),
      );

  String get dateText {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${createdAt.year}/${two(createdAt.month)}/${two(createdAt.day)} '
        '${two(createdAt.hour)}:${two(createdAt.minute)}';
  }
}
