import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_itinerary.dart';

/// 用 shared_preferences 把行程存在裝置本機。
class ItineraryStore {
  static const String _key = 'saved_itineraries_v1';

  Future<List<SavedItinerary>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = List<String>.from(prefs.getStringList(_key) ?? const []);
    final items = <SavedItinerary>[];
    for (final s in raw) {
      try {
        items.add(SavedItinerary.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // 略過壞掉的資料
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // 新的在前
    return items;
  }

  /// 儲存行程；若已存在相同 id 的行程則「覆蓋」它，否則新增。
  Future<void> save(SavedItinerary item) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = List<String>.from(prefs.getStringList(_key) ?? const []);
    raw.removeWhere((s) {
      try {
        return (jsonDecode(s) as Map)['id'] == item.id;
      } catch (_) {
        return false;
      }
    });
    raw.add(jsonEncode(item.toJson()));
    await prefs.setStringList(_key, raw);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = List<String>.from(prefs.getStringList(_key) ?? const []);
    raw.removeWhere((s) {
      try {
        return (jsonDecode(s) as Map)['id'] == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_key, raw);
  }
}
