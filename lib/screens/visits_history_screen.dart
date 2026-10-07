import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';

class VisitsHistoryScreen extends StatefulWidget {
  final String accessToken;
  final Map<String, dynamic> user;

  const VisitsHistoryScreen({
    super.key,
    required this.accessToken,
    required this.user,
  });

  @override
  State<VisitsHistoryScreen> createState() => _VisitsHistoryScreenState();
}

class _VisitsHistoryScreenState extends State<VisitsHistoryScreen> {
  bool _loading = true;
  String _error = '';

  List<Map<String, dynamic>> _visits = [];

  @override
  void initState() {
    super.initState();
    _loadVisits();
  }

  Future<void> _loadVisits() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }

    try {
      final userId = widget.user['id']?.toString() ?? '';
      final email = widget.user['email']?.toString() ?? '';
      final name = widget.user['name']?.toString() ?? '';

      String searchValue = email.isNotEmpty ? email : name;

      final uri = Uri.parse(
        '${ApiService.baseUrl}/visits?page=1&limit=100'
        '${searchValue.trim().isNotEmpty ? '&search=${Uri.encodeQueryComponent(searchValue.trim())}' : ''}',
      );

      final response = await http.get(
        uri,
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
        throw Exception(data['message'] ?? 'Failed to load visits.');
      }

      final rawVisits = data['data']?['visits'] ?? data['visits'] ?? [];

      final List<Map<String, dynamic>> loadedVisits = [];

      if (rawVisits is List) {
        for (final item in rawVisits) {
          if (item is! Map) continue;

          final visit = Map<String, dynamic>.from(item);

          // Extra protection: only show this Supervisor's visits.
          final visitUser = visit['user'];

          if (userId.isNotEmpty &&
              visitUser is Map &&
              visitUser['id'] != null &&
              visitUser['id'].toString() != userId) {
            continue;
          }

          loadedVisits.add(visit);
        }
      }

      loadedVisits.sort((a, b) {
        final aDate = DateTime.tryParse(a['visitAt']?.toString() ?? '');

        final bDate = DateTime.tryParse(b['visitAt']?.toString() ?? '');

        return (bDate ?? DateTime(1970)).compareTo(aDate ?? DateTime(1970));
      });

      if (!mounted) return;

      setState(() {
        _visits = loadedVisits;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}

    return {};
  }

  int get _todayCount {
    final now = DateTime.now();

    return _visits.where((visit) {
      final value = visit['visitAt']?.toString() ?? '';
      final date = DateTime.tryParse(value);

      if (date == null) return false;

      final local = date.toLocal();

      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }).length;
  }

  String _formatDateTime(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');

    if (date == null) return 'NA';

    final local = date.toLocal();

    final dateText =
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';

    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;

    final period = local.hour >= 12 ? 'PM' : 'AM';

    final timeText =
        '${hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')} $period';

    return '$dateText • $timeText';
  }

  String _statusText(dynamic value) {
    final status = value?.toString().toUpperCase() ?? '';

    switch (status) {
      case 'VERIFIED':
        return 'Verified';
      case 'REJECTED':
        return 'Rejected';
      case 'UNVERIFIED':
        return 'Unverified';
      case 'PENDING':
        return 'Pending';
      default:
        return status.isEmpty ? 'Pending' : status;
    }
  }

  Color _statusColor(dynamic value) {
    final status = value?.toString().toUpperCase() ?? '';

    switch (status) {
      case 'VERIFIED':
        return const Color(0xFF16A34A);
      case 'REJECTED':
        return const Color(0xFFDC2626);
      case 'UNVERIFIED':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF2563EB);
    }
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitCard(Map<String, dynamic> visit) {
    final site = visit['site'] is Map
        ? Map<String, dynamic>.from(visit['site'])
        : <String, dynamic>{};

    final siteName = site['name']?.toString().trim() ?? '';

    final siteCode = site['siteCode']?.toString().trim() ?? '';

    final client = visit['clientName']?.toString().trim() ?? '';

    final reportType = visit['reportType']?.toString().trim() ?? '';

    final status = visit['status']?.toString() ?? 'PENDING';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      siteName.isNotEmpty ? siteName : 'Site Visit',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    if (siteCode.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          siteCode,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusText(status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          if (client.isNotEmpty)
            _infoRow(Icons.business_outlined, 'Client', client),

          if (reportType.isNotEmpty)
            _infoRow(Icons.description_outlined, 'Type', reportType),

          _infoRow(
            Icons.schedule_outlined,
            'Visited',
            _formatDateTime(visit['visitAt']),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF111827),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'No visits found',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            const Text(
              'Your completed site visits will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'My Visits',
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadVisits,
            icon: const Icon(Icons.refresh, color: Color(0xFF374151)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 56,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadVisits,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadVisits,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      _statCard(
                        title: 'Total Visits',
                        value: '${_visits.length}',
                        icon: Icons.location_on_outlined,
                        iconColor: const Color(0xFF2563EB),
                        iconBackground: const Color(0xFFEAF1FF),
                      ),
                      const SizedBox(width: 12),
                      _statCard(
                        title: 'Today',
                        value: '$_todayCount',
                        icon: Icons.today_outlined,
                        iconColor: const Color(0xFF16A34A),
                        iconBackground: const Color(0xFFEAF8EE),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Visit History',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_visits.isEmpty)
                    SizedBox(height: 360, child: _emptyState())
                  else
                    ..._visits.map(_buildVisitCard),
                ],
              ),
            ),
    );
  }
}
