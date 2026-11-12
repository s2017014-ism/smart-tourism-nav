// 前端全域設定。
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可在建置時覆寫預設後端位址，例如：
///   flutter build apk --release --dart-define=STN_API_BASE=http://192.168.1.20:8000
const String _defineBase = String.fromEnvironment('STN_API_BASE');

/// 把使用者輸入正規化：補上 http://、去掉結尾斜線。
String normalizeBaseUrl(String input) {
  var u = input.trim();
  if (u.isEmpty) return u;
  if (!u.startsWith('http://') && !u.startsWith('https://')) {
    u = 'http://$u';
  }
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}

/// 各平台的預設後端位址。
///
/// * Android 模擬器：`10.0.2.2` 才是主機的 localhost。
/// * Android 實機：需在 App 內改成電腦的區網 IP（例如 http://192.168.1.20:8000）。
/// * iOS 模擬器 / 桌面 / Web：`127.0.0.1`。
String get defaultApiBaseUrl {
  if (_defineBase.isNotEmpty) return normalizeBaseUrl(_defineBase);
  if (kIsWeb) return 'http://127.0.0.1:8000';
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}

/// 目前使用的後端位址。可在 App 的「後端伺服器設定」修改並持久化。
String apiBaseUrl = defaultApiBaseUrl;

const String _prefsKey = 'stn_api_base';

/// 啟動時載入使用者先前儲存的位址。
Future<void> loadServerConfig() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.trim().isNotEmpty) {
      apiBaseUrl = normalizeBaseUrl(saved);
    }
  } catch (_) {
    // 讀取失敗時沿用預設值
  }
}

/// 儲存新的後端位址（同時更新全域設定）。
Future<void> setApiBaseUrl(String input) async {
  final u = normalizeBaseUrl(input);
  if (u.isEmpty) return;
  apiBaseUrl = u;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, u);
  } catch (_) {
    // 儲存失敗不影響本次使用
  }
}

/// 還原為平台預設值。
Future<void> resetApiBaseUrl() async {
  apiBaseUrl = defaultApiBaseUrl;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  } catch (_) {}
}

/// 澳門本島中心點。
const LatLng macauCenter = LatLng(22.1987, 113.5439);
const double macauInitialZoom = 14;
