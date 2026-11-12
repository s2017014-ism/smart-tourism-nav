import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';
import '../models/transit_plan.dart';
import '../models/weather.dart';
import '../services/api_client.dart';
import '../widgets/numbered_marker.dart';
import 'itinerary_screen.dart';
import 'saved_itineraries_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.initialOrigin, this.initialDestination});

  /// 由行程頁帶入的起點／終點；兩者皆有時，進入後自動規劃路線。
  final LatLng? initialOrigin;
  final LatLng? initialDestination;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final ApiClient _api = ApiClient();

  LatLng? _origin;
  LatLng? _destination;
  RoutePlan? _plan;
  TransitPlan? _transitPlan;

  bool _accessible = false; // 合併：避開階梯 + 避免陡坡
  bool _rainMode = false;   // 雨天模式（提高步行成本）
  bool _rainModeTouched = false; // 使用者是否手動調整過雨天模式
  Weather? _weather;
  bool _transitMode = false;
  bool _loading = false;
  bool _topHidden = false;
  bool _bottomHidden = false;
  bool _pickOrigin = true; // 地圖點擊要設定哪個端點
  String? _transitTime; // null = 現在

  LatLng? _myLocation;
  List<Poi> _allPois = [];
  bool _poisLoaded = false;
  bool _locating = false;

  // ---- 即時導航 ----
  StreamSubscription<Position>? _positionSub;
  bool _navigating = false;
  bool _deviationPrompted = false;
  bool _offRouteDialogShowing = false;
  static const double _offRouteThresholdM = 60;

  @override
  void initState() {
    super.initState();
    _checkBackend();
    _loadWeather();
    if (widget.initialOrigin != null) _origin = widget.initialOrigin;
    if (widget.initialDestination != null) _destination = widget.initialDestination;
    if (_origin != null && _destination != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _planRoute());
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _loadWeather() async {
    try {
      final w = await _api.fetchWeather();
      if (!mounted) return;
      setState(() {
        _weather = w;
        // 現時有雨 → 自動開啟雨天模式（若使用者尚未手動調整過）。
        if (!_rainModeTouched && w.isRaining) _rainMode = true;
      });
    } catch (_) {
      // 天氣為附加功能，失敗時靜默略過
    }
  }

  Future<void> _checkBackend() async {
    final ok = await _api.health();
    if (!mounted) return;
    if (!ok) {
      _snack('無法連線後端（$apiBaseUrl）。請啟動 FastAPI，或到右上角設定後端位址。');
    }
  }

  /// 讓使用者設定後端位址（APK 安裝在手機時必用：改填電腦的區網 IP）。
  Future<void> _openServerSettings() async {
    final ctrl = TextEditingController(text: apiBaseUrl);
    String? message;
    bool ok = false;
    bool testing = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: const Text('後端伺服器設定'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '手機與電腦需在同一個 Wi-Fi。請填入手機可連到的電腦區網 IP，'
                    '例如 http://192.168.1.20:8000；iOS／桌面／Web 可用 127.0.0.1。',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'API 位址',
                      hintText: 'http://192.168.1.20:8000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      message!,
                      style: TextStyle(
                        fontSize: 13,
                        color: ok ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ctrl.text = defaultApiBaseUrl;
                  setSt(() {
                    message = null;
                    ok = false;
                  });
                },
                child: const Text('還原預設'),
              ),
              TextButton(
                onPressed: testing
                    ? null
                    : () async {
                        final target = normalizeBaseUrl(ctrl.text);
                        if (target.isEmpty) return;
                        setSt(() {
                          testing = true;
                          message = null;
                        });
                        final good = await _api.health(baseUrl: target);
                        if (!ctx.mounted) return;
                        setSt(() {
                          testing = false;
                          ok = good;
                          message = good
                              ? '連線成功：$target'
                              : '連線失敗。請確認後端已啟動、IP 正確、同一 Wi-Fi，且防火牆已開放 8000。';
                        });
                      },
                child: testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('測試連線'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  await setApiBaseUrl(ctrl.text);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _snack('已儲存後端位址：$apiBaseUrl');
                  _checkBackend();
                },
                child: const Text('儲存'),
              ),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
  }

  void _onTap(TapPosition _, LatLng point) {
    setState(() {
      if (_pickOrigin) {
        _origin = point;
        _pickOrigin = false; // 接著設定終點
      } else {
        _destination = point;
      }
      _plan = null;
      _transitPlan = null;
    });
  }

  Future<void> _planRoute() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) {
      _snack('請先設定起點與終點（可在上方切換要設定的端點）。');
      return;
    }

    setState(() => _loading = true);
    try {
      if (_transitMode) {
        final plan = await _api.fetchTransitRoute(
          origin: origin,
          destination: destination,
          avoidStairs: _accessible,
          maxSlopePct: _accessible ? 12 : null,
          avoidRain: _rainMode,
          departureTime: _transitTime,
        );
        if (!mounted) return;
        setState(() {
          _transitPlan = plan;
          _plan = null;
          _loading = false;
        });
        _fitToPoints(plan.points);
      } else {
        final plan = await _api.fetchRoute(
          origin: origin,
          destination: destination,
          avoidStairs: _accessible,
          maxSlopePct: _accessible ? 12 : null,
          avoidRain: _rainMode,
        );
        if (!mounted) return;
        setState(() {
          _plan = plan;
          _transitPlan = null;
          _loading = false;
        });
        _fitToPoints(plan.points);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('規劃失敗：$e');
    }
  }

  void _fitToPoints(List<LatLng> points) {
    if (points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(48),
        ),
      );
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickTransitTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    setState(() {
      _transitTime = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      _transitPlan = null;
    });
  }

  void _clear() {
    setState(() {
      _origin = null;
      _destination = null;
      _plan = null;
      _transitPlan = null;
      _pickOrigin = true;
    });
  }

  void _setEndpoint(LatLng p, {required bool asOrigin}) {
    setState(() {
      if (asOrigin) {
        _origin = p;
      } else {
        _destination = p;
      }
      _plan = null;
      _transitPlan = null;
    });
  }

  // ---- 搜尋景點設為起點／終點 ----
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
                                title: Text(p.name),
                                subtitle: Text(p.categoryLabel),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: '設為起點',
                                      icon: const Icon(Icons.trip_origin, color: Colors.green),
                                      onPressed: () {
                                        _setEndpoint(p.point, asOrigin: true);
                                        Navigator.pop(ctx);
                                        _snack('已將「${p.name}」設為起點');
                                      },
                                    ),
                                    IconButton(
                                      tooltip: '設為終點',
                                      icon: const Icon(Icons.place, color: Colors.red),
                                      onPressed: () {
                                        _setEndpoint(p.point, asOrigin: false);
                                        Navigator.pop(ctx);
                                        _snack('已將「${p.name}」設為終點');
                                      },
                                    ),
                                  ],
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

  // ---- 使用目前位置 ----
  Future<void> _ensureLocationPermission() async {
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
  }

  Future<LatLng> _determinePosition() async {
    await _ensureLocationPermission();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(pos.latitude, pos.longitude);
  }

  Future<void> _useMyLocation({required bool asOrigin}) async {
    setState(() => _locating = true);
    try {
      final p = await _determinePosition();
      if (!mounted) return;
      setState(() {
        _myLocation = p;
        _locating = false;
      });
      _setEndpoint(p, asOrigin: asOrigin);
      _snack(asOrigin ? '已將我的位置設為起點' : '已將我的位置設為終點');
    } catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  // ---- 即時導航 ----
  List<LatLng> _currentRoutePoints() {
    final t = _transitPlan;
    if (t != null) return t.points;
    return _plan?.points ?? const <LatLng>[];
  }

  Future<void> _startNavigation() async {
    if (_currentRoutePoints().length < 2) {
      _snack('請先規劃路線，再開始導航。');
      return;
    }
    try {
      await _ensureLocationPermission();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
      return;
    }
    await _positionSub?.cancel();
    setState(() {
      _navigating = true;
      _deviationPrompted = false;
    });
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final p = LatLng(pos.latitude, pos.longitude);
      final first = _myLocation == null;
      setState(() => _myLocation = p);
      if (first) _mapController.move(p, 17);
      _checkDeviation(p);
    }, onError: (e) {
      if (!mounted) return;
      _snack('GPS 讀取失敗：$e');
      _stopNavigation();
    });
    _snack('已開始即時導航，正在接收 GPS…');
  }

  void _stopNavigation() {
    _positionSub?.cancel();
    _positionSub = null;
    if (!mounted) return;
    setState(() {
      _navigating = false;
      _deviationPrompted = false;
    });
    _snack('已停止導航');
  }

  void _checkDeviation(LatLng p) {
    if (!_navigating) return;
    final pts = _currentRoutePoints();
    if (pts.length < 2) return;
    final dist = _distanceToRouteMeters(p, pts);
    if (dist > _offRouteThresholdM) {
      if (_deviationPrompted) return;
      _deviationPrompted = true;
      _promptReroute();
    } else if (dist < _offRouteThresholdM * 0.6) {
      // 回到路線附近：允許下次再提示
      _deviationPrompted = false;
    }
  }

  Future<void> _promptReroute() async {
    if (_offRouteDialogShowing || !mounted) return;
    _offRouteDialogShowing = true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('已偏離原定路線'),
        content: const Text('您目前不在原定路線上，是否要從目前位置重新規劃？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('繼續原路線'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重新規劃'),
          ),
        ],
      ),
    );
    _offRouteDialogShowing = false;
    if (choice == true && mounted) {
      final me = _myLocation;
      if (me == null) return;
      setState(() {
        _origin = me;
        _plan = null;
        _transitPlan = null;
        _deviationPrompted = false;
      });
      await _planRoute();
    }
  }

  double _distanceToRouteMeters(LatLng p, List<LatLng> pts) {
    var best = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = i + 1 < pts.length ? pts[i + 1] : pts[i];
      final d = _distanceToSegmentMeters(p, a, b);
      if (d < best) best = d;
    }
    return best;
  }

  double _distanceToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    // 以 p 為原點的局部等距投影（公尺），短距離足夠準確。
    final latRad = p.latitude * math.pi / 180;
    const mPerDegLat = 110540.0;
    final mPerDegLng = 111320.0 * math.cos(latRad);
    double x(LatLng q) => (q.longitude - p.longitude) * mPerDegLng;
    double y(LatLng q) => (q.latitude - p.latitude) * mPerDegLat;
    final ax = x(a), ay = y(a);
    final bx = x(b), by = y(b);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = 0.0;
    if (len2 > 0) {
      t = (-ax * dx - ay * dy) / len2;
      if (t < 0) t = 0;
      if (t > 1) t = 1;
    }
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    return math.sqrt(cx * cx + cy * cy);
  }

  List<Polyline> _polylines() {
    final t = _transitPlan;
    if (t != null) {
      return t.legs
          .where((l) => l.points.length > 1)
          .map((l) => Polyline(
                points: l.points,
                strokeWidth: 5,
                color: l.mode == 'bus' ? Colors.deepPurple.shade600 : Colors.blue.shade700,
              ))
          .toList();
    }
    if (_plan != null && _plan!.points.length > 1) {
      return [Polyline(points: _plan!.points, strokeWidth: 5, color: Colors.blue.shade700)];
    }
    return const [];
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    final t = _transitPlan;
    if (t != null) {
      for (final leg in t.legs) {
        if (leg.mode != 'bus') continue;
        for (final p in leg.stopCoords) {
          markers.add(Marker(
            point: p,
            width: 14,
            height: 14,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ));
        }
      }
    }

    if (_myLocation != null) {
      markers.add(Marker(
        point: _myLocation!,
        width: 22,
        height: 22,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
      ));
    }

    if (_origin != null) {
      markers.add(Marker(
        point: _origin!,
        width: 30,
        height: 30,
        child: const EndpointMarker(icon: Icons.trip_origin, color: Colors.green),
      ));
    }
    if (_destination != null) {
      markers.add(Marker(
        point: _destination!,
        width: 30,
        height: 30,
        child: const EndpointMarker(icon: Icons.place, color: Colors.red),
      ));
    }
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

  Widget _targetSelector() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _pickOrigin = true),
            icon: Icon(Icons.trip_origin, size: 18, color: _pickOrigin ? Colors.green : Colors.grey),
            label: const Text('設定起點', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              backgroundColor: _pickOrigin ? Colors.green.shade50 : null,
              side: BorderSide(color: _pickOrigin ? Colors.green : Colors.grey.shade400),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _pickOrigin = false),
            icon: Icon(Icons.place, size: 18, color: !_pickOrigin ? Colors.red : Colors.grey),
            label: const Text('設定終點', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              backgroundColor: !_pickOrigin ? Colors.red.shade50 : null,
              side: BorderSide(color: !_pickOrigin ? Colors.red : Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = _polylines();
    return Scaffold(
      appBar: _topHidden
          ? null
          : AppBar(
              title: const Text('適應型智慧旅遊導航'),
              actions: [
                IconButton(
                  tooltip: '收起上方介面',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: () => setState(() => _topHidden = true),
                ),
                IconButton(tooltip: '搜尋景點', icon: const Icon(Icons.search), onPressed: _openSearch),
                IconButton(
                  tooltip: '智慧行程規劃',
                  icon: const Icon(Icons.auto_awesome),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ItineraryScreen()),
                  ),
                ),
                IconButton(
                  tooltip: '我的行程',
                  icon: const Icon(Icons.bookmarks_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SavedItinerariesScreen()),
                  ),
                ),
                IconButton(
                  tooltip: '後端伺服器設定',
                  icon: const Icon(Icons.settings_ethernet),
                  onPressed: _openServerSettings,
                ),
                IconButton(onPressed: _clear, icon: const Icon(Icons.delete_outline), tooltip: '清除'),
              ],
            ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: macauCenter,
              initialZoom: macauInitialZoom,
              minZoom: 11,
              maxZoom: 19,
              onTap: _onTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'mo.um.smartnav.smart_tourism_nav',
              ),
              if (lines.isNotEmpty) PolylineLayer(polylines: lines),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          if (_loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_topHidden)
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: _circleButton(
                    Icons.keyboard_arrow_down,
                    '展開上方介面',
                    () => setState(() => _topHidden = false),
                  ),
                ),
              ),
            ),
          if (_bottomHidden)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: _circleButton(
                  Icons.keyboard_arrow_up,
                  '展開下方介面',
                  () => setState(() => _bottomHidden = false),
                ),
              ),
            ),
          if (!_bottomHidden) _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final plan = _plan;
    final transit = _transitPlan;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _origin == null || _destination == null
                            ? '點地圖設定「${_pickOrigin ? '起點' : '終點'}」'
                            : '已選好兩點，按「規劃路線」',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: '收起下方介面',
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: () => setState(() => _bottomHidden = true),
                    ),
                  ],
                ),
                _targetSelector(),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _locating ? null : () => _useMyLocation(asOrigin: true),
                        icon: _locating
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location, size: 18),
                        label: const Text('定位為起點', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _locating ? null : () => _useMyLocation(asOrigin: false),
                        icon: const Icon(Icons.my_location, size: 18),
                        label: const Text('定位為終點', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('無障礙路線（避開階梯與陡坡）'),
                  value: _accessible,
                  onChanged: (v) => setState(() => _accessible = v),
                ),
                if (_weather != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '目前天氣：${_weather!.label}'
                      '${_weather!.isRaining ? '　（現時有雨${_rainMode ? '，已自動開啟雨天模式' : ''}）' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('雨天模式（少走路，多搭車）'),
                  subtitle: _weather?.isRaining == true
                      ? const Text('現時有雨，已自動開啟', style: TextStyle(fontSize: 11))
                      : null,
                  value: _rainMode,
                  onChanged: (v) => setState(() {
                    _rainMode = v;
                    _rainModeTouched = true;
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('大眾運輸（走 + 公車）'),
                  value: _transitMode,
                  onChanged: (v) => setState(() {
                    _transitMode = v;
                    _plan = null;
                    _transitPlan = null;
                  }),
                ),
                if (_transitMode)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule, size: 18),
                        const SizedBox(width: 8),
                        Text('出發時間：${_transitTime ?? '現在'}'),
                        const Spacer(),
                        TextButton(onPressed: _pickTransitTime, child: const Text('選擇')),
                        if (_transitTime != null)
                          TextButton(
                            onPressed: () => setState(() {
                              _transitTime = null;
                              _transitPlan = null;
                            }),
                            child: const Text('現在'),
                          ),
                      ],
                    ),
                  ),
                if (transit != null) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.directions_bus, size: 20, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${transit.modeText}（${transit.departureTime} 出發）　·　${transit.distanceText}　·　約 ${transit.durationText}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...transit.legs.asMap().entries.map((e) {
                    final afterBus = e.key > 0 && transit.legs[e.key - 1].mode == 'bus';
                    return _legRow(e.key + 1, e.value, afterBus: afterBus);
                  }),
                ] else if (plan != null) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.route, size: 20, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        '${plan.distanceText}　·　約 ${plan.durationText}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
                if (plan != null || transit != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: _navigating
                        ? OutlinedButton.icon(
                            onPressed: _stopNavigation,
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text('停止即時導航'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: _startNavigation,
                            icon: const Icon(Icons.navigation),
                            label: const Text('開始即時導航（顯示 GPS）'),
                          ),
                  ),
                  if (_navigating)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.gps_fixed, size: 14, color: Colors.green),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '即時導航中：偏離路線時會詢問是否重新規劃',
                              style: TextStyle(fontSize: 11, color: Colors.green),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _planRoute,
                    icon: Icon(_transitMode ? Icons.directions_bus : Icons.directions_walk),
                    label: const Text('規劃路線'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _legRow(int index, TransitLeg leg, {bool afterBus = false}) {
    final isBus = leg.mode == 'bus';
    final minutes = (leg.durationS / 60).round();
    final transfer = isBus && afterBus;
    final text = isBus
        ? '${transfer ? '轉乘 ' : ''}搭 ${leg.route} 路：在「${leg.fromName}」上車 → 在「${leg.toName}」下車（${leg.numStops} 站，約 $minutes 分）'
        : '步行 ${leg.distanceM.toStringAsFixed(0)} 公尺（約 $minutes 分）';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            transfer
                ? Icons.sync_alt
                : (isBus ? Icons.directions_bus : Icons.directions_walk),
            size: 18,
            color: transfer
                ? Colors.orange.shade800
                : (isBus ? Colors.deepPurple : Colors.blue),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text('$index. $text', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
