import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models/itinerary.dart';
import '../models/poi.dart';
import '../models/saved_itinerary.dart';
import '../services/api_client.dart';
import '../services/itinerary_store.dart';
import '../widgets/numbered_marker.dart';
import 'map_screen.dart';

class ItineraryScreen extends StatefulWidget {
  const ItineraryScreen({
    super.key,
    this.initialPlan,
    this.initialSettings,
    this.initialSavedId,
    this.initialName,
  });

  /// 由「我的行程」載入時帶入的既有行程與設定。
  final ItineraryPlan? initialPlan;
  final Map<String, dynamic>? initialSettings;

  /// 由「我的行程」開啟時帶入的既有行程 id／名稱；非 null 表示可覆蓋儲存。
  final String? initialSavedId;
  final String? initialName;

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen> {
  final MapController _mapController = MapController();
  final ApiClient _api = ApiClient();
  final ItineraryStore _store = ItineraryStore();

  LatLng _start = const LatLng(22.19356, 113.53963); // 議事亭前地
  String? _startName; // 以名稱選擇起點時顯示
  bool _locating = false;
  String _departure = '09:00';
  double _duration = 6;
  final Set<String> _cats = {'tourism', 'historic', 'natural', 'curated'};
  int _maxFood = 2;

  ItineraryPlan? _plan;
  bool _loading = false;
  List<Poi> _allPois = [];
  bool _poisLoaded = false;
  bool _accessible = false; // 合併：避開階梯 + 避免陡坡
  String? _savedId;   // 目前對應的已儲存行程 id（用於覆蓋儲存）
  String? _savedName; // 目前對應的已儲存行程名稱
  final TextEditingController _nlCtrl = TextEditingController();
  bool _nlLoading = false;
  String? _nlSummary;
  String? _nlSource;
  bool _panelHidden = false; // 是否收起下方設定面板

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
      _maxFood = (s['max_food_stops'] as num?)?.toInt() ?? _maxFood;
      _accessible = (s['avoid_stairs'] == true) || (s['max_slope_pct'] != null);
    }
    _plan = widget.initialPlan;
    _savedId = widget.initialSavedId;
    _savedName = widget.initialName;
    if (_plan != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit(_plan!));
    }
  }

  @override
  void dispose() {
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
      final plan = await _api.fetchItinerary(
        start: _start,
        departureTime: _departure,
        durationHours: _duration,
        categories: _cats.toList(),
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
      _startName = null;
      _plan = null;
    });
  }

  Future<LatLng> _determinePosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('定位服務未開啟');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('已拒絕定位權限');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('定位權限已被永久拒絕，請至系統設定開啟');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(pos.latitude, pos.longitude);
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final p = await _determinePosition();
      if (!mounted) return;
      setState(() {
        _start = p;
        _startName = '我的位置';
        _plan = null;
        _locating = false;
      });
      _snack('已將我的位置設為起點');
    } catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  void _showStops() {
    final plan = _plan;
    if (plan == null) return;
    // 選取的站序索引（最多兩個）：第一個＝起點、第二個＝終點。
    final selected = <int>[];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void toggle(int i) {
            setSheet(() {
              if (selected.remove(i)) return; // 已選 → 取消
              if (selected.length >= 2) selected.removeAt(0); // 已有兩個 → 換掉第一個
              selected.add(i);
            });
          }

          LatLng? pickedPoint(int i) =>
              (i >= 0 && i < selected.length) ? plan.stops[selected[i]].point : null;

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 8),
                Text('行程共 ${plan.stops.length} 站 · ${plan.distanceText} · 約 ${plan.durationText}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  selected.length < 2 ? '點選兩個景點，即可導航其間路程' : '起點：${plan.stops[selected[0]].name}　→　終點：${plan.stops[selected[1]].name}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    controller: scrollCtrl,
                    itemCount: plan.stops.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = plan.stops[i];
                      final sel = selected.indexOf(i); // 0=起點, 1=終點, -1=未選
                      return ListTile(
                        selected: sel >= 0,
                        selectedTileColor: Colors.blue.withValues(alpha: 0.08),
                        leading: CircleAvatar(
                          backgroundColor: sel >= 0
                              ? (sel == 0 ? Colors.green : Colors.red)
                              : _catColor(s.category),
                          child: Text(
                            sel == 0 ? '起' : (sel == 1 ? '終' : '${s.order}'),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                        title: Text(s.name),
                        subtitle: Text(
                          '${s.arrival}–${s.departure}　${s.categoryLabel}'
                          '${i == 0 ? '' : '　步行 ${s.travelFromPrevM.toStringAsFixed(0)}m'}',
                        ),
                        trailing: Text('${s.dwellMin}分', style: TextStyle(color: Colors.grey.shade600)),
                        onTap: () => toggle(i),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selected.length == 2
                            ? () {
                                final a = pickedPoint(0)!;
                                final b = pickedPoint(1)!;
                                final from = plan.stops[selected[0]].name;
                                final to = plan.stops[selected[1]].name;
                                Navigator.pop(ctx);
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => MapScreen(initialOrigin: a, initialDestination: b),
                                ));
                                _snack('規劃 $from → $to 的路線');
                              }
                            : null,
                        icon: const Icon(Icons.directions),
                        label: Text(selected.length == 2 ? '導航這兩點' : '請選擇兩個景點'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
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
                                    _startName = p.name;
                                    _plan = null;
                                  });
                                  Navigator.pop(ctx);
                                  _snack('已將「${p.name}」設為起點');
                                },
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

  Future<String?> _askName(DateTime now, {String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '澳門行程 ${now.month}/${now.day}');
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
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null) return;

    final now = DateTime.now();
    final settings = <String, dynamic>{
      'start': {'lat': _start.latitude, 'lng': _start.longitude},
      'departure_time': _departure,
      'duration_hours': _duration,
      'categories': _cats.toList(),
      'max_food_stops': _maxFood,
      'avoid_stairs': _accessible,
      'max_slope_pct': _accessible ? 12 : null,
    };

    String? id;
    String? name;
    var overwritten = false;

    if (_savedId != null) {
      // 由「我的行程」開啟的既有行程 → 詢問覆蓋原行程或另存新檔
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('儲存行程'),
          content: Text('此行程由「${_savedName ?? ''}」開啟。\n要覆蓋原行程，還是另存新檔？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'new'), child: const Text('另存新檔')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'overwrite'), child: const Text('覆蓋原行程')),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      if (choice == 'overwrite') {
        id = _savedId;
        name = _savedName ?? '澳門行程 ${now.month}/${now.day}';
        overwritten = true;
      } else {
        name = await _askName(now);
        if (name == null) return;
        id = now.microsecondsSinceEpoch.toString();
      }
    } else {
      name = await _askName(now);
      if (name == null) return;
      id = now.microsecondsSinceEpoch.toString();
    }

    try {
      await _store.save(SavedItinerary(
        id: id!,
        name: name,
        createdAt: now,
        plan: plan,
        settings: settings,
      ));
      if (!mounted) return;
      setState(() {
        _savedId = id;
        _savedName = name;
      });
      _snack(overwritten ? '已覆蓋「$name」' : '已儲存「$name」，可在「我的行程」查看');
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
              _startName = null;
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
          if (_panelHidden)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: _circleButton(
                  Icons.keyboard_arrow_up,
                  '展開下方介面',
                  () => setState(() => _panelHidden = false),
                ),
              ),
            ),
          if (!_panelHidden) _buildPanel(),
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

  Widget _circleButton(IconData icon, String tip, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(tooltip: tip, icon: Icon(icon), onPressed: onTap),
    );
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
                    const Expanded(
                      child: Text(
                        '行程設定',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      tooltip: '收起下方介面',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: () => setState(() => _panelHidden = true),
                    ),
                  ],
                ),
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
                Text(
                  _startName == null
                      ? '起點：${_start.latitude.toStringAsFixed(4)}, ${_start.longitude.toStringAsFixed(4)}（點地圖可改）'
                      : '起點：$_startName（${_start.latitude.toStringAsFixed(4)}, ${_start.longitude.toStringAsFixed(4)}）',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openSearch,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('選擇起點', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _locating ? null : _useMyLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location, size: 18),
                        label: const Text('我的位置', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左：出發時間 + 時長
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickTime,
                            icon: const Icon(Icons.access_time, size: 18),
                            label: Text('出發 $_departure'),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '行程 ${_duration.round()} 小時',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Slider(
                            value: _duration,
                            min: 2,
                            max: 12,
                            divisions: 10,
                            label: '${_duration.round()} 小時',
                            onChanged: (v) => setState(() => _duration = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 右：類別 + 無障礙
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '包含類別',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 6,
                            runSpacing: -4,
                            children: _catLabels.entries.map((e) {
                              final selected = _cats.contains(e.key);
                              return FilterChip(
                                label: Text(e.value, style: const TextStyle(fontSize: 12)),
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
                          if (_cats.contains('food'))
                            Row(
                              children: [
                                const Text('美食上限', style: TextStyle(fontSize: 12)),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                                  onPressed:
                                      _maxFood > 0 ? () => setState(() => _maxFood--) : null,
                                ),
                                Text('$_maxFood', style: const TextStyle(fontSize: 12)),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.add_circle_outline, size: 18),
                                  onPressed:
                                      _maxFood < 6 ? () => setState(() => _maxFood++) : null,
                                ),
                              ],
                            ),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '無障礙路線',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Switch(
                                value: _accessible,
                                onChanged: (v) => setState(() => _accessible = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
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
