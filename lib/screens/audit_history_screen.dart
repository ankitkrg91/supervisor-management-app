import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';

class AuditHistoryScreen extends StatefulWidget {
  final String accessToken;
  final Map<String, dynamic> user;

  const AuditHistoryScreen({
    super.key,
    required this.accessToken,
    required this.user,
  });

  @override
  State<AuditHistoryScreen> createState() => _AuditHistoryScreenState();
}

class _AuditHistoryScreenState extends State<AuditHistoryScreen> {
  bool _loading = true;
  String _error = '';

  List<Map<String, dynamic>> _audits = [];

  @override
  void initState() {
    super.initState();
    _loadAudits();
  }

  Future<void> _loadAudits() async {
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

      final searchValue = email.isNotEmpty ? email : name;

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
        throw Exception(data['message'] ?? 'Failed to load audits.');
      }

      final rawVisits = data['data']?['visits'] ?? data['visits'] ?? [];

      final List<Map<String, dynamic>> loadedAudits = [];

      if (rawVisits is List) {
        for (final item in rawVisits) {
          if (item is! Map) continue;

          final visit = Map<String, dynamic>.from(item);

          // Only this Supervisor.
          final visitUser = visit['user'];

          if (userId.isNotEmpty &&
              visitUser is Map &&
              visitUser['id'] != null &&
              visitUser['id'].toString() != userId) {
            continue;
          }

          // One submitted audit is represented
          // by a Visit having auditSubmission.
          final auditSubmission = visit['auditSubmission'];

          if (auditSubmission == null) {
            continue;
          }

          loadedAudits.add(visit);
        }
      }

      loadedAudits.sort((a, b) {
        final aDate = DateTime.tryParse(
          a['auditSubmission']?['submittedAt']?.toString() ??
              a['visitAt']?.toString() ??
              '',
        );

        final bDate = DateTime.tryParse(
          b['auditSubmission']?['submittedAt']?.toString() ??
              b['visitAt']?.toString() ??
              '',
        );

        return (bDate ?? DateTime(1970)).compareTo(aDate ?? DateTime(1970));
      });

      if (!mounted) return;

      setState(() {
        _audits = loadedAudits;
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

  int get _verifiedCount {
    return _audits.where((audit) {
      return audit['status']?.toString().toUpperCase() == 'VERIFIED';
    }).length;
  }

  int get _rejectedCount {
    return _audits.where((audit) {
      return audit['status']?.toString().toUpperCase() == 'REJECTED';
    }).length;
  }

  int get _pendingCount {
    return _audits.where((audit) {
      final status = audit['status']?.toString().toUpperCase();

      return status == 'PENDING' ||
          status == 'UNVERIFIED' ||
          status == null ||
          status.isEmpty;
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
    final status = value?.toString().toUpperCase() ?? 'PENDING';

    switch (status) {
      case 'VERIFIED':
        return 'Verified';
      case 'REJECTED':
        return 'Rejected';
      case 'UNVERIFIED':
        return 'Pending';
      default:
        return 'Pending';
    }
  }

  Color _statusColor(dynamic value) {
    final status = value?.toString().toUpperCase() ?? 'PENDING';

    switch (status) {
      case 'VERIFIED':
        return const Color(0xFF16A34A);
      case 'REJECTED':
        return const Color(0xFFDC2626);
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

  Widget _buildAuditCard(Map<String, dynamic> audit) {
    final site = audit['site'] is Map
        ? Map<String, dynamic>.from(audit['site'])
        : <String, dynamic>{};

    final submission = audit['auditSubmission'] is Map
        ? Map<String, dynamic>.from(audit['auditSubmission'])
        : <String, dynamic>{};

    final siteName = site['name']?.toString().trim() ?? '';

    final siteCode = site['siteCode']?.toString().trim() ?? '';

    final client = audit['clientName']?.toString().trim() ?? '';

    final status = audit['status']?.toString() ?? 'PENDING';

    final submittedAt =
        submission['submittedAt']?.toString().trim() ??
        audit['visitAt']?.toString() ??
        '';

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
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      siteName.isNotEmpty ? siteName : 'Audit',
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

          _infoRow(
            Icons.fact_check_outlined,
            'Audit Submitted',
            _formatDateTime(submittedAt),
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
              Icons.fact_check_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'No audits found',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            const Text(
              'Submitted audits will appear here.',
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
          'My Audits',
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadAudits,
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
                      onPressed: _loadAudits,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAudits,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      _statCard(
                        title: 'Total Audits',
                        value: '${_audits.length}',
                        icon: Icons.fact_check_outlined,
                        iconColor: const Color(0xFF2563EB),
                        iconBackground: const Color(0xFFEAF1FF),
                      ),
                      const SizedBox(width: 10),
                      _statCard(
                        title: 'Pending',
                        value: '$_pendingCount',
                        icon: Icons.pending_actions_outlined,
                        iconColor: const Color(0xFFD97706),
                        iconBackground: const Color(0xFFFFF7E6),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statCard(
                        title: 'Verified',
                        value: '$_verifiedCount',
                        icon: Icons.verified_outlined,
                        iconColor: const Color(0xFF16A34A),
                        iconBackground: const Color(0xFFEAF8EE),
                      ),
                      const SizedBox(width: 10),
                      _statCard(
                        title: 'Rejected',
                        value: '$_rejectedCount',
                        icon: Icons.cancel_outlined,
                        iconColor: const Color(0xFFDC2626),
                        iconBackground: const Color(0xFFFFEEEE),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Audit History',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_audits.isEmpty)
                    SizedBox(height: 360, child: _emptyState())
                  else
                    ..._audits.map(_buildAuditCard),
                ],
              ),
            ),
    );
  }
}
