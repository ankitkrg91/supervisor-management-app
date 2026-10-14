import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

class VisitCaptureScreen extends StatefulWidget {
  final String siteName;
  final String siteCode;
  const VisitCaptureScreen({
    super.key,
    required this.siteName,
    required this.siteCode,
  });

  @override
  State<VisitCaptureScreen> createState() => _VisitCaptureScreenState();
}

class _VisitCaptureScreenState extends State<VisitCaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _namePlatePhoto;
  File? _selfiePhoto;
  File? _sitePhoto;
  Position? _position;
  bool _loadingLocation = false;
  bool _processing = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _takePhoto(String type) async {
    try {
      setState(() => _error = '');
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 55,
        maxWidth: 1024,
        maxHeight: 1024,
        preferredCameraDevice: type == 'SELFIE'
            ? CameraDevice.front
            : CameraDevice.rear,
      );
      if (image == null || !mounted) return;
      setState(() {
        if (type == 'NAMEPLATE')
          _namePlatePhoto = File(image.path);
        else if (type == 'SELFIE')
          _selfiePhoto = File(image.path);
        else
          _sitePhoto = File(image.path);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Unable to capture photo: $e');
    }
  }

  Future<void> _getLocation() async {
    try {
      setState(() {
        _loadingLocation = true;
        _error = '';
      });
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location service is disabled. Please enable GPS.');
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Location permission denied.');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
      if (mounted) setState(() => _position = pos);
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _proceedToAudit() async {
    if (_namePlatePhoto == null)
      return setState(() => _error = 'Please capture Client Name Plate Photo.');
    if (_selfiePhoto == null)
      return setState(() => _error = 'Please capture Supervisor Selfie.');
    if (_sitePhoto == null)
      return setState(() => _error = 'Please capture Photo 1 (Site Entrance).');
    if (_position == null)
      return setState(() => _error = 'Please verify GPS location.');

    try {
      setState(() {
        _processing = true;
        _error = '';
      });
      final npB64 =
          'data:image/jpeg;base64,${base64Encode(await _namePlatePhoto!.readAsBytes())}';
      final sfB64 =
          'data:image/jpeg;base64,${base64Encode(await _selfiePhoto!.readAsBytes())}';
      final stB64 =
          'data:image/jpeg;base64,${base64Encode(await _sitePhoto!.readAsBytes())}';
      if (!mounted) return;
      Navigator.of(context).pop({
        'namePlatePhoto': npB64,
        'selfiePhoto': sfB64,
        'sitePhoto': stB64,
        'photoUrl': stB64,
        'photoFileId': 'EVIDENCE_${DateTime.now().millisecondsSinceEpoch}',
        'latitude': _position!.latitude,
        'longitude': _position!.longitude,
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _processing = false;
          _error = 'Failed to process photos: $e';
        });
    }
  }

  Widget _buildPhotoSlot(
    String title,
    String sub,
    File? file,
    VoidCallback onTap,
    IconData icon,
  ) {
    final ok = file != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ok ? const Color(0xFFA7F3D0) : const Color(0xFFE5E7EB),
          width: ok ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD1D5DB)),
            ),
            child: ok
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.file(file, fit: BoxFit.cover),
                  )
                : Icon(icon, size: 28, color: const Color(0xFF9CA3AF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ok ? 'Photo Captured ✓' : sub,
                  style: TextStyle(
                    fontSize: 12,
                    color: ok
                        ? const Color(0xFF059669)
                        : const Color(0xFF6B7280),
                    fontWeight: ok ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: ok
                  ? const Color(0xFFEFF6FF)
                  : const Color(0xFF2563EB),
              foregroundColor: ok ? const Color(0xFF2563EB) : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              ok ? 'Retake' : 'Capture',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        title: const Text(
          'Site Evidence Photos (3 Required)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(
                '${widget.siteName} ${widget.siteCode.isNotEmpty ? "(${widget.siteCode})" : ""}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A8A),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_error.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Text(
                  _error,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 13,
                  ),
                ),
              ),
            _buildPhotoSlot(
              'CLIENT NAME PLATE PHOTO',
              'Branch / office sign board',
              _namePlatePhoto,
              () => _takePhoto('NAMEPLATE'),
              Icons.badge_outlined,
            ),
            _buildPhotoSlot(
              'SELFIE',
              'Front camera supervisor selfie',
              _selfiePhoto,
              () => _takePhoto('SELFIE'),
              Icons.person_outline,
            ),
            _buildPhotoSlot(
              'PHOTO 1 (SITE ENTRANCE)',
              'Site entrance / overview photo',
              _sitePhoto,
              () => _takePhoto('SITE'),
              Icons.camera_alt_outlined,
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: _position != null
                        ? const Color(0xFF059669)
                        : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loadingLocation
                          ? 'Fetching GPS...'
                          : (_position != null
                                ? 'GPS Verified: ${_position!.latitude.toStringAsFixed(5)}, ${_position!.longitude.toStringAsFixed(5)}'
                                : 'GPS not acquired'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _position != null
                            ? const Color(0xFF059669)
                            : Colors.black54,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.refresh,
                      size: 20,
                      color: Color(0xFF2563EB),
                    ),
                    onPressed: _getLocation,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _processing ? null : _proceedToAudit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _processing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'PROCEED TO AUDIT CHECKLIST',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
