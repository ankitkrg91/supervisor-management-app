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

  /* ==========================================================
     LOAD TASKS
     ========================================================== */

  Future<void> _loadTasks() async {
    try {
      setState(() {
        _loading = true;
        _errorMessage = '';
      });

      final List<Map<String, dynamic>> allTasks = [];

      int page = 1;
      int totalPages = 1;

      do {
        final response = await http.get(
          Uri.parse(
            '${ApiService.baseUrl}/tasks'
            '?page=$page&limit=100',
          ),
          headers: {
            'Authorization': 'Bearer ${widget.accessToken}',
            'Content-Type': 'application/json',
          },
        );

        final data = _decodeResponse(response);

        if (response.statusCode == 401) {
          throw Exception(
            data['message'] ?? 'Session expired. Please login again.',
          );
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(data['message'] ?? 'Failed to load tasks.');
        }

        final rawTasks = data['data']?['tasks'] ?? data['tasks'] ?? [];

        if (rawTasks is List) {
          for (final item in rawTasks) {
            if (item is Map) {
              final task = Map<String, dynamic>.from(item);

              final role = task['assignedTo']?['role']
                  ?.toString()
                  .toUpperCase();

              /*
               * Only show tasks assigned to Supervisors
               * and only tasks that are still pending/incomplete.
               *
               * SCHEDULED   -> SHOW
               * IN_PROGRESS -> SHOW
               * COMPLETED   -> HIDE
               * CANCELLED   -> HIDE
               */
              final status =
                  task['status']?.toString().toUpperCase() ?? 'SCHEDULED';

              final isPendingTask =
                  status == 'SCHEDULED' || status == 'IN_PROGRESS';

              if ((role == null || role.isEmpty || role == 'SUPERVISOR') &&
                  isPendingTask) {
                allTasks.add(task);
              }
            }
          }
        }

        final pagination =
            data['data']?['pagination'] ?? data['pagination'] ?? {};

        totalPages = int.tryParse('${pagination['totalPages'] ?? 1}') ?? 1;

        page++;
      } while (page <= totalPages);

      /*
       * Sort pending tasks by scheduled date.
       */
      allTasks.sort((a, b) {
        final aDate =
            DateTime.tryParse('${a['scheduledAt'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0);

        final bDate =
            DateTime.tryParse('${b['scheduledAt'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return aDate.compareTo(bDate);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = allTasks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /* ==========================================================
     DECODE
     ========================================================== */

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final value = jsonDecode(response.body);

      if (value is Map<String, dynamic>) {
        return value;
      }

      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }

      return {};
    } catch (_) {
      return {};
    }
  }

  /* ==========================================================
     DESCRIPTION HELPERS
     ========================================================== */

  String _extractValue(String? description, String key) {
    if (description == null || description.trim().isEmpty) {
      return '';
    }

    for (final line in description.split('\n')) {
      final trimmed = line.trim();

      if (trimmed.toLowerCase().startsWith('$key:'.toLowerCase())) {
        return trimmed.substring(key.length + 1).trim();
      }
    }

    return '';
  }

  String _getCategory(Map<String, dynamic> task) {
    return _extractValue(task['description']?.toString(), 'Category');
  }

  String _getType(Map<String, dynamic> task) {
    return _extractValue(task['description']?.toString(), 'Type');
  }

  String _getClient(Map<String, dynamic> task) {
    final descriptionClient = _extractValue(
      task['description']?.toString(),
      'Client',
    );

    if (descriptionClient.isNotEmpty) {
      return descriptionClient;
    }

    return task['clientName']?.toString() ?? '';
  }

  /* ==========================================================
     CREATE / UPDATE VISIT
     ========================================================== */

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

    if (siteId.isEmpty) {
      throw Exception('Task site is missing.');
    }

    if (taskId.isEmpty) {
      throw Exception('Task ID is missing.');
    }

    /* ========================================================
       1. OPEN PHOTO + GPS SCREEN
       ======================================================== */

    if (!mounted) {
      return '';
    }

    final captureResult = await Navigator.of(context)
        .push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (_) =>
                VisitCaptureScreen(siteName: siteName, siteCode: siteCode),
          ),
        );

    if (captureResult == null) {
      return '';
    }

    /* ========================================================
       2. GET PHOTO DATA
       ======================================================== */

    final photoUrl = captureResult['photoUrl']?.toString().trim() ?? '';

    final photoFileId = captureResult['photoFileId']?.toString().trim() ?? '';

    final latitude = (captureResult['latitude'] as num?)?.toDouble();

    final longitude = (captureResult['longitude'] as num?)?.toDouble();

    if (photoUrl.isEmpty) {
      throw Exception('Photo URL was not returned.');
    }

    if (latitude == null || longitude == null) {
      throw Exception('GPS coordinates were not returned.');
    }

    /* ========================================================
       3. CREATE / UPDATE VISIT IN POSTGRESQL
       ======================================================== */

    final notes = [
      'Task ID: $taskId',
      'Task: $title',
      if (_getCategory(task).isNotEmpty) 'Category: ${_getCategory(task)}',
      if (siteCode.isNotEmpty) 'Site Code: $siteCode',
      if (siteName.isNotEmpty) 'Site: $siteName',
    ].join('\n');

    final response = await ApiService.createVisit(
      accessToken: widget.accessToken,
      siteId: siteId,
      visitAt: DateTime.now().toUtc().toIso8601String(),
      reportType: _getType(task).isNotEmpty ? _getType(task) : 'Audit',
      clientName: _getClient(task).isNotEmpty ? _getClient(task) : null,
      branch: null,
      region: null,
      latitude: latitude,
      longitude: longitude,
      photoUrl: photoUrl,
      photoFileId: photoFileId.isNotEmpty ? photoFileId : null,
      notes: notes,
    );

    final visit = response['data']?['visit'] ?? response['visit'];

    final visitId = visit?['id']?.toString() ?? '';

    if (visitId.isEmpty) {
      throw Exception('Visit ID was not returned by backend.');
    }

    return visitId;
  }

  /* ==========================================================
     CHECK-IN
     ========================================================== */

  Future<bool> _ensureTaskCheckIn(Map<String, dynamic> task) async {
    final site = task['site'];

    final siteMap = site is Map
        ? Map<String, dynamic>.from(site)
        : <String, dynamic>{};

    final siteId =
        siteMap['id']?.toString() ?? task['siteId']?.toString() ?? '';

    if (siteId.isEmpty) {
      throw Exception('Task site is missing.');
    }

    if (!mounted) {
      return false;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CheckInCheckOutScreen(
          accessToken: widget.accessToken,
          user: widget.user ?? {},
          taskSiteId: siteId,
          taskSiteName: siteMap['name']?.toString(),
          taskSiteCode: siteMap['siteCode']?.toString(),
          returnAfterCheckIn: true,
        ),
      ),
    );

    return result == true;
  }

  /* ==========================================================
     TASK STATUS
     ========================================================== */

  Future<void> _updateTaskStatus(String taskId, String status) async {
    final response = await http.patch(
      Uri.parse('${ApiService.baseUrl}/tasks/$taskId/status'),
      headers: {
        'Authorization': 'Bearer ${widget.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'status': status}),
    );

    final data = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['message'] ?? 'Failed to update task.');
    }
  }

  /* ==========================================================
     START AUDIT
     ========================================================== */

  Future<void> _startAudit(Map<String, dynamic> task) async {
    if (_startingAudit) {
      return;
    }

    final status = task['status']?.toString().toUpperCase();

    if (status == 'COMPLETED' || status == 'CANCELLED') {
      return;
    }

    try {
      setState(() {
        _startingAudit = true;
      });

      final checkedIn = await _ensureTaskCheckIn(task);

      if (!checkedIn) {
        return;
      }

      if (status == 'SCHEDULED') {
        await _updateTaskStatus(task['id'].toString(), 'IN_PROGRESS');
      }

      /* IMPORTANT:
         Photo/GPS BEFORE Visit creation */

      final visitId = await _createVisitForAudit(task);

      if (visitId.isEmpty) {
        return;
      }

      if (!mounted) {
        return;
      }

      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AuditScreen(
            visitId: visitId,
            accessToken: widget.accessToken,
            title: _getCategory(task).isNotEmpty ? _getCategory(task) : 'MSF',
            clientName: _getClient(task),
            siteName: task['site']?['name']?.toString(),
            siteCode: task['site']?['siteCode']?.toString(),
          ),
        ),
      );

      if (result == true) {
        await _updateTaskStatus(task['id'].toString(), 'COMPLETED');

        /*
         * Reload immediately.
         *
         * Because _loadTasks() now only keeps
         * SCHEDULED and IN_PROGRESS tasks,
         * this completed task will disappear
         * from My Tasks.
         */
        await _loadTasks();

        if (!mounted) {
          return;
        }

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CheckInCheckOutScreen(
              accessToken: widget.accessToken,
              user: widget.user ?? {},
              taskSiteId:
                  task['site']?['id']?.toString() ?? task['siteId']?.toString(),
              taskSiteName: task['site']?['name']?.toString(),
              taskSiteCode: task['site']?['siteCode']?.toString(),
              returnAfterCheckIn: false,
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _startingAudit = false;
        });
      }
    }
  }

  /* ==========================================================
     FORMAT
     ========================================================== */

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) {
      return '—';
    }

    final date = DateTime.tryParse(value);

    if (date == null) {
      return '—';
    }

    final d = date.toLocal();

    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  String _formatTime(String? value) {
    if (value == null || value.isEmpty) {
      return '—';
    }

    final date = DateTime.tryParse(value);

    if (date == null) {
      return '—';
    }

    final d = date.toLocal();

    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;

    return '$hour:'
        '${d.minute.toString().padLeft(2, '0')} '
        '${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  /* ==========================================================
     BUILD
     ========================================================== */

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
          : _errorMessage.isNotEmpty && _tasks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_errorMessage, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadTasks,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
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

                  final canStart =
                      status != 'COMPLETED' && status != 'CANCELLED';

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

                        const SizedBox(height: 8),

                        Text(
                          siteCode.isNotEmpty
                              ? '$siteCode - $siteName'
                              : siteName,

                          style: const TextStyle(color: Color(0xFF6B7280)),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          'Schedule: '
                          '${_formatDate(task['scheduledAt']?.toString())} '
                          '${_formatTime(task['scheduledAt']?.toString())}',

                          style: const TextStyle(color: Color(0xFF6B7280)),
                        ),

                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Text(
                              status,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const Spacer(),

                            if (canStart)
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
