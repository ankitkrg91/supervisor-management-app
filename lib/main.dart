import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

import 'services/api_service.dart';

import 'screens/change_password_screen.dart';

import 'screens/my_tasks_screen.dart';

import 'services/location_tracking_service.dart';

import 'screens/visits_history_screen.dart';

import 'screens/audit_history_screen.dart';

void main() {
  runApp(const SupervisorApp());
}

class SupervisorApp extends StatelessWidget {
  const SupervisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'Supervisor App',

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),

        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      ),

      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();

  final _passwordController = TextEditingController();

  bool _loading = false;

  bool _hidePassword = true;

  Future<void> _startLocationTracking(String token) async {
    try {
      await LocationTrackingService.start(accessToken: token);
    } catch (error) {
      debugPrint('Location tracking start failed: $error');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();

    _passwordController.dispose();

    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });

    try {
      final response = await ApiService.supervisorLogin(
        email: _emailController.text.trim(),

        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      final data = response['data'] is Map
          ? Map<String, dynamic>.from(response['data'])
          : <String, dynamic>{};

      final user = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'])
          : <String, dynamic>{};

      final token =
          data['accessToken']?.toString() ?? data['token']?.toString() ?? '';

      if (token.isEmpty) {
        throw Exception('Login successful but access token was not returned.');
      }

      Navigator.pushReplacement(
        context,

        MaterialPageRoute(
          builder: (_) => SupervisorDashboard(user: user, accessToken: token),
        ),
      );

      unawaited(_startLocationTracking(token));
    } catch (error) {
      if (!mounted) {
        return;
      }

      var message = error.toString();

      if (message.startsWith('Exception:')) {
        message = message.substring(10).trim();
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),

            backgroundColor: Colors.red,

            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),

            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),

              child: Form(
                key: _formKey,

                child: Column(
                  children: [
                    Container(
                      width: 78,

                      height: 78,

                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),

                        borderRadius: BorderRadius.circular(22),
                      ),

                      child: const Icon(
                        Icons.shield_outlined,

                        color: Colors.white,

                        size: 42,
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Supervisor App',

                      style: TextStyle(
                        fontSize: 28,

                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Sign in to continue',

                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),

                    const SizedBox(height: 30),

                    Container(
                      padding: const EdgeInsets.all(20),

                      decoration: BoxDecoration(
                        color: Colors.white,

                        borderRadius: BorderRadius.circular(20),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),

                            blurRadius: 20,

                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),

                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailController,

                            keyboardType: TextInputType.emailAddress,

                            decoration: InputDecoration(
                              labelText: 'Email',

                              prefixIcon: const Icon(Icons.email_outlined),

                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),

                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter email';
                              }

                              if (!value.contains('@')) {
                                return 'Enter a valid email';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 18),

                          TextFormField(
                            controller: _passwordController,

                            obscureText: _hidePassword,

                            onFieldSubmitted: (_) => _login(),

                            decoration: InputDecoration(
                              labelText: 'Password',

                              prefixIcon: const Icon(Icons.lock_outline),

                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _hidePassword = !_hidePassword;
                                  });
                                },

                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),

                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),

                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter password';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 22),

                          SizedBox(
                            width: double.infinity,

                            height: 52,

                            child: ElevatedButton(
                              onPressed: _loading ? null : _login,

                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),

                                foregroundColor: Colors.white,

                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),

                              child: _loading
                                  ? const SizedBox(
                                      width: 22,

                                      height: 22,

                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,

                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Login',

                                      style: TextStyle(
                                        fontSize: 16,

                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SupervisorDashboard extends StatefulWidget {
  final Map<String, dynamic> user;

  final String accessToken;

  const SupervisorDashboard({
    super.key,

    required this.user,

    required this.accessToken,
  });

  @override
  State<SupervisorDashboard> createState() => _SupervisorDashboardState();
}

class _SupervisorDashboardState extends State<SupervisorDashboard> {
  bool _loading = true;

  bool _refreshing = false;

  String _error = '';

  List<Map<String, dynamic>> _tasks = [];

  @override
  void initState() {
    super.initState();

    _loadTasks();
  }

  Future<void> _loadTasks({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _refreshing = true;

        _error = '';
      });
    } else {
      setState(() {
        _loading = true;

        _error = '';
      });
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/tasks?page=1&limit=100'),

        headers: {
          'Content-Type': 'application/json',

          'Authorization': 'Bearer ${widget.accessToken}',
        },
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          decoded is Map
              ? decoded['message'] ?? 'Failed to load tasks'
              : 'Failed to load tasks',
        );
      }

      final rawTasks = decoded is Map && decoded['data'] is Map
          ? decoded['data']['tasks']
          : null;

      final List<Map<String, dynamic>> loaded = [];

      if (rawTasks is List) {
        for (final item in rawTasks) {
          if (item is Map) {
            final task = Map<String, dynamic>.from(item);

            final assignedTo = task['assignedTo'];

            if (assignedTo is Map) {
              final role = assignedTo['role']?.toString().toUpperCase();

              if (role != null && role != 'SUPERVISOR') {
                continue;
              }
            }

            loaded.add(task);
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = loaded;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      var message = error.toString();

      if (message.startsWith('Exception:')) {
        message = message.substring(10).trim();
      }

      setState(() {
        _error = message;

        _tasks = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;

          _refreshing = false;
        });
      }
    }
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return {};
  }

  String _userName() {
    final name = widget.user['name']?.toString();

    if (name != null && name.trim().isNotEmpty) {
      return name;
    }

    return 'Supervisor';
  }

  String _greeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'Good morning';
    }

    if (hour < 17) {
      return 'Good afternoon';
    }

    return 'Good evening';
  }

  String _siteName() {
    final site = _map(widget.user['site']);

    final name = site['name']?.toString();

    if (name != null && name.trim().isNotEmpty) {
      return name;
    }

    if (_tasks.isNotEmpty) {
      final taskSite = _map(_tasks.first['site']);

      final taskSiteName = taskSite['name']?.toString();

      if (taskSiteName != null && taskSiteName.trim().isNotEmpty) {
        return taskSiteName;
      }
    }

    return 'Site not assigned';
  }

  // ignore: unused_element
  String _siteCode() {
    final site = _map(widget.user['site']);

    final code = site['siteCode']?.toString();

    if (code != null && code.trim().isNotEmpty) {
      return code;
    }

    if (_tasks.isNotEmpty) {
      final taskSite = _map(_tasks.first['site']);

      return taskSite['siteCode']?.toString() ?? '';
    }

    return '';
  }

  DateTime? _scheduledAt(Map<String, dynamic> task) {
    final value = task['scheduledAt']?.toString();

    if (value == null || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  bool _isMissed(Map<String, dynamic> task) {
    final status = task['status']?.toString();

    if (status != 'SCHEDULED') {
      return false;
    }

    final scheduled = _scheduledAt(task);

    if (scheduled == null) {
      return false;
    }

    return scheduled.isBefore(DateTime.now());
  }

  bool _isToday(Map<String, dynamic> task) {
    final date = _scheduledAt(task);

    if (date == null) {
      return false;
    }

    final now = DateTime.now();

    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  int _countStatus(String status) {
    return _tasks.where((task) {
      return task['status']?.toString() == status;
    }).length;
  }

  int get _missedCount {
    return _tasks.where(_isMissed).length;
  }

  int get _pendingCount {
    return _tasks.where((task) {
      return task['status']?.toString() == 'SCHEDULED' && !_isMissed(task);
    }).length;
  }

  List<Map<String, dynamic>> get _todayTasks {
    final list = _tasks.where((task) {
      final status = task['status']?.toString().toUpperCase() ?? '';
      final isPending = status != 'COMPLETED' && status != 'CANCELLED';
      return _isToday(task) && isPending;
    }).toList();

    list.sort((a, b) {
      final aDate = _scheduledAt(a);
      final bDate = _scheduledAt(b);

      if (aDate == null && bDate == null) {
        return 0;
      }
      if (aDate == null) {
        return 1;
      }
      if (bDate == null) {
        return -1;
      }
      return aDate.compareTo(bDate);
    });

    return list;
  }

  String _formatDateTime(Map<String, dynamic> task) {
    final date = _scheduledAt(task);

    if (date == null) {
      return 'No schedule';
    }

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}  $hour:$minute';
  }

  String _formatTime(Map<String, dynamic> task) {
    final date = _scheduledAt(task);

    if (date == null) {
      return '--:--';
    }

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  Color _priorityColor(String? priority) {
    switch (priority) {
      case 'HIGH':
        return Colors.red;

      case 'MEDIUM':
        return Colors.orange;

      case 'LOW':
        return Colors.green;

      default:
        return Colors.grey;
    }
  }

  Color _statusColor(Map<String, dynamic> task) {
    if (_isMissed(task)) {
      return const Color(0xFFDC2626);
    }

    switch (task['status']?.toString()) {
      case 'COMPLETED':
        return const Color(0xFF16A34A);

      case 'IN_PROGRESS':
        return const Color(0xFF2563EB);

      case 'CANCELLED':
        return const Color(0xFF6B7280);

      case 'SCHEDULED':
        return const Color(0xFFF59E0B);

      default:
        return const Color(0xFF6B7280);
    }
  }

  String _displayStatus(Map<String, dynamic> task) {
    if (_isMissed(task)) {
      return 'MISSED';
    }

    switch (task['status']?.toString()) {
      case 'COMPLETED':
        return 'COMPLETED';

      case 'IN_PROGRESS':
        return 'IN PROGRESS';

      case 'CANCELLED':
        return 'CANCELLED';

      case 'SCHEDULED':
        return 'PENDING';

      default:
        return 'UNKNOWN';
    }
  }

  Future<void> _logout() async {
    await LocationTrackingService.stop();

    if (!mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,

      MaterialPageRoute(builder: (_) => const LoginScreen()),

      (_) => false,
    );
  }

  void _showNotifications() {
    final missedTasks = _tasks.where(_isMissed).toList();

    missedTasks.sort((a, b) {
      final aDate = _scheduledAt(a);

      final bDate = _scheduledAt(b);

      if (aDate == null && bDate == null) {
        return 0;
      }

      if (aDate == null) {
        return 1;
      }

      if (bDate == null) {
        return -1;
      }

      return aDate.compareTo(bDate);
    });

    showModalBottomSheet(
      context: context,

      isScrollControlled: true,

      backgroundColor: Colors.white,

      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),

      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),

            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Center(
                  child: Container(
                    width: 42,

                    height: 4,

                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),

                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Notifications',

                        style: TextStyle(
                          fontSize: 20,

                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                    if (missedTasks.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,

                          vertical: 5,
                        ),

                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),

                          borderRadius: BorderRadius.circular(20),
                        ),

                        child: Text(
                          '${missedTasks.length} missed',

                          style: const TextStyle(
                            color: Color(0xFFDC2626),

                            fontSize: 12,

                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                if (missedTasks.isEmpty)
                  Container(
                    width: double.infinity,

                    padding: const EdgeInsets.symmetric(
                      vertical: 35,

                      horizontal: 20,
                    ),

                    child: const Column(
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,

                          size: 48,

                          color: Color(0xFF9CA3AF),
                        ),

                        SizedBox(height: 12),

                        Text(
                          'No new notifications',

                          style: TextStyle(
                            fontSize: 15,

                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        SizedBox(height: 4),

                        Text(
                          'You are all caught up.',

                          style: TextStyle(
                            color: Color(0xFF6B7280),

                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,

                      itemCount: missedTasks.length,

                      separatorBuilder: (_, _) => const SizedBox(height: 10),

                      itemBuilder: (context, index) {
                        final task = missedTasks[index];

                        final title =
                            task['title']?.toString() ?? 'Untitled Task';

                        return Container(
                          padding: const EdgeInsets.all(14),

                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),

                            borderRadius: BorderRadius.circular(14),

                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),

                          child: Row(
                            children: [
                              Container(
                                width: 42,

                                height: 42,

                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),

                                  borderRadius: BorderRadius.circular(11),
                                ),

                                child: const Icon(
                                  Icons.schedule_rounded,

                                  color: Color(0xFFDC2626),

                                  size: 21,
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,

                                  children: [
                                    Text(
                                      title,

                                      maxLines: 1,

                                      overflow: TextOverflow.ellipsis,

                                      style: const TextStyle(
                                        fontSize: 14,

                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      'Scheduled ${_formatDateTime(task)}',

                                      style: const TextStyle(
                                        color: Color(0xFF6B7280),

                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
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
    );
  }

  Widget _taskCard(Map<String, dynamic> task) {
    final title = task['title']?.toString() ?? 'Untitled Task';

    final description = task['description']?.toString() ?? '';

    final priority = task['priority']?.toString();

    final status = _displayStatus(task);

    final statusColor = _statusColor(task);

    final priorityColor = _priorityColor(priority);

    final site = _map(task['site']);

    final siteName = site['name']?.toString() ?? _siteName();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Expanded(
                child: Text(
                  title,

                  maxLines: 2,

                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    fontSize: 15,

                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),

                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),

                  borderRadius: BorderRadius.circular(8),
                ),

                child: Text(
                  status,

                  style: TextStyle(
                    color: statusColor,

                    fontSize: 9,

                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          if (description.trim().isNotEmpty) ...[
            const SizedBox(height: 7),

            Text(
              description,

              maxLines: 2,

              overflow: TextOverflow.ellipsis,

              style: const TextStyle(
                color: Color(0xFF6B7280),

                fontSize: 12,

                height: 1.35,
              ),
            ),
          ],

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,

                size: 16,

                color: Color(0xFF6B7280),
              ),

              const SizedBox(width: 5),

              Expanded(
                child: Text(
                  siteName,

                  maxLines: 1,

                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    color: Color(0xFF6B7280),

                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(
                Icons.schedule_outlined,

                size: 16,

                color: Color(0xFF6B7280),
              ),

              const SizedBox(width: 5),

              Expanded(
                child: Text(
                  _formatTime(task),

                  style: const TextStyle(
                    color: Color(0xFF6B7280),

                    fontSize: 12,
                  ),
                ),
              ),

              if (priority != null && priority.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,

                    vertical: 4,
                  ),

                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: 0.10),

                    borderRadius: BorderRadius.circular(6),
                  ),

                  child: Text(
                    priority,

                    style: TextStyle(
                      color: priorityColor,

                      fontSize: 9,

                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String title,

    required int value,

    required IconData icon,

    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Row(
        children: [
          Container(
            width: 42,

            height: 42,

            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),

              borderRadius: BorderRadius.circular(11),
            ),

            child: Icon(icon, color: color, size: 21),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  maxLines: 1,

                  overflow: TextOverflow.ellipsis,

                  style: const TextStyle(
                    fontSize: 11,

                    color: Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  value.toString(),

                  style: const TextStyle(
                    fontSize: 22,

                    fontWeight: FontWeight.w800,

                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,

    required String title,

    required String subtitle,

    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,

        borderRadius: BorderRadius.circular(16),

        child: Container(
          padding: const EdgeInsets.all(14),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(16),

            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Container(
                width: 40,

                height: 40,

                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.10),

                  borderRadius: BorderRadius.circular(11),
                ),

                child: const Icon(
                  Icons.arrow_forward,

                  color: Color(0xFF2563EB),

                  size: 20,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                title,

                style: const TextStyle(
                  fontSize: 13,

                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                subtitle,

                maxLines: 1,

                overflow: TextOverflow.ellipsis,

                style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,

            size: 40,

            color: Color(0xFF9CA3AF),
          ),

          const SizedBox(height: 10),

          const Text(
            'Unable to load tasks',

            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),

          const SizedBox(height: 5),

          Text(
            _error,

            textAlign: TextAlign.center,

            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),

          const SizedBox(height: 14),

          OutlinedButton(
            onPressed: _refreshing ? null : () => _loadTasks(refresh: true),

            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _emptyTodayView() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),

      child: const Column(
        children: [
          Icon(
            Icons.event_available_outlined,

            size: 40,

            color: Color(0xFF9CA3AF),
          ),

          SizedBox(height: 10),

          Text(
            'No tasks for today',

            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),

          SizedBox(height: 4),

          Text(
            'You are all caught up for today.',

            textAlign: TextAlign.center,

            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _tasks.length;

    final pending = _pendingCount;

    final inProgress = _countStatus('IN_PROGRESS');

    final completed = _countStatus('COMPLETED');

    final missed = _missedCount;

    final todayTasks = _todayTasks;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        elevation: 0,

        titleSpacing: 18,

        title: const Text(
          'Dashboard',

          style: TextStyle(
            color: Color(0xFF111827),

            fontSize: 20,

            fontWeight: FontWeight.w800,
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Refresh',

            onPressed: _refreshing
                ? null
                : () {
                    _loadTasks(refresh: true);
                  },

            icon: _refreshing
                ? const SizedBox(
                    width: 19,

                    height: 19,

                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, color: Color(0xFF374151)),
          ),

          Stack(
            alignment: Alignment.center,

            children: [
              IconButton(
                tooltip: 'Notifications',

                onPressed: _showNotifications,

                icon: const Icon(
                  Icons.notifications_none_rounded,

                  color: Color(0xFF374151),
                ),
              ),

              if (missed > 0)
                Positioned(
                  right: 8,

                  top: 8,

                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 17,

                      minHeight: 17,
                    ),

                    padding: const EdgeInsets.symmetric(horizontal: 4),

                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),

                      shape: BoxShape.circle,

                      border: Border.all(color: Colors.white, width: 2),
                    ),

                    child: Text(
                      missed > 9 ? '9+' : '$missed',

                      textAlign: TextAlign.center,

                      style: const TextStyle(
                        color: Colors.white,

                        fontSize: 8,

                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'change_password') {
                Navigator.push(
                  context,

                  MaterialPageRoute(
                    builder: (_) =>
                        ChangePasswordScreen(accessToken: widget.accessToken),
                  ),
                );
              } else if (value == 'logout') {
                _logout();
              }
            },

            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'change_password',

                child: Row(
                  children: [
                    Icon(Icons.lock_reset, size: 19),

                    SizedBox(width: 8),

                    Text('Change Password'),
                  ],
                ),
              ),

              const PopupMenuItem<String>(
                value: 'logout',

                child: Row(
                  children: [
                    Icon(Icons.logout, size: 19),

                    SizedBox(width: 8),

                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadTasks(refresh: true),

              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),

                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(20),

                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,

                          end: Alignment.bottomRight,

                          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        ),

                        borderRadius: BorderRadius.circular(20),

                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2563EB)
                                .withValues(alpha: 0.20),

                            blurRadius: 18,

                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            _greeting(),

                            style: const TextStyle(
                              color: Colors.white70,

                              fontSize: 13,

                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          const SizedBox(height: 5),

                          Text(
                            _userName(),

                            maxLines: 1,

                            overflow: TextOverflow.ellipsis,

                            style: const TextStyle(
                              color: Colors.white,

                              fontSize: 24,

                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          const SizedBox(height: 2),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Task Overview',

                      style: TextStyle(
                        fontSize: 18,

                        fontWeight: FontWeight.w800,

                        color: Color(0xFF111827),
                      ),
                    ),

                    const SizedBox(height: 12),

                    GridView.count(
                      crossAxisCount: 2,

                      shrinkWrap: true,

                      physics: const NeverScrollableScrollPhysics(),

                      mainAxisSpacing: 10,

                      crossAxisSpacing: 10,

                      childAspectRatio: 1.55,

                      children: [
                        _statCard(
                          title: 'Total Tasks',

                          value: total,

                          icon: Icons.assignment_outlined,

                          color: const Color(0xFF2563EB),
                        ),

                        _statCard(
                          title: 'Pending',

                          value: pending,

                          icon: Icons.schedule_outlined,

                          color: const Color(0xFFF59E0B),
                        ),

                        _statCard(
                          title: 'In Progress',

                          value: inProgress,

                          icon: Icons.play_circle_outline,

                          color: const Color(0xFF3B82F6),
                        ),

                        _statCard(
                          title: 'Completed',

                          value: completed,

                          icon: Icons.check_circle_outline,

                          color: const Color(0xFF16A34A),
                        ),
                      ],
                    ),

                    if (missed > 0) ...[
                      const SizedBox(height: 12),

                      InkWell(
                        onTap: _showNotifications,

                        borderRadius: BorderRadius.circular(12),

                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,

                            vertical: 10,
                          ),

                          decoration: BoxDecoration(
                            color: Colors.white,

                            borderRadius: BorderRadius.circular(12),

                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),

                          child: Row(
                            children: [
                              const Icon(
                                Icons.notifications_active_outlined,

                                size: 18,

                                color: Color(0xFFDC2626),
                              ),

                              const SizedBox(width: 8),

                              Expanded(
                                child: Text(
                                  '$missed missed task${missed == 1 ? '' : 's'}',

                                  style: const TextStyle(
                                    fontSize: 12,

                                    fontWeight: FontWeight.w600,

                                    color: Color(0xFF374151),
                                  ),
                                ),
                              ),

                              const Icon(
                                Icons.chevron_right_rounded,

                                size: 20,

                                color: Color(0xFF9CA3AF),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 26),

                    const Text(
                      'Today’s Tasks',

                      style: TextStyle(
                        fontSize: 18,

                        fontWeight: FontWeight.w800,

                        color: Color(0xFF111827),
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (_error.isNotEmpty)
                      _errorView()
                    else if (todayTasks.isEmpty)
                      _emptyTodayView()
                    else
                      ...todayTasks.map(_taskCard),

                    const SizedBox(height: 26),

                    const Text(
                      'Quick Actions',

                      style: TextStyle(
                        fontSize: 18,

                        fontWeight: FontWeight.w800,

                        color: Color(0xFF111827),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        _quickAction(
                          icon: Icons.assignment_outlined,

                          title: 'My Tasks',

                          subtitle: 'View assigned tasks',

                          onTap: () {
                            Navigator.push(
                              context,

                              MaterialPageRoute(
                                builder: (_) => MyTasksScreen(
                                  accessToken: widget.accessToken,

                                  user: widget.user,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Row(
                      children: [
                        _quickAction(
                          icon: Icons.location_on_outlined,

                          title: 'Visits',

                          subtitle: 'View site visits',

                          onTap: () {
                            Navigator.push(
                              context,

                              MaterialPageRoute(
                                builder: (_) => VisitsHistoryScreen(
                                  accessToken: widget.accessToken,

                                  user: widget.user,
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(width: 10),

                        _quickAction(
                          icon: Icons.fact_check_outlined,

                          title: 'Audits',

                          subtitle: 'Manage audits',

                          onTap: () {
                            Navigator.push(
                              context,

                              MaterialPageRoute(
                                builder: (_) => AuditHistoryScreen(
                                  accessToken: widget.accessToken,

                                  user: widget.user,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,

                        vertical: 12,
                      ),

                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),

                        borderRadius: BorderRadius.circular(12),
                      ),

                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,

                            size: 16,

                            color: Color(0xFF9CA3AF),
                          ),

                          const SizedBox(width: 7),

                          Expanded(
                            child: Text(
                              missed > 0
                                  ? 'You have $missed missed task${missed == 1 ? '' : 's'}. Tap the notification bell to view details.'
                                  : 'Your task information is up to date.',

                              style: const TextStyle(
                                color: Color(0xFF6B7280),

                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
