import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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
  // ============================================================
  // PUT YOUR GOOGLE APPS SCRIPT WEB APP URL HERE
  // ============================================================

static const String appsScriptUrl =
      'https://script.google.com/macros/s/AKfycbyhMb46Rjbe98HzdGzCZ2U2F5kDkSREqDZyjbq_lz_w_5HKjyEKNyFkiLmtX9Jc3ePZQw/exec';

  final ImagePicker _picker = ImagePicker();

  File? _photo;

  Position? _position;

  bool _loadingLocation = false;
  bool _uploading = false;

  String _error = '';

  // ============================================================
  // PICK PHOTO FROM CAMERA
  // ============================================================

  Future<void> _takePhoto() async {
    try {
      setState(() {
        _error = '';
      });

      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (image == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _photo = File(image.path);
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'Unable to open camera: $e';
      });
    }
  }

  // ============================================================
  // GET CURRENT GPS
  // ============================================================

  Future<void> _getLocation() async {
    try {
      setState(() {
        _loadingLocation = true;
        _error = '';
      });

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
          'Location permission permanently denied. Please enable it from phone settings.',
        );
      }

      final position =
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('Unable to get current GPS location.');
            },
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _position = position;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingLocation = false;
        });
      }
    }
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  bool _validate() {
    if (_photo == null) {
      setState(() {
        _error = 'Please take a site photo first.';
      });

      return false;
    }

    if (_position == null) {
      setState(() {
        _error = 'Please capture your GPS location first.';
      });

      return false;
    }

    if (appsScriptUrl.trim().isEmpty ||
        appsScriptUrl.contains('PASTE_YOUR_GOOGLE')) {
      setState(() {
        _error = 'Google Apps Script URL is not configured.';
      });

      return false;
    }

    return true;
  }

  // ============================================================
  // UPLOAD PHOTO TO GOOGLE APPS SCRIPT
  // HANDLES GOOGLE'S 302 REDIRECT
  // ============================================================

  Future<Map<String, dynamic>?> _uploadPhotoToGoogleDrive() async {
    final photo = _photo;

    if (photo == null) {
      return null;
    }

    try {
      final bytes = await photo.readAsBytes();

      final base64Image = base64Encode(bytes);

      final uploadId =
          'visit_${DateTime.now().millisecondsSinceEpoch}_'
          '${DateTime.now().microsecondsSinceEpoch}';

      final fileName = 'visit_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final uri = Uri.parse(appsScriptUrl);

      /*
     * ========================================================
     * STEP 1
     * POST PHOTO
     *
     * We do NOT depend on the POST response because
     * Google Apps Script may return HTTP 302.
     * ========================================================
     */

      try {
        await http
            .post(
              uri,

              headers: {'Content-Type': 'application/json'},

              body: jsonEncode({
                'action': 'uploadVisitPhoto',

                'uploadId': uploadId,

                'fileName': fileName,

                'mimeType': 'image/jpeg',

                'imageBase64': base64Image,

                'siteCode': widget.siteCode,

                'siteName': widget.siteName,
              }),
            )
            .timeout(const Duration(seconds: 60));
      } catch (_) {
        /*
       * Ignore the POST response/redirect error here.
       *
       * The Apps Script may already have created the
       * Google Drive file.
       *
       * We will retrieve the result using uploadId.
       */
      }

      /*
     * ========================================================
     * STEP 2
     * WAIT AND ASK APPS SCRIPT FOR RESULT
     * ========================================================
     */

      Map<String, dynamic>? result;

      for (int attempt = 0; attempt < 6; attempt++) {
        await Future.delayed(Duration(milliseconds: attempt == 0 ? 700 : 1000));

        try {
          final lookupUri = uri.replace(
            queryParameters: {'uploadId': uploadId},
          );

          final lookupResponse = await http
              .get(lookupUri)
              .timeout(const Duration(seconds: 20));

          if (lookupResponse.statusCode < 200 ||
              lookupResponse.statusCode >= 300) {
            continue;
          }

          final body = lookupResponse.body.trim();

          if (body.isEmpty) {
            continue;
          }

          dynamic decoded;

          try {
            decoded = jsonDecode(body);
          } catch (_) {
            continue;
          }

          if (decoded is! Map) {
            continue;
          }

          final data = Map<String, dynamic>.from(decoded);

          if (data['success'] == true) {
            result = data;

            break;
          }
        } catch (_) {
          continue;
        }
      }

      /*
     * ========================================================
     * STEP 3
     * FINAL RESULT
     * ========================================================
     */

      if (result == null) {
        throw Exception(
          'Google Drive upload completed, but upload result could not be retrieved.',
        );
      }

      final photoUrl = result['photoUrl']?.toString().trim();

      final photoFileId = result['fileId']?.toString().trim();

      if (photoUrl == null || photoUrl.isEmpty) {
        throw Exception('Google Drive photo URL was not returned.');
      }

      return {
        'success': true,

        'photoUrl': photoUrl,

        'photoFileId': photoFileId ?? '',

        'fileId': photoFileId ?? '',

        'thumbnailUrl': result['thumbnailUrl']?.toString().trim() ?? '',
      };
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }
  // ============================================================
  // SUBMIT
  // ============================================================

  Future<void> _submit() async {
    if (_uploading) {
      return;
    }

    if (!_validate()) {
      return;
    }

    try {
      setState(() {
        _uploading = true;
        _error = '';
      });

      final uploadResult = await _uploadPhotoToGoogleDrive();

      if (uploadResult == null) {
        throw Exception('Photo upload failed.');
      }

      final photoUrl = uploadResult['photoUrl']?.toString();

      final photoFileId = uploadResult['fileId']?.toString();

      if (photoUrl == null || photoUrl.trim().isEmpty) {
        throw Exception('Photo URL was not returned.');
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop({
        'photoUrl': photoUrl.trim(),

        'photoFileId': photoFileId,

        'latitude': _position!.latitude,

        'longitude': _position!.longitude,
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final latitude = _position?.latitude;

    final longitude = _position?.longitude;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      appBar: AppBar(
        backgroundColor: Colors.white,

        surfaceTintColor: Colors.white,

        elevation: 0,

        title: const Text(
          'Submit Site Visit',
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // ==================================================
              // SITE
              // ==================================================

              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(16),

                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      'Visit Site',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      widget.siteName.trim().isNotEmpty
                          ? widget.siteName
                          : 'Site',

                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),

                    if (widget.siteCode.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),

                      Text(
                        widget.siteCode,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ==================================================
              // PHOTO
              // ==================================================
              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(16),

                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [
                    const Text(
                      'Site Photo',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (_photo != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),

                        child: Image.file(
                          _photo!,
                          height: 300,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        height: 220,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.photo_camera_outlined,
                            size: 60,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ),

                    const SizedBox(height: 14),

                    ElevatedButton.icon(
                      onPressed: _uploading ? null : _takePhoto,

                      icon: const Icon(Icons.photo_camera),

                      label: Text(
                        _photo == null ? 'Take Site Photo' : 'Retake Photo',
                      ),

                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ==================================================
              // GPS
              // ==================================================
              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(16),

                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,

                  children: [
                    const Text(
                      'GPS Location',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(14),

                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),

                        borderRadius: BorderRadius.circular(12),
                      ),

                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: Color(0xFF2563EB),
                          ),

                          const SizedBox(width: 10),

                          Expanded(
                            child: _position == null
                                ? const Text(
                                    'GPS location not captured.',
                                    style: TextStyle(color: Color(0xFF6B7280)),
                                  )
                                : Text(
                                    'Latitude: ${latitude!.toStringAsFixed(6)}\n'
                                    'Longitude: ${longitude!.toStringAsFixed(6)}',

                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    OutlinedButton.icon(
                      onPressed: _loadingLocation || _uploading
                          ? null
                          : _getLocation,

                      icon: _loadingLocation
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),

                      label: Text(
                        _position == null
                            ? 'Capture Current GPS'
                            : 'Refresh GPS',
                      ),

                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ==================================================
              // ERROR
              // ==================================================
              if (_error.trim().isNotEmpty)
                Container(
                  width: double.infinity,

                  margin: const EdgeInsets.only(bottom: 16),

                  padding: const EdgeInsets.all(14),

                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),

                    borderRadius: BorderRadius.circular(12),

                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),

                  child: Text(
                    _error,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              // ==================================================
              // SUBMIT
              // ==================================================
              SizedBox(
                width: double.infinity,

                height: 54,

                child: ElevatedButton.icon(
                  onPressed: _uploading ? null : _submit,

                  icon: _uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload_outlined),

                  label: Text(
                    _uploading ? 'Uploading...' : 'Upload & Submit Visit',
                  ),

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
