import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';

class CheckInCheckOutScreen extends StatefulWidget {
  final String accessToken;
  final Map<String, dynamic> user;

  final String? taskSiteId;
  final String? taskSiteName;
  final String? taskSiteCode;

  final bool returnAfterCheckIn;

  const CheckInCheckOutScreen({
    super.key,
    required this.accessToken,
    required this.user,
    this.taskSiteId,
    this.taskSiteName,
    this.taskSiteCode,
    this.returnAfterCheckIn = false,
  });

  @override
  State<CheckInCheckOutScreen> createState() => _CheckInCheckOutScreenState();
}

class _CheckInCheckOutScreenState extends State<CheckInCheckOutScreen> {
  bool _attendanceLoading = true;
  bool _processing = false;

  Map<String, dynamic>? _activeCheckIn;

  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  // ============================================================
  // TASK SITE ID
  // ============================================================

  String _taskSiteId() {
    final directTaskSiteId = widget.taskSiteId?.trim();

    if (directTaskSiteId != null && directTaskSiteId.isNotEmpty) {
      return directTaskSiteId;
    }

    final userSiteId = widget.user['siteId']?.toString().trim();

    if (userSiteId != null && userSiteId.isNotEmpty) {
      return userSiteId;
    }

    final userSite = widget.user['site'];

    if (userSite is Map) {
      final id = userSite['id']?.toString().trim();

      if (id != null && id.isNotEmpty) {
        return id;
      }
    }

    return '';
  }

  // ============================================================
  // TASK SITE NAME
  // ============================================================

  String _taskSiteName() {
    final taskName = widget.taskSiteName?.trim();

    if (taskName != null && taskName.isNotEmpty) {
      return taskName;
    }

    final activeSite = _activeCheckIn?['site'];

    if (activeSite is Map) {
      final activeName = activeSite['name']?.toString().trim();

      if (activeName != null && activeName.isNotEmpty) {
        return activeName;
      }
    }

    final userSite = widget.user['site'];

    if (userSite is Map) {
      final userName = userSite['name']?.toString().trim();

      if (userName != null && userName.isNotEmpty) {
        return userName;
      }
    }

    return 'Assigned Site';
  }

  // ============================================================
  // TASK SITE CODE
  // ============================================================

  String _taskSiteCode() {
    final taskCode = widget.taskSiteCode?.trim();

    if (taskCode != null && taskCode.isNotEmpty) {
      return taskCode;
    }

    final activeSite = _activeCheckIn?['site'];

    if (activeSite is Map) {
      final activeCode = activeSite['siteCode']?.toString().trim();

      if (activeCode != null && activeCode.isNotEmpty) {
        return activeCode;
      }
    }

    final userSite = widget.user['site'];

    if (userSite is Map) {
      final userCode = userSite['siteCode']?.toString().trim();

      if (userCode != null && userCode.isNotEmpty) {
        return userCode;
      }
    }

    return '';
  }

  // ============================================================
  // CHECK-IN SITE ID
  // ============================================================

  String _checkInSiteId(Map<String, dynamic> checkIn) {
    final directId = checkIn['siteId']?.toString().trim();

    if (directId != null && directId.isNotEmpty) {
      return directId;
    }

    final site = checkIn['site'];

    if (site is Map) {
      final nestedId = site['id']?.toString().trim();

      if (nestedId != null && nestedId.isNotEmpty) {
        return nestedId;
      }
    }

    return '';
  }
  
  // ============================================================
  // CURRENT LOCATION
  // ============================================================

  Future<Position> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception('Location service is disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission permanently denied. '
        'Please enable it from phone settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception(
          'Unable to get your current location. '
          'Please make sure GPS is enabled.',
        );
      },
    );
  }

  // ============================================================
  // LOAD ATTENDANCE
  // ============================================================

Future<void> _loadAttendance() async {
    try {
      if (mounted) {
        setState(() {
          _attendanceLoading = true;
          _error = '';
        });
      }

      // ----------------------------------------------------------
      // ONLY CHECK ATTENDANCE FOR THIS TASK SITE
      // ----------------------------------------------------------

      final siteId = _taskSiteId();

      if (siteId.isEmpty) {
        throw Exception('This task does not have a valid site.');
      }

      final response = await ApiService.getCheckIns(
        accessToken: widget.accessToken,
        page: 1,
        limit: 100,
        siteId: siteId,
      );

      final data = response['data'];

      List<dynamic> checkIns = [];

      if (data is Map && data['checkIns'] is List) {
        checkIns = data['checkIns'];
      } else if (response['checkIns'] is List) {
        checkIns = response['checkIns'];
      }

      Map<String, dynamic>? active;

      for (final item in checkIns) {
        if (item is! Map) {
          continue;
        }

        final checkIn = Map<String, dynamic>.from(item);

        final status = checkIn['status']?.toString().trim().toUpperCase();

        final returnedSiteId =
            checkIn['siteId']?.toString() ??
            (checkIn['site'] is Map ? checkIn['site']['id']?.toString() : null);

        final checkOutAt = checkIn['checkOutAt'];

        final isCheckedIn =
            status == 'CHECKED_IN' ||
            status == 'CHECKED-IN' ||
            status == 'CHECKED IN';

        final hasNoCheckout =
            checkOutAt == null ||
            checkOutAt.toString().trim().isEmpty ||
            checkOutAt.toString().trim().toLowerCase() == 'null';

        if (returnedSiteId == siteId && isCheckedIn && hasNoCheckout) {
          active = checkIn;
          break;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _activeCheckIn = active;
        _attendanceLoading = false;
      });

      // ----------------------------------------------------------
      // ALREADY CHECKED IN FOR THIS TASK SITE
      // ----------------------------------------------------------

      if (widget.returnAfterCheckIn && active != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _attendanceLoading = false;
        _error = _cleanError(e);
      });
    }
  }

  // ============================================================
  // CLEAN ERROR
  // ============================================================

  String _cleanError(Object error) {
    var message = error.toString().trim();

    if (message.startsWith('Exception:')) {
      message = message.substring('Exception:'.length).trim();
    }

    return message.isEmpty ? 'Something went wrong.' : message;
  }

  // ============================================================
  // RESPONSE MESSAGE
  // ============================================================

  String _responseMessage(Map<String, dynamic> response, String fallback) {
    final message = response['message']?.toString().trim();

    if (message != null && message.isNotEmpty) {
      return message;
    }

    final data = response['data'];

    if (data is Map) {
      final dataMessage = data['message']?.toString().trim();

      if (dataMessage != null && dataMessage.isNotEmpty) {
        return dataMessage;
      }
    }

    final error = response['error']?.toString().trim();

    if (error != null && error.isNotEmpty) {
      return error;
    }

    return fallback;
  }

  // ============================================================
  // CHECK-IN
  // ============================================================

Future<void> _checkIn() async {
    if (_processing) {
      return;
    }

    final siteId = _taskSiteId();

    if (siteId.isEmpty) {
      _showMessage('This task does not have a valid site.', isError: true);
      return;
    }

    try {
      setState(() {
        _processing = true;
        _error = '';
      });

      final position = await _getCurrentLocation();

      final response = await ApiService.createCheckIn(
        accessToken: widget.accessToken,
        siteId: siteId,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      final data = response['data'];

      Map<String, dynamic>? checkIn;

      if (data is Map && data['checkIn'] is Map) {
        checkIn = Map<String, dynamic>.from(data['checkIn']);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _activeCheckIn = checkIn;
        _processing = false;
      });

      // ----------------------------------------------------------
      // RETURN TO AUDIT
      // ----------------------------------------------------------

      if (widget.returnAfterCheckIn) {
        Navigator.of(context).pop(true);
        return;
      }

      _showMessage(
        response['message'] ?? 'Check-in successful',
        isError: false,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _processing = false;
      });

      _showMessage(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }
  // ============================================================
  // CHECK-OUT
  // ============================================================

  Future<void> _checkOut() async {
    if (_processing || _attendanceLoading) {
      return;
    }

    final checkIn = _activeCheckIn;

    if (checkIn == null) {
      await _loadAttendance();
      return;
    }

    final checkInId = checkIn['id']?.toString().trim() ?? '';

    if (checkInId.isEmpty) {
      _showMessage('Active check-in record is invalid.', isError: true);
      return;
    }

    try {
      if (!mounted) {
        return;
      }

      setState(() {
        _processing = true;
        _error = '';
      });

      debugPrint('CHECK-IN SCREEN: Checking out $checkInId');

      final position = await _getCurrentLocation();

      final response =
          await ApiService.checkOut(
            accessToken: widget.accessToken,
            checkInId: checkInId,
            latitude: position.latitude,
            longitude: position.longitude,
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception(
                'Check-out request timed out. '
                'Please check that the backend is running.',
              );
            },
          );

      debugPrint('CHECK-IN SCREEN: checkOut response = $response');

      final success = response['success'] == true;

      if (!success) {
        if (!mounted) {
          return;
        }

        setState(() {
          _processing = false;
        });

        _showMessage(
          _responseMessage(response, 'Check-out failed.'),
          isError: true,
        );

        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _activeCheckIn = null;
        _processing = false;
        _error = '';
      });

      _showMessage(
        _responseMessage(response, 'Check-out successful'),
        isError: false,
      );

      await _loadAttendance();
    } catch (e) {
      debugPrint('CHECK-IN SCREEN CHECK-OUT ERROR: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _processing = false;
      });

      _showMessage(_cleanError(e), isError: true);
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) {
      return;
    }

    final cleaned = message.trim().isEmpty
        ? 'Something went wrong.'
        : message.trim();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(cleaned),
          backgroundColor: isError
              ? Colors.red.shade700
              : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  // ============================================================
  // FORMAT DATE TIME
  // ============================================================

  String _formatDateTime(dynamic value) {
    if (value == null) {
      return '—';
    }

    final date = DateTime.tryParse(value.toString());

    if (date == null) {
      return '—';
    }

    final local = date.toLocal();

    final day = local.day.toString().padLeft(2, '0');

    final month = local.month.toString().padLeft(2, '0');

    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;

    final minute = local.minute.toString().padLeft(2, '0');

    final period = local.hour >= 12 ? 'PM' : 'AM';

    return '$day/$month/${local.year} '
        '$hour:$minute $period';
  }

  // ============================================================
  // STATUS CARD
  // ============================================================

  Widget _statusCard() {
    final checkedIn = _activeCheckIn != null;

    final taskSiteId = _taskSiteId();

    final activeSite = _activeCheckIn?['site'];

    final activeSiteId = _activeCheckIn != null
        ? _checkInSiteId(_activeCheckIn!)
        : '';

    final checkedInAtTaskSite =
        checkedIn && taskSiteId.isNotEmpty && activeSiteId == taskSiteId;

    final displayedSiteName = checkedIn
        ? (activeSite is Map
              ? (activeSite['name']?.toString().trim().isNotEmpty == true
                    ? activeSite['name'].toString().trim()
                    : 'Current Site')
              : 'Current Site')
        : _taskSiteName();

    final displayedSiteCode = checkedIn
        ? (activeSite is Map
              ? (activeSite['siteCode']?.toString().trim() ?? '')
              : '')
        : _taskSiteCode();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: checkedIn
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: _attendanceLoading
                ? const Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  )
                : Icon(
                    checkedIn
                        ? Icons.check_circle_outline
                        : Icons.login_rounded,
                    size: 38,
                    color: checkedIn
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF2563EB),
                  ),
          ),

          const SizedBox(height: 14),

          Text(
            _attendanceLoading
                ? 'Checking Attendance...'
                : checkedIn
                ? checkedInAtTaskSite
                      ? 'You are Checked In'
                      : 'Already Checked In'
                : 'You are Not Checked In',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            _attendanceLoading
                ? 'Checking your current check-in status.'
                : checkedIn
                ? checkedInAtTaskSite
                      ? 'Your attendance is active for this task site.'
                      : 'Check out from the current site before checking in to another site.'
                : 'Check in before starting your field work.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),

          const SizedBox(height: 18),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _infoRow(
                  Icons.business_outlined,
                  checkedIn ? 'Current Site' : 'Task Site',
                  displayedSiteName,
                ),

                if (displayedSiteCode.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _infoRow(
                    Icons.qr_code_2_rounded,
                    'Site Code',
                    displayedSiteCode,
                  ),
                ],

                if (checkedIn) ...[
                  const SizedBox(height: 10),
                  _infoRow(
                    Icons.access_time_rounded,
                    'Check-in Time',
                    _formatDateTime(_activeCheckIn?['checkInAt']),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INFO ROW
  // ============================================================

  Widget _infoRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, size: 19, color: const Color(0xFF6B7280)),

        const SizedBox(width: 9),

        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ),

        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ACTION BUTTON
  // ============================================================

  Widget _actionButton() {
    final checkedIn = _activeCheckIn != null;

    final disabled = _processing || _attendanceLoading;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: disabled
            ? null
            : checkedIn
            ? _checkOut
            : _checkIn,
        icon: disabled
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(checkedIn ? Icons.logout_rounded : Icons.login_rounded),
        label: Text(
          _attendanceLoading
              ? 'Checking...'
              : _processing
              ? 'Please wait...'
              : checkedIn
              ? 'Check Out'
              : 'Check In',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: checkedIn
              ? const Color(0xFFDC2626)
              : const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Check In & Check Out',
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w800,
            fontSize: 19,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),

      body: RefreshIndicator(
        onRefresh: _loadAttendance,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _statusCard(),

              const SizedBox(height: 18),

              _actionButton(),

              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    _error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 18),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 20,
                      color: Color(0xFF2563EB),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your current GPS location is captured during check-in and check-out.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          height: 1.4,
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
