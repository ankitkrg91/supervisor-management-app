import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  // ============================================================
  // ENVIRONMENT CONFIGURATION (LOCAL TESTING SWITCH)
  // ============================================================
  // Set isLocalTest = true for local testing, false for live Render.
  static const bool isLocalTest = true;

  static const String _localUrl = 'http://10.250.21.234:5000/api';
  static const String _liveUrl =
      'https://supervisor-management-backend.onrender.com/api';

  static String get baseUrl => isLocalTest ? _localUrl : _liveUrl;

  //============================================================
  // COMMON HELPERS
  // ============================================================

  static Map<String, String> _headers({String? accessToken}) {
    return {
      'Content-Type': 'application/json',
      if (accessToken != null && accessToken.trim().isNotEmpty)
        'Authorization': 'Bearer ${accessToken.trim()}',
    };
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }

      return {};
    } catch (_) {
      return {};
    }
  }

  static Exception _apiException(
    http.Response response,
    String fallbackMessage,
  ) {
    final decoded = _decodeResponse(response);

    final message = decoded['message']?.toString().trim();

    if (message != null && message.isNotEmpty) {
      return Exception(message);
    }

    final error = decoded['error']?.toString().trim();

    if (error != null && error.isNotEmpty) {
      return Exception(error);
    }

    return Exception('$fallbackMessage (Status code: ${response.statusCode})');
  }

  // ============================================================
  // SUPERVISOR LOGIN
  // ============================================================

  static Future<Map<String, dynamic>> supervisorLogin({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/supervisor-login'),
      headers: _headers(),
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Login failed');
  }

  // ============================================================
  // UPDATE PASSWORD
  // ============================================================

  static Future<Map<String, dynamic>> updatePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/change-password'),
      headers: _headers(accessToken: accessToken),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Password update failed');
  }

  // ============================================================
  // GET TASKS
  // ============================================================

  static Future<Map<String, dynamic>> getTasks({
    required String accessToken,
    int page = 1,
    int limit = 100,
    String? status,
  }) async {
    final queryParameters = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };

    if (status != null && status.trim().isNotEmpty) {
      queryParameters['status'] = status.trim();
    }

    final uri = Uri.parse('$baseUrl/tasks')
        .replace(queryParameters: queryParameters);

    final response = await http.get(
      uri,
      headers: _headers(accessToken: accessToken),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to fetch tasks');
  }

  // ============================================================
  // UPDATE TASK STATUS
  // ============================================================

  static Future<Map<String, dynamic>> updateTaskStatus({
    required String accessToken,
    required String taskId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/tasks/$taskId/status'),
      headers: _headers(accessToken: accessToken),
      body: jsonEncode({'status': status.trim()}),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to update task status');
  }

  // ============================================================
  // CREATE VISIT
  // ============================================================

  static Future<Map<String, dynamic>> createVisit({
    required String accessToken,
    required String siteId,
    required String visitAt,
    String? reportType,
    String? clientName,
    String? branch,
    String? region,
    double? latitude,
    double? longitude,
    String? photoUrl,
    String? photoFileId,
    String? notes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/visits'),
      headers: _headers(accessToken: accessToken),
      body: jsonEncode({
        'siteId': siteId,
        'visitAt': visitAt,
        'reportType': reportType,
        'clientName': clientName,
        'branch': branch,
        'region': region,
        'latitude': latitude,
        'longitude': longitude,
        'photoUrl': photoUrl,
        'photoFileId': photoFileId,
        'notes': notes,
      }),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to create visit');
  }

  // ============================================================
  // CHECK-IN (SUPPORTS STANDARD & RAIN/EMERGENCY EXCEPTION)
  // ============================================================

  static Future<Map<String, dynamic>> createCheckIn({
    required String accessToken,
    required String siteId,
    required double latitude,
    required double longitude,
    String? photoUrl,
    bool isAlternate = false,
    String? alternateReason,
  }) async {
    final body = <String, dynamic>{
      'siteId': siteId,
      'latitude': latitude,
      'longitude': longitude,
      if (isAlternate) 'isAlternate': true,
      if (alternateReason != null && alternateReason.trim().isNotEmpty)
        'alternateReason': alternateReason.trim(),
    };
    if (photoUrl != null && photoUrl.isNotEmpty) {
      body['photoUrl'] = photoUrl;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/check-ins'),
      headers: _headers(accessToken: accessToken),
      body: jsonEncode(body),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Check-in failed');
  }

  // ============================================================
  // GET MY CHECK-INS
  // ============================================================

  static Future<Map<String, dynamic>> getCheckIns({
    required String accessToken,
    int page = 1,
    int limit = 100,
    String? siteId,
  }) async {
    final queryParameters = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      'role': 'SUPERVISOR',
    };

    if (siteId != null && siteId.trim().isNotEmpty) {
      queryParameters['siteId'] = siteId.trim();
    }

    final uri = Uri.parse('$baseUrl/check-ins')
        .replace(queryParameters: queryParameters);

    final response = await http.get(
      uri,
      headers: _headers(accessToken: accessToken),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to fetch check-ins');
  }

  // ============================================================
  // GET VISITS HISTORY
  // ============================================================

  static Future<Map<String, dynamic>> getVisits({
    required String accessToken,
    int page = 1,
    int limit = 20,
    String? from,
    String? to,
    String? status,
    String? search,
  }) async {
    final queryParameters = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };

    if (from != null && from.trim().isNotEmpty) {
      queryParameters['from'] = from.trim();
    }

    if (to != null && to.trim().isNotEmpty) {
      queryParameters['to'] = to.trim();
    }

    if (status != null && status.trim().isNotEmpty) {
      queryParameters['status'] = status.trim();
    }

    if (search != null && search.trim().isNotEmpty) {
      queryParameters['search'] = search.trim();
    }

    final uri = Uri.parse('$baseUrl/visits')
        .replace(queryParameters: queryParameters);

    final response = await http.get(
      uri,
      headers: _headers(accessToken: accessToken),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to fetch visits history');
  }

  // ============================================================
  // GET ACTIVE CHECK-IN FOR USER
  // ============================================================

  static Future<Map<String, dynamic>?> getActiveCheckIn({
    required String accessToken,
  }) async {
    final response = await getCheckIns(
      accessToken: accessToken,
      page: 1,
      limit: 10,
    );

    final data = response['data'];

    List<dynamic> checkIns = [];

    if (data is Map && data['checkIns'] is List) {
      checkIns = data['checkIns'];
    } else if (response['checkIns'] is List) {
      checkIns = response['checkIns'];
    }

    for (final item in checkIns) {
      if (item is Map) {
        final status = item['status']?.toString().toUpperCase();

        final checkOutAt = item['checkOutAt'];

        if (status == 'CHECKED_IN' && checkOutAt == null) {
          return Map<String, dynamic>.from(item);
        }
      }
    }

    return null;
  }

  // ============================================================
  // CHECK-OUT
  // ============================================================

  static Future<Map<String, dynamic>> checkOut({
    required String accessToken,
    required String checkInId,
    required double latitude,
    required double longitude,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/check-ins/$checkInId/check-out'),
      headers: _headers(accessToken: accessToken),
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Check-out failed');
  }

  // ============================================================
  // AUDIT APIS
  // ============================================================

  static Future<Map<String, dynamic>> getAuditChecklist({
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/audit/checklist'),
      headers: _headers(accessToken: accessToken),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to fetch audit checklist');
  }

  static Future<Map<String, dynamic>> submitAudit({
    required String accessToken,
    required String visitId,
    required String templateId,
    required List<Map<String, dynamic>> answers,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/audit/visits/$visitId/submit'),
      headers: _headers(accessToken: accessToken),
      body: jsonEncode({'templateId': templateId, 'answers': answers}),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to submit audit');
  }
}