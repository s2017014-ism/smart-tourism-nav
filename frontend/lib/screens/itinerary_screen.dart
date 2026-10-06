import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models/itinerary.dart';
import '../models/poi.dart';
import '../models/saved_itinerary.dart';
import '../services/api_client.dart';
import '../services/itinerary_store.dart';
import '../widgets/numbered_marker.dart';

class ItineraryScreen extends StatefulWidget {
  const ItineraryScreen({super.key, this.initialPlan, this.initialSettings});

  /// 由「我的行程」載入時帶入的既有行程與設定。
  final ItineraryPlan? initialPlan;
  final Map<String, dynamic>? initialSettings;

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen> {
  final MapController _mapController = MapController();
  final ApiClient _api = ApiClient();
  final ItineraryStore _store = ItineraryStore();

  LatLng _start = const LatLng(22.19356, 113.53963); // 議事亭前地
  String _departure = '09:00';
  double _duration = 6;
  final Set<String> _cats = {'tourism', 'historic', 'natural', 'curated'};
  final TextEditingController _mustCtrl = TextEditingController();
  int _maxFood = 2;

  ItineraryPlan? _plan;
  bool _loading = false;
  List<Poi> _allPois = [];
  bool _poisLoaded = false;
  bool _accessible = false; // 合併：避開階梯 + 避免陡坡
  final TextEditingController _nlCtrl = TextEditingController();
  bool _nlLoading = false;
  String? _nlSummary;
  String? _nlSource;

  static const Map<String, String> _catLabels = {
    'tourism': '觀光',
    'historic': '歷史',
    'natural': '自然',
    'leisure': '休閒',
    'place': '廣場',
    'man_made': '地標',
    'curated': '必訪',
    'food': '美食',
  };

  static Color _catColor(String c) {
    switch (c) {
      case 'tourism':
        return Colors.blue;
      case 'historic':
        return Colors.brown;
      case 'natural':
        return Colors.green;
      case 'leisure':
        return Colors.teal;
      case 'place':
        return Colors.orange;
      case 'man_made':
        return Colors.red;
      case 'curated':
        return Colors.deepOrange;
      case 'food':
        return Colors.pink;
      default:
        return Colors.deepOrange;
    }
  }

  @override
  void initState() {
    super.initState();
    final s = widget.initialSettings;
    if (s != null) {
      final start = s['start'] as Map?;
      if (start != null) {
        _start = LatLng((start['lat'] as num).toDouble(), (start['lng'] as num).toDouble());
      }
      _departure = s['departure_time'] as String? ?? _departure;
      _duration = (s['duration_hours'] as num?)?.toDouble() ?? _duration;
      final cats = s['categories'] as List?;
      if (cats != null) {
        _cats
          ..clear()
          ..addAll(cats.map((e) => e.toString()));
      }
      _mustCtrl.text = s['must_visit'] as String? ?? '';
      _maxFood = (s['max_food_stops'] as num?)?.toInt() ?? _maxFood;
      _accessible = (s['avoid_stairs'] == true) || (s['max_slope_pct'] != null);
    }
    _plan = widget.initialPlan;
    if (_plan != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit(_plan!));
    }
  }

  @override
  void dispose() {
    _mustCtrl.dispose();
    _nlCtrl.dispose();
    super.dispose();
  }

  Future<void> _planFromText() async {
    final text = _nlCtrl.text.trim();
    if (text.isEmpty) {
      _snack('請先輸入一句話，例如：想看歷史地質但不想走太累');
      return;
    }
    setState(() => _nlLoading = true);
    try {
      final result = await _api.planFromText(text);
      if (!mounted) return;
      setState(() {
        _nlLoading = false;
        _nlSummary = result.summary;
        _nlSource = result.sourceText;
        if (result.itinerary != null) {
          _plan = result.itinerary;
          if (result.durationHours != null) _duration = result.durationHours!;
          if (result.categories.isNotEmpty) {
            _cats
              ..clear()
              ..addAll(result.categories);
          }
          _accessible = result.avoidStairs || result.avoidSteep;
        }
      });
      if (result.itinerary != null) _fit(result.itinerary!);
      if (result.note.isNotEmpty) _snack(result.note);
    } catch (e) {
      if (!mounted) return;
      setState(() => _nlLoading = false);
      _snack('規劃失敗：$e');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickTime() async {
    final p = _departure.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
    );
    if (t != null) {
      setState(() => _departure = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _generate() async {
    if (_cats.isEmpty) {
      _snack('請至少選一個類別');
      return;
    }
    setState(() => _loading = true);
    try {
      final must = _mustCtrl.text
          .split(RegExp(r'[,，\s]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final plan = await _api.fetchItinerary(
        start: _start,
        departureTime: _departure,
        durationHours: _duration,
        categories: _cats.toList(),
        mustVisit: must,
        maxFoodStops: _maxFood,
        avoidStairs: _accessible,
        maxSlopePct: _accessible ? 12 : null,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loading = false;
      });
      _fit(plan);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('產生失敗：$e');
    }
  }

  void _fit(ItineraryPlan plan) {
    if (plan.points.length < 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(plan.points),
          padding: const EdgeInsets.all(56),
        ),
      );
    });
  }

  void _onTap(TapPosition _, LatLng point) {
    setState(() {
      _start = point;
      _plan = null;
    });
  }

  void _showStops() {
    final plan = _plan;
    if (plan == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Text('行程共 ${plan.stops.length} 站 · ${plan.distanceText} · 約 ${plan.durationText}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                itemCount: plan.stops.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = plan.stops[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _catColor(s.category),
                      child: Text('${s.order}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                    title: Text(s.name),
                    subtitle: Text(
                      '${s.arrival}–${s.departure}　${s.categoryLabel}'
                      '${i == 0 ? '' : '　步行 ${s.travelFromPrevM.toStringAsFixed(0)}m'}',
                    ),
                    trailing: Text('${s.dwellMin}分', style: TextStyle(color: Colors.grey.shade600)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSearch() async {
    try {
      if (!_poisLoaded) {
        _allPois = await _api.fetchPois();
        _poisLoaded = true;
      }
    } catch (e) {
      if (!mounted) return;
      _snack('無法載入景點：$e');
      return;
    }
    if (!mounted) return;

    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final q = query.trim().toLowerCase();
          final results = (q.isEmpty
                  ? _allPois
                  : _allPois.where((p) =>
                      p.name.toLowerCase().contains(q) ||
                      (p.nameEn?.toLowerCase().contains(q) ?? false)))
              .take(60)
              .toList();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '搜尋景點（例：大三巴、媽閣、氹仔）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setSheet(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: results.isEmpty
                        ? const Center(child: Text('沒有符合的景點'))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final p = results[i];
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(radius: 7, backgroundColor: _catColor(p.category)),
                                title: Text(p.name),
                                subtitle: Text(p.categoryLabel),
                                onTap: () {
                                  setState(() {
                                    _start = p.point;
                                    _plan = null;
                                  });
                                  Navigator.pop(ctx);
                                  _snack('已將「${p.name}」設為起點');
                                },
                                trailing: IconButton(
                                  tooltip: '加入必訪',
                                  icon: const Icon(Icons.star_border),
                                  onPressed: () {
                                    final cur = _mustCtrl.text.trim();
                                    if (!cur.contains(p.name)) {
                                      _mustCtrl.text = cur.isEmpty ? p.name : '$cur, ${p.name}';
                                    }
                                    _snack('已加入必訪：${p.name}');
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null) return;

    final now = DateTime.now();
    final ctrl = TextEditingController(text: '澳門行程 ${now.month}/${now.day}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('儲存行程'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '行程名稱'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('儲存')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final settings = <String, dynamic>{
      'start': {'lat': _start.latitude, 'lng': _start.longitude},
      'departure_time': _departure,
      'duration_hours': _duration,
      'categories': _cats.toList(),
      'must_visit': _mustCtrl.text,
      'max_food_stops': _maxFood,
      'avoid_stairs': _accessible,
      'max_slope_pct': _accessible ? 12 : null,
    };

    try {
      await _store.save(SavedItinerary(
        id: now.microsecondsSinceEpoch.toString(),
        name: name,
        createdAt: now,
        plan: plan,
        settings: settings,
      ));
      if (!mounted) return;
      _snack('已儲存「$name」，可在「我的行程」查看');
    } catch (e) {
      if (!mounted) return;
      _snack('儲存失敗：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('智慧行程規劃'),
        actions: [
          IconButton(
            tooltip: '搜尋景點',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          IconButton(
            tooltip: '清除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() {
              _plan = null;
              _start = const LatLng(22.19356, 113.53963);
            }),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: macauCenter,
              initialZoom: 14,
              minZoom: 11,
              maxZoom: 19,
              onTap: _onTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'mo.um.smartnav.smart_tourism_nav',
              ),
              if (_plan != null && _plan!.points.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _plan!.points, strokeWidth: 5, color: Colors.deepOrange.shade700),
                  ],
                ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          if (_loading || _nlLoading)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        _nlLoading ? 'AI 解析與排程中，請稍候…' : '行程求解中，請稍候…',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _buildPanel(),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    final plan = _plan;
    if (plan != null) {
      for (final s in plan.stops) {
        markers.add(Marker(
          point: s.point,
          width: 30,
          height: 30,
          child: NumberedMarker(number: s.order, color: _catColor(s.category)),
        ));
      }
    }
    markers.add(Marker(
      point: _start,
      width: 30,
      height: 30,
      child: const EndpointMarker(icon: Icons.trip_origin, color: Colors.green),
    ));
    return markers;
  }

  Widget _buildPanel() {
    final plan = _plan;
    final maxH = MediaQuery.of(context).size.height * 0.56;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nlCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: '用一句話描述（例：想看歷史地質但不想走太累）',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _planFromText(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _nlLoading ? null : _planFromText,
                      icon: _nlLoading
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('AI 規劃'),
                    ),
                  ],
                ),
                if (_nlSummary != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('已理解（$_nlSource）：$_nlSummary',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  ),
                const Divider(),
                Text('起點：${_start.latitude.toStringAsFixed(4)}, ${_start.longitude.toStringAsFixed(4)}　（點地圖可改）',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text('出發 $_departure'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('行程 ${_duration.round()} 小時', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                Slider(
                  value: _duration,
                  min: 2,
                  max: 12,
                  divisions: 10,
                  label: '${_duration.round()} 小時',
                  onChanged: (v) => setState(() => _duration = v),
                ),
                const Text('包含類別', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: -4,
                  children: _catLabels.entries.map((e) {
                    final selected = _cats.contains(e.key);
                    return FilterChip(
                      label: Text(e.value),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _cats.add(e.key);
                        } else {
                          _cats.remove(e.key);
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _mustCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: '必訪景點（逗號分隔，可留空）',
                          hintText: '大三巴, 媽閣廟',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_cats.contains('food'))
                      Row(
                        children: [
                          const Text('美食上限'),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: _maxFood > 0 ? () => setState(() => _maxFood--) : null,
                          ),
                          Text('$_maxFood'),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: _maxFood < 6 ? () => setState(() => _maxFood++) : null,
                          ),
                        ],
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('無障礙路線（避開階梯與陡坡）', style: TextStyle(fontSize: 13)),
                  value: _accessible,
                  onChanged: (v) => setState(() => _accessible = v),
                ),
                const SizedBox(height: 8),
                if (plan != null) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 20, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${plan.stops.length} 站　·　${plan.distanceText}　·　約 ${plan.durationText}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showStops,
                          icon: const Icon(Icons.list_alt, size: 18),
                          label: const Text('查看行程'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _save,
                          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                          label: const Text('儲存行程'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _generate,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(plan == null ? '產生行程' : '重新產生'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
