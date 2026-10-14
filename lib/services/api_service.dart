import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  // ============================================================
  // LOCAL BACKEND
  // ============================================================

  static const String baseUrl = 'http://10.249.23.234:5000/api';

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
    final data = _decodeResponse(response);

    final message = data['message']?.toString();

    if (message != null && message.trim().isNotEmpty) {
      return Exception(message);
    }

    if (response.statusCode == 401) {
      return Exception('Session expired. Please login again.');
    }

    return Exception(fallbackMessage);
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
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Login failed');
  }

  // ============================================================
  // GET MY TASKS
  // ============================================================

  static Future<Map<String, dynamic>> getMyTasks({
    required String accessToken,
    int page = 1,
    int limit = 100,
    String? status,
    String? priority,
    String? search,
  }) async {
    final queryParameters = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };

    if (status != null && status.trim().isNotEmpty) {
      queryParameters['status'] = status.trim();
    }

    if (priority != null && priority.trim().isNotEmpty) {
      queryParameters['priority'] = priority.trim();
    }

    if (search != null && search.trim().isNotEmpty) {
      queryParameters['search'] = search.trim();
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

    throw _apiException(response, 'Failed to load tasks');
  }

  // ============================================================
  // CREATE VISIT
  // PHOTO + GPS + TASK SITE
  // ============================================================

  static Future<Map<String, dynamic>> createVisit({
    required String accessToken,
    required String siteId,
    String? visitAt,
    String? reportType,
    String? clientName,
    String? branch,
    String? region,
    required double latitude,
    required double longitude,
    String? photoUrl,
    String? photoFileId,
    String? notes,
  }) async {
    final body = <String, dynamic>{
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
    };

    final response = await http.post(
      Uri.parse('$baseUrl/visits'),
      headers: _headers(accessToken: accessToken),
      body: jsonEncode(body),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to create visit');
  }

  // ============================================================
  // CHECK-IN
  // ============================================================

  static Future<Map<String, dynamic>> createCheckIn({
    required String accessToken,
    required String siteId,
    required double latitude,
    required double longitude,
    String? photoUrl,
  }) async {
    final body = <String, dynamic>{
      'siteId': siteId,
      'latitude': latitude,
      'longitude': longitude,
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

    throw _apiException(response, 'Failed to load check-ins');
  }

  // ============================================================
  // GET ACTIVE CHECK-IN FOR SITE
  // ============================================================

  static Future<Map<String, dynamic>?> getActiveCheckInForSite({
    required String accessToken,
    required String siteId,
  }) async {
    final data = await getCheckIns(
      accessToken: accessToken,
      page: 1,
      limit: 100,
      siteId: siteId,
    );

    final rawCheckIns = data['data']?['checkIns'] ?? data['checkIns'] ?? [];

    if (rawCheckIns is! List) {
      return null;
    }

    for (final item in rawCheckIns) {
      if (item is! Map) {
        continue;
      }

      final checkIn = Map<String, dynamic>.from(item);

      final status = checkIn['status']?.toString().toUpperCase() ?? '';

      final returnedSiteId =
          checkIn['siteId']?.toString() ??
          checkIn['site']?['id']?.toString() ??
          '';

      final checkOutAt = checkIn['checkOutAt'];

      if (returnedSiteId == siteId &&
          status == 'CHECKED_IN' &&
          checkOutAt == null) {
        return checkIn;
      }
    }

    return null;
  }

  // ============================================================
  // GET CHECK-IN BY ID
  // ============================================================

  static Future<Map<String, dynamic>> getCheckInById({
    required String accessToken,
    required String checkInId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/check-ins/$checkInId'),
      headers: _headers(accessToken: accessToken),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to load check-in record');
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
  // GET AUDIT CHECKLIST
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

    throw _apiException(response, 'Failed to load audit checklist');
  }

  // ============================================================
  // GET AUDIT TEMPLATE
  // ============================================================

  static Future<Map<String, dynamic>> getAuditTemplate({
    required String accessToken,
    required String templateId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/audit/$templateId'),
      headers: _headers(accessToken: accessToken),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to load audit template');
  }

  // ============================================================
  // SUBMIT AUDIT
  // ============================================================

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

  // ============================================================
  // GET AUDIT SUBMISSION
  // ============================================================

  static Future<Map<String, dynamic>> getAuditSubmission({
    required String accessToken,
    required String visitId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/audit/visits/$visitId/submission'),
      headers: _headers(accessToken: accessToken),
    );

    final data = _decodeResponse(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw _apiException(response, 'Failed to load audit submission');
  }
}
