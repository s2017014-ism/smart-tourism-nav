// 前端全域設定。
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// 後端 API base url。
///
/// * Android 模擬器：要用 `10.0.2.2` 才連得到主機的 localhost。
/// * iOS 模擬器 / 桌面 / Web：用 `127.0.0.1`。
/// * 實機測試：改成你電腦的區網 IP（例如 http://192.168.1.20:8000）。
String get apiBaseUrl {
  if (kIsWeb) return 'http://127.0.0.1:8000';
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}

/// 澳門本島中心點。
const LatLng macauCenter = LatLng(22.1987, 113.5439);
const double macauInitialZoom = 14;
