import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

class LocationTrackingService {
  static StreamSubscription<Position>? _positionSubscription;
  static Timer? _periodicTimer;
  static String? _accessToken;
  static bool _started = false;
  static DateTime? _lastUploadedAt;
  static const Duration _uploadInterval = Duration(seconds: 15);
  static final Battery _battery = Battery();

  static Future<bool> start({required String accessToken}) async {
    if (_started) return true;
    _accessToken = accessToken;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );

      _positionSubscription =
          Geolocator.getPositionStream(locationSettings: locationSettings)
              .listen(
                (Position position) async {
                  await _handlePosition(position);
                },
                onError: (error) {},
                cancelOnError: false,
              );

      _periodicTimer?.cancel();
      _periodicTimer = Timer.periodic(_uploadInterval, (_) async {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: locationSettings,
          );
          await _handlePosition(pos, force: true);
        } catch (_) {}
      });

      _started = true;

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
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
    final token = _accessToken;
    if (token == null || token.isEmpty) return;

    final now = DateTime.now();
    if (!force &&
        _lastUploadedAt != null &&
        now.difference(_lastUploadedAt!) < _uploadInterval) {
      return;
    }

    _lastUploadedAt = now;

    int? batteryPercentage;
    try {
      batteryPercentage = await _battery.batteryLevel;
    } catch (_) {
      batteryPercentage = null;
    }

    try {
      await http.post(
        Uri.parse('${ApiService.baseUrl}/location'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'batteryPercentage': batteryPercentage,
        }),
      );
    } catch (_) {}
  }

  static Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _started = false;
    _accessToken = null;
    _lastUploadedAt = null;
  }
}
