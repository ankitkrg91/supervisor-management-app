import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';

class CheckInCheckOutScreen extends StatefulWidget {
  final String accessToken;
  final Map<String, dynamic> user;

  final String? taskSiteId;
  final String? taskSiteName;
  final String? taskSiteCode;
  final double? taskSiteLatitude;
  final double? taskSiteLongitude;

  final bool returnAfterCheckIn;

  const CheckInCheckOutScreen({
    super.key,
    required this.accessToken,
    required this.user,
    this.taskSiteId,
    this.taskSiteName,
    this.taskSiteCode,
    this.taskSiteLatitude,
    this.taskSiteLongitude,
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

  String _cleanError(Object error) {
    var message = error.toString().trim();

    if (message.startsWith('Exception:')) {
      message = message.substring('Exception:'.length).trim();
    }

    return message.isEmpty ? 'Something went wrong.' : message;
  }

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
  // CHECK-IN (STANDARD OR ALTERNATE/RAIN)
  // ============================================================

  Future<void> _checkIn({
    bool isAlternate = false,
    String? alternateReason,
  }) async {
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

      // Enforce 100-meter geofence ONLY if NOT in Alternate/Rain mode
      if (!isAlternate) {
        double? targetLat = widget.taskSiteLatitude;
        double? targetLng = widget.taskSiteLongitude;

        if (targetLat == null || targetLng == null) {
          final s = widget.user['site'] ?? _activeCheckIn?['site'];
          if (s is Map) {
            targetLat = (s['latitude'] as num?)?.toDouble();
            targetLng = (s['longitude'] as num?)?.toDouble();
          }
        }

        if (targetLat != null && targetLng != null) {
          final distanceMeters = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            targetLat,
            targetLng,
          );

          if (distanceMeters > 100) {
            final roundedDist = distanceMeters.round();
            final siteName = _taskSiteName();
            setState(() {
              _processing = false;
            });
            _showMessage(
              "You are ${roundedDist}m away from $siteName. Standard Check-In strictly requires being within 100m.\n\n👉 If you cannot reach the site due to rain or emergency, please tap 'Rain / Weather Emergency Check-In'.",
              isError: true,
            );
            return;
          }
        }
      }

      final response = await ApiService.createCheckIn(
        accessToken: widget.accessToken,
        siteId: siteId,
        latitude: position.latitude,
        longitude: position.longitude,
        isAlternate: isAlternate,
        alternateReason: alternateReason,
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

      if (widget.returnAfterCheckIn) {
        Navigator.of(context).pop(true);
        return;
      }

      _showMessage(
        response['message'] ??
            (isAlternate
                ? 'Rain/Emergency Check-in successful!'
                : 'Check-in successful!'),
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
  // ALTERNATE / RAIN EMERGENCY MODAL DIALOG
  // ============================================================

  Future<void> _showAlternateCheckInDialog() async {
    String selectedReason = '🌧️ Heavy Rain / Waterlogging';
    final customController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final reasons = [
              '🌧️ Heavy Rain / Waterlogging',
              '⚡ Severe Storm / Extreme Weather',
              '🚫 Road Blockage / Flooding',
              '🚗 Transport / Vehicle Breakdown',
              '🏢 Client Office Closed / Inaccessible',
              '📝 Other Emergency Reason',
            ];

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.thunderstorm_outlined,
                          color: Color(0xFFD97706),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rain / Emergency Check-In',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            Text(
                              'Bypasses 100m geofence with GPS stamp',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select Emergency Reason:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...reasons.map(
                    (r) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: r,
                      groupValue: selectedReason,
                      activeColor: const Color(0xFFD97706),
                      title: Text(
                        r,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedReason = val);
                        }
                      },
                    ),
                  ),
                  if (selectedReason == '📝 Other Emergency Reason') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: customController,
                      decoration: InputDecoration(
                        hintText: 'Enter reason for remote check-in...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        if (selectedReason == '📝 Other Emergency Reason' &&
                            customController.text.trim().isNotEmpty) {
                          selectedReason = customController.text.trim();
                        }
                        Navigator.of(ctx).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Confirm & Check In (Bypass Geofence)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed == true) {
      _checkIn(isAlternate: true, alternateReason: selectedReason);
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
      _showMessage('Invalid active check-in record.', isError: true);
      return;
    }

    try {
      setState(() {
        _processing = true;
        _error = '';
      });

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
                'Check-out request timed out. Please check backend connection.',
              );
            },
          );

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_responseMessage(response, 'Check-out successful')),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );

      Navigator.of(context).pop(true);
      return;
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _processing = false;
      });

      _showMessage(_cleanError(e), isError: true);
    }
  }

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

    return '$day/$month/${local.year} $hour:$minute $period';
  }

  Widget _statusCard() {
    final checkedIn = _activeCheckIn != null;
    final displayedSiteName = _taskSiteName();
    final displayedSiteCode = _taskSiteCode();

    final isAlternateMode =
        _activeCheckIn?['isAlternate'] == true ||
        _activeCheckIn?['alternateReason'] != null;

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
                  ? (isAlternateMode
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFFDCFCE7))
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
                        ? (isAlternateMode
                              ? Icons.cloudy_snowing
                              : Icons.check_circle_outline)
                        : Icons.login_rounded,
                    size: 38,
                    color: checkedIn
                        ? (isAlternateMode
                              ? const Color(0xFFD97706)
                              : const Color(0xFF16A34A))
                        : const Color(0xFF2563EB),
                  ),
          ),

          const SizedBox(height: 14),

          Text(
            _attendanceLoading
                ? 'Checking Attendance...'
                : checkedIn
                ? (isAlternateMode
                      ? 'Checked In (Rain/Emergency)'
                      : 'You are Checked In')
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
                ? (isAlternateMode
                      ? 'Attendance active via Weather Exception (${_activeCheckIn?['alternateReason'] ?? "Emergency"}).'
                      : 'Your attendance is active for this task site.')
                : 'Check in on-site (within 100m) or use Rain Check-In if unable to reach site.',
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
                _infoRow(Icons.business_outlined, 'Site', displayedSiteName),

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

                if (checkedIn && isAlternateMode) ...[
                  const SizedBox(height: 10),
                  _infoRow(
                    Icons.thunderstorm_outlined,
                    'Check-in Mode',
                    '🌧️ Rain / Weather Exception',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF4B5563),
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Expanded(
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
            : () => _checkIn(isAlternate: false),
        icon: disabled
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                checkedIn ? Icons.logout_rounded : Icons.location_on_rounded,
              ),
        label: Text(
          _attendanceLoading
              ? 'Checking...'
              : _processing
              ? 'Please wait...'
              : checkedIn
              ? 'Check Out'
              : 'Standard Check In (Within 100m)',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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

  Widget _alternateActionButton() {
    final checkedIn = _activeCheckIn != null;
    if (checkedIn) return const SizedBox.shrink();

    final disabled = _processing || _attendanceLoading;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          onPressed: disabled ? null : _showAlternateCheckInDialog,
          icon: const Icon(
            Icons.thunderstorm_outlined,
            color: Color(0xFFD97706),
            size: 20,
          ),
          label: const Text(
            '🌧️ Rain / Weather Emergency Check-In',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFFD97706),
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
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
              _alternateActionButton(),
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
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
