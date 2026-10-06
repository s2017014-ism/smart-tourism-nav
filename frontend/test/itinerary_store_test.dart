import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_tourism_nav/models/itinerary.dart';
import 'package:smart_tourism_nav/models/saved_itinerary.dart';
import 'package:smart_tourism_nav/services/itinerary_store.dart';

ItineraryPlan _samplePlan() => ItineraryPlan.fromJson({
      'num_visited': 1,
      'total_distance_m': 123.4,
      'total_duration_min': 45.0,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [113.5, 22.1],
          [113.6, 22.2],
        ],
      },
      'stops': [
        {
          'order': 1,
          'name': '測試景點',
          'category': 'tourism',
          'category_label': '觀光',
          'lat': 22.1,
          'lng': 113.5,
          'arrival': '09:00',
          'departure': '09:30',
          'dwell_min': 30,
          'travel_from_prev_m': 0.0,
        },
      ],
      'skipped': ['沒排到的'],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 這正是先前的 bug：第一次儲存時 getStringList 回傳 null，
  // 舊寫法用 const [] 導致 add() 丟出 UnsupportedError。
  test('第一次儲存（空清單）不應拋例外，且可讀回', () async {
    final store = ItineraryStore();
    expect(await store.loadAll(), isEmpty);

    await store.save(SavedItinerary(
      id: '1',
      name: '我的澳門行程',
      createdAt: DateTime(2026, 10, 6, 9, 0),
      plan: _samplePlan(),
      settings: {'duration_hours': 6},
    ));

    final loaded = await store.loadAll();
    expect(loaded.length, 1);
    expect(loaded.first.name, '我的澳門行程');
    expect(loaded.first.plan.stops.first.name, '測試景點');
    expect(loaded.first.plan.points.length, 2);
    expect(loaded.first.settings['duration_hours'], 6);
  });

  test('刪除指定行程後其餘保留', () async {
    final store = ItineraryStore();
    await store.save(SavedItinerary(id: 'a', name: 'A', createdAt: DateTime(2026, 1, 1), plan: _samplePlan(), settings: {}));
    await store.save(SavedItinerary(id: 'b', name: 'B', createdAt: DateTime(2026, 1, 2), plan: _samplePlan(), settings: {}));
    expect((await store.loadAll()).length, 2);

    await store.delete('a');
    final rest = await store.loadAll();
    expect(rest.length, 1);
    expect(rest.first.name, 'B');
  });
}
