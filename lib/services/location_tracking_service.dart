import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

class LocationTrackingService {
  static StreamSubscription<Position>? _positionSubscription;

  static String? _accessToken;

  static bool _started = false;

  static DateTime? _lastUploadedAt;

  static const Duration _uploadInterval = Duration(seconds: 30);

  static final Battery _battery = Battery();

  static Future<bool> start({required String accessToken}) async {
    if (_started) {
      return true;
    }

    _accessToken = accessToken;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      final androidSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 30),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Supervisor Tracking',
          notificationText: 'Your location is being updated.',
          notificationChannelName: 'Supervisor Location Tracking',
          setOngoing: true,
          enableWakeLock: false,
          enableWifiLock: false,
        ),
      );

      _positionSubscription =
          Geolocator.getPositionStream(locationSettings: androidSettings)
              .listen(
                (Position position) async {
                  await _handlePosition(position);
                },
                onError: (error) {},
                cancelOnError: false,
              );

      _started = true;

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: androidSettings,
        );

        await _handlePosition(position, force: true);
      } catch (_) {}

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _handlePosition(
    Position position, {
    bool force = false,
  }) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      return;
    }

    final now = DateTime.now();

    if (!force &&
        _lastUploadedAt != null &&
        now.difference(_lastUploadedAt!) < _uploadInterval) {
      return;
    }

    final int batteryLevel = await _getBatteryLevel();

    final uploaded = await _uploadLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      batteryLevel: batteryLevel,
    );

    if (uploaded) {
      _lastUploadedAt = now;
    }
  }

  static Future<int> _getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;

      return level.clamp(0, 100).toInt();
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> _uploadLocation({
    required double latitude,
    required double longitude,
    required int batteryLevel,
  }) async {
    final token = _accessToken;

    if (token == null || token.isEmpty) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/location'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'batteryLevel': batteryLevel,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    await _positionSubscription?.cancel();

    _positionSubscription = null;

    _accessToken = null;

    _lastUploadedAt = null;

    _started = false;
  }

  static bool get isRunning {
    return _started;
  }
}
