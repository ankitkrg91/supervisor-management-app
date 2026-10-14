import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import 'audit_screen.dart';
import 'check_in_check_out_screen.dart';
import 'visit_capture_screen.dart';

class MyTasksScreen extends StatefulWidget {
  final String accessToken;
  final Map<String, dynamic>? user;
  const MyTasksScreen({super.key, required this.accessToken, this.user});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  bool _loading = true;
  bool _startingAudit = false;
  String _errorMessage = '';
  List<Map<String, dynamic>> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      setState(() {
        _loading = true;
        _errorMessage = '';
      });
      final List<Map<String, dynamic>> allTasks = [];
      int page = 1, totalPages = 1;
      do {
        final response = await http.get(
          Uri.parse('${ApiService.baseUrl}/tasks?page=$page&limit=100'),
          headers: {
            'Authorization': 'Bearer ${widget.accessToken}',
            'Content-Type': 'application/json',
          },
        );
        final data = _decodeResponse(response);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(data['message'] ?? 'Failed to load tasks.');
        }
        final rawTasks = data['data']?['tasks'] ?? data['tasks'] ?? [];
        if (rawTasks is List) {
          for (final item in rawTasks) {
            if (item is Map) {
              final task = Map<String, dynamic>.from(item);
              final status =
                  task['status']?.toString().toUpperCase() ?? 'SCHEDULED';
              if (status == 'SCHEDULED' || status == 'IN_PROGRESS')
                allTasks.add(task);
            }
          }
        }
        final pagination =
            data['data']?['pagination'] ?? data['pagination'] ?? {};
        totalPages = int.tryParse('${pagination['totalPages'] ?? 1}') ?? 1;
        page++;
      } while (page <= totalPages);

      if (!mounted) return;
      setState(() {
        _tasks = allTasks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final v = jsonDecode(response.body);
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }

  String _extractValue(String? description, String key) {
    if (description == null || description.trim().isEmpty) return '';
    for (final line in description.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('$key:'.toLowerCase())) {
        return trimmed.substring(key.length + 1).trim();
      }
    }
    return '';
  }

  String _getCategory(Map<String, dynamic> t) =>
      _extractValue(t['description']?.toString(), 'Category');
  String _getType(Map<String, dynamic> t) =>
      _extractValue(t['description']?.toString(), 'Type');
  String _getClient(Map<String, dynamic> t) {
    final c = _extractValue(t['description']?.toString(), 'Client');
    return c.isNotEmpty ? c : (t['clientName']?.toString() ?? '');
  }

  String _getClientMobile(Map<String, dynamic> t) {
    for (final k in ['Client Phone', 'Client Mobile']) {
      final v = _extractValue(t['description']?.toString(), k);
      if (v.isNotEmpty) return v;
    }
    return t['clientMobile']?.toString() ?? t['clientPhone']?.toString() ?? '';
  }

  Future<String> _createVisitForAudit(Map<String, dynamic> task) async {
    final site = task['site'];
    final siteMap = site is Map
        ? Map<String, dynamic>.from(site)
        : <String, dynamic>{};
    final siteId =
        siteMap['id']?.toString() ?? task['siteId']?.toString() ?? '';
    final siteName = siteMap['name']?.toString() ?? '';
    final siteCode = siteMap['siteCode']?.toString() ?? '';
    final taskId = task['id']?.toString() ?? '';
    final title = task['title']?.toString() ?? 'Audit';
    if (siteId.isEmpty || taskId.isEmpty || !mounted) return '';

    final captureResult = await Navigator.of(context)
        .push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (_) =>
                VisitCaptureScreen(siteName: siteName, siteCode: siteCode),
          ),
        );
    if (captureResult == null) return '';

    final photoUrl = captureResult['photoUrl']?.toString().trim() ?? '';
    final latitude = (captureResult['latitude'] as num?)?.toDouble();
    final longitude = (captureResult['longitude'] as num?)?.toDouble();
    if (photoUrl.isEmpty || latitude == null || longitude == null) {
      throw Exception('Site evidence photos and GPS are required.');
    }

    final evidenceJson = jsonEncode({
      'nameplate': captureResult['namePlatePhoto']?.toString() ?? '',
      'selfie': captureResult['selfiePhoto']?.toString() ?? '',
      'photo1': captureResult['sitePhoto']?.toString() ?? photoUrl,
    });

    final notes = [
      'Task ID: $taskId',
      'Task: $title',
      if (siteCode.isNotEmpty) 'Site Code: $siteCode',
      if (siteName.isNotEmpty) 'Site: $siteName',
      '[SITE_EVIDENCE]: $evidenceJson',
    ].join('\n');

    final response = await ApiService.createVisit(
      accessToken: widget.accessToken,
      siteId: siteId,
      visitAt: DateTime.now().toUtc().toIso8601String(),
      reportType: _getType(task).isNotEmpty ? _getType(task) : 'Audit',
      clientName: _getClient(task).isNotEmpty ? _getClient(task) : null,
      latitude: latitude,
      longitude: longitude,
      photoUrl: photoUrl,
      photoFileId: captureResult['photoFileId']?.toString(),
      notes: notes,
    );
    final visit = response['data']?['visit'] ?? response['visit'];
    return visit?['id']?.toString() ?? '';
  }

  Future<bool> _ensureTaskCheckIn(Map<String, dynamic> task) async {
    final site = task['site'];
    final siteMap = site is Map
        ? Map<String, dynamic>.from(site)
        : <String, dynamic>{};
    final siteId =
        siteMap['id']?.toString() ?? task['siteId']?.toString() ?? '';
    if (siteId.isEmpty || !mounted) return false;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CheckInCheckOutScreen(
          accessToken: widget.accessToken,
          user: widget.user ?? {},
          taskSiteId: siteId,
          taskSiteName: siteMap['name']?.toString(),
          taskSiteCode: siteMap['siteCode']?.toString(),
          taskSiteLatitude: (siteMap['latitude'] as num?)?.toDouble(),
          taskSiteLongitude: (siteMap['longitude'] as num?)?.toDouble(),
          returnAfterCheckIn: true,
        ),
      ),
    );
    return result == true;
  }

  Future<void> _updateTaskStatus(String taskId, String status) async {
    await http.patch(
      Uri.parse('${ApiService.baseUrl}/tasks/$taskId/status'),
      headers: {
        'Authorization': 'Bearer ${widget.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'status': status}),
    );
  }

  Future<void> _startAudit(Map<String, dynamic> task) async {
    if (_startingAudit) return;
    final status = task['status']?.toString().toUpperCase();
    if (status == 'COMPLETED' || status == 'CANCELLED') return;
    try {
      setState(() => _startingAudit = true);
      if (!await _ensureTaskCheckIn(task)) return;
      if (status == 'SCHEDULED')
        await _updateTaskStatus(task['id'].toString(), 'IN_PROGRESS');
      final visitId = await _createVisitForAudit(task);
      if (visitId.isEmpty || !mounted) return;
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AuditScreen(
            visitId: visitId,
            accessToken: widget.accessToken,
            title: _getCategory(task).isNotEmpty ? _getCategory(task) : 'MSF',
            clientName: _getClient(task),
            clientMobile: _getClientMobile(task),
            supervisorName: widget.user?['name']?.toString() ?? 'SUPERVISOR',
            siteName: task['site']?['name']?.toString(),
            siteCode: task['site']?['siteCode']?.toString(),
          ),
        ),
      );
      if (result == true) {
        await _updateTaskStatus(task['id'].toString(), 'COMPLETED');
        await _loadTasks();
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CheckInCheckOutScreen(
              accessToken: widget.accessToken,
              user: widget.user ?? {},
              taskSiteId:
                  task['site']?['id']?.toString() ?? task['siteId']?.toString(),
              taskSiteName: task['site']?['name']?.toString(),
              taskSiteCode: task['site']?['siteCode']?.toString(),
              taskSiteLatitude: (task['site']?['latitude'] as num?)?.toDouble(),
              taskSiteLongitude: (task['site']?['longitude'] as num?)
                  ?.toDouble(),
              returnAfterCheckIn: false,
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = error.toString().replaceFirst('Exception: ', ''),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _startingAudit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        title: const Text(
          'My Tasks',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(onPressed: _loadTasks, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
          ? const Center(child: Text('No pending tasks.'))
          : RefreshIndicator(
              onRefresh: _loadTasks,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _tasks.length,
                itemBuilder: (context, index) {
                  final task = _tasks[index];
                  final site = task['site'];
                  final siteName = site is Map
                      ? site['name']?.toString() ?? '—'
                      : '—';
                  final siteCode = site is Map
                      ? site['siteCode']?.toString() ?? ''
                      : '';
                  final status =
                      task['status']?.toString().toUpperCase() ?? 'SCHEDULED';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task['title']?.toString() ?? 'Task',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          siteCode.isNotEmpty
                              ? '$siteCode - $siteName'
                              : siteName,
                          style: const TextStyle(color: Color(0xFF6B7280)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              status,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: _startingAudit
                                  ? null
                                  : () => _startAudit(task),
                              icon: const Icon(
                                Icons.assignment_turned_in_outlined,
                                size: 18,
                              ),
                              label: Text(
                                status == 'IN_PROGRESS'
                                    ? 'Resume Audit'
                                    : 'Start Audit',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
