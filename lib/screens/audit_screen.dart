import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class AuditScreen extends StatefulWidget {
  final String visitId;
  final String accessToken;
  final String title;
  final String? clientName;
  final String? clientMobile;
  final String? supervisorName;
  final String? siteName;
  final String? siteCode;

  const AuditScreen({
    super.key,
    required this.visitId,
    required this.accessToken,
    this.title = 'MSF',
    this.clientName,
    this.clientMobile,
    this.supervisorName,
    this.siteName,
    this.siteCode,
  });

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  bool _loading = true;
  bool _submitting = false;
  bool _submitted = false;
  String _errorMessage = '';
  String? _templateId;
  String _templateName = '';
  List<Map<String, dynamic>> _questions = [];
  final Map<String, bool> _answers = {};
  final Map<String, List<String>> _questionPhotos = {};
  final ImagePicker _picker = ImagePicker();

  // LIVE RENDER SERVER DOMAIN (Accessible on any phone over the internet)
  static const String _publicWebBaseUrl =
      'https://supervisor-management-backend.onrender.com';

  @override
  void initState() {
    super.initState();
    _loadChecklist();
  }

  bool _isPhotoRequired(Map<String, dynamic> q) {
    if (q['requiresPhoto'] == true || q['photo'] == true) return true;
    final t = (q['question'] ?? q['text'] ?? '').toString().toUpperCase();
    for (final kw in [
      'TURNOUT', 'UNIFORM', 'GROOMING', 'APP', 'LOBBY', 'PANTRY',
      'WASH', 'CABIN', 'REGISTER', 'CHECKLIST', 'TRAINING', 'PHOTO',
      'ROOM', 'HOUSEKEEPING', 'AREA', 'CLEAN', 'FIRE', 'SECURITY'
    ]) {
      if (t.contains(kw)) return true;
    }
    return false;
  }

  Future<void> _loadChecklist() async {
    try {
      setState(() {
        _loading = true;
        _errorMessage = '';
      });
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/audit/checklist'),
        headers: {
          'Authorization': 'Bearer ${widget.accessToken}',
          'Content-Type': 'application/json',
        },
      );
      final data = _decodeResponse(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(data['message'] ?? 'Failed to load audit checklist.');
      }
      final checklist = data['data']?['checklist'] ?? data['checklist'];
      if (checklist == null) throw Exception('Audit checklist not found.');
      final rawQuestions = checklist['questions'];
      final List<Map<String, dynamic>> active = [];
      if (rawQuestions is List) {
        for (final item in rawQuestions) {
          if (item is Map<String, dynamic> && item['isActive'] != false) {
            active.add(Map<String, dynamic>.from(item));
          }
        }
      }
      active.sort((a, b) => (int.tryParse('${a['questionNo']}') ?? 0)
          .compareTo(int.tryParse('${b['questionNo']}') ?? 0));
      for (int i = 0; i < active.length; i++) {
        active[i]['displayNo'] = i + 1;
        active[i]['questionNo'] = i + 1;
      }
      if (!mounted) return;
      setState(() {
        _templateId = checklist['id']?.toString();
        _templateName = checklist['name']?.toString() ?? widget.title;
        _questions = active;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response r) {
    try {
      final d = jsonDecode(r.body);
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _selectAnswer(Map<String, dynamic> question, bool value) async {
    if (_submitted || _submitting) return;
    final qId = question['id']?.toString() ?? '';
    if (qId.isEmpty) return;
    setState(() {
      _answers[qId] = value;
      _errorMessage = '';
    });
    final existing = _questionPhotos[qId] ?? [];
    if (value == true && _isPhotoRequired(question) && existing.isEmpty) {
      await _capturePhoto(qId, question['question']?.toString() ?? 'Checkpoint');
    }
  }

  Future<void> _capturePhoto(String questionId, String title) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 55,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (photo != null && mounted) {
        setState(() {
          _questionPhotos.putIfAbsent(questionId, () => []).add(photo.path);
          _answers[questionId] = true;
          _errorMessage = '';
        });
      }
    } catch (e) {
      _showMessage('Failed to capture photo: $e', isError: true);
    }
  }

  void _removePhoto(String questionId, int index) {
    setState(() {
      _questionPhotos[questionId]?.removeAt(index);
      if (_questionPhotos[questionId]?.isEmpty ?? false) {
        _questionPhotos.remove(questionId);
      }
    });
  }

  String? _validateAnswers() {
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final qId = q['id']?.toString() ?? '';
      if (qId.isEmpty) continue;
      if (q['isRequired'] != false && !_answers.containsKey(qId)) {
        return 'Please answer Question Q${i + 1}.';
      }
    }
    return null;
  }

  Future<void> _sendWhatsAppReport() async {
    final siteCode = widget.siteCode ?? '';
    final siteName = widget.siteName ?? 'Client Site';
    final sup = (widget.supervisorName ?? '').isNotEmpty
        ? widget.supervisorName!
        : 'SUPERVISOR';

    final auditUrl = '$_publicWebBaseUrl/audit-view/${widget.visitId}';
    final fbUrl = '$_publicWebBaseUrl/feedback/${widget.visitId}';

    final msg =
        'The Site: $siteCode $siteName has been visited by Operation Executive $sup.\n\n'
        'Click to view audit report: $auditUrl\n'
        'Share feedback: $fbUrl\n\n'
        'Thanks and regards,\n'
        'Security Operations Centre: 18002021055\n'
        'VINICIA SECURITY SERVICES PVT LTD';

    String rawPhone = (widget.clientMobile ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (rawPhone.startsWith('0') && rawPhone.length == 11) {
      rawPhone = rawPhone.substring(1);
    }

    final phoneParam = rawPhone.length == 10
        ? '91$rawPhone'
        : (rawPhone.length > 10 ? rawPhone : '');

    final enc = Uri.encodeComponent(msg);
    final appUri = phoneParam.isNotEmpty
        ? Uri.parse('whatsapp://send?phone=$phoneParam&text=$enc')
        : Uri.parse('whatsapp://send?text=$enc');

    final waMeUri = phoneParam.isNotEmpty
        ? Uri.parse('https://wa.me/$phoneParam?text=$enc')
        : Uri.parse('https://wa.me/?text=$enc');

    final webUri = phoneParam.isNotEmpty
        ? Uri.parse('https://api.whatsapp.com/send?phone=$phoneParam&text=$enc')
        : Uri.parse('https://api.whatsapp.com/send?text=$enc');

    try {
      if (!await launchUrl(appUri, mode: LaunchMode.externalApplication)) {
        if (!await launchUrl(waMeUri, mode: LaunchMode.externalApplication)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (_) {
      try {
        if (!await launchUrl(waMeUri, mode: LaunchMode.externalApplication)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _submitAudit() async {
    if (_submitted || _submitting) return;
    if (_templateId == null || _templateId!.isEmpty) {
      return setState(() => _errorMessage = 'Audit template missing.');
    }
    final err = _validateAnswers();
    if (err != null) {
      setState(() => _errorMessage = err);
      _showMessage(err, isError: true);
      return;
    }

    final List<Map<String, dynamic>> answersPayload = [];
    for (final q in _questions) {
      final qId = q['id']?.toString();
      if (qId == null || !_answers.containsKey(qId)) continue;
      final paths = _questionPhotos[qId] ?? [];
      final List<String> b64List = [];
      for (final p in paths) {
        try {
          final f = File(p);
          if (await f.exists()) {
            b64List.add('data:image/jpeg;base64,${base64Encode(await f.readAsBytes())}');
          }
        } catch (_) {}
      }
      answersPayload.add({
        'questionId': qId,
        'booleanValue': _answers[qId],
        'textValue': b64List.isNotEmpty ? jsonEncode(b64List) : null,
        'photos': b64List,
      });
    }

    try {
      setState(() {
        _submitting = true;
        _errorMessage = '';
      });
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/audit/visits/${widget.visitId}/submit'),
        headers: {
          'Authorization': 'Bearer ${widget.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'templateId': _templateId,
          'answers': answersPayload,
        }),
      );
      final data = _decodeResponse(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(data['message'] ?? 'Failed to submit audit.');
      }
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });

      await _sendWhatsAppReport();

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dCtx) => AlertDialog(
          title: const Text('Audit Submitted'),
          content: const Text(
            'Your site audit and photos have been saved. Please proceed to Check-Out.',
          ),
          actions: [
            TextButton(
              onPressed: _sendWhatsAppReport,
              child: const Text('Resend WhatsApp'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dCtx).pop();
                Navigator.of(context).pop(true);
              },
              child: const Text('Proceed to Check-Out'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _submitting = false;
        _errorMessage = msg;
      });
      _showMessage(msg, isError: true);
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> question, int index) {
    final qId = question['id']?.toString() ?? '';
    final displayNo = '${index + 1}';
    final text = question['question']?.toString() ?? question['text']?.toString() ?? '';
    final selected = _answers[qId];
    final reqPhoto = _isPhotoRequired(question);
    final paths = _questionPhotos[qId] ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected != null ? const Color(0xFFC7D7FE) : const Color(0xFFE4E7EC),
          width: selected != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Q$displayNo',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1D4ED8),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (reqPhoto || selected == true || paths.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: paths.isNotEmpty
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    paths.isNotEmpty ? '${paths.length} Photo(s) Attached' : 'Attach Photo',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: paths.isNotEmpty
                          ? const Color(0xFF059669)
                          : const Color(0xFFD97706),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          if (reqPhoto || selected == true || paths.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (paths.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < paths.length; i++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(paths[i]),
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            onTap: () => _removePhoto(qId, i),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  InkWell(
                    onTap: () => _capturePhoto(qId, text),
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, size: 20, color: Color(0xFF2563EB)),
                          SizedBox(height: 3),
                          Text(
                            '+ Add',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                onPressed: () => _capturePhoto(qId, text),
                icon: const Icon(Icons.camera_alt, size: 16, color: Color(0xFF2563EB)),
                label: const Text(
                  'Capture Photo',
                  style: TextStyle(color: Color(0xFF2563EB), fontSize: 13),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: (_submitted || _submitting)
                      ? null
                      : () => _selectAnswer(question, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        selected == true ? const Color(0xFF16A34A) : Colors.white,
                    foregroundColor:
                        selected == true ? Colors.white : const Color(0xFF374151),
                    side: BorderSide(
                      color: selected == true
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                  child: const Text('YES', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_submitted || _submitting)
                      ? null
                      : () => _selectAnswer(question, false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        selected == false ? const Color(0xFFDC2626) : Colors.white,
                    foregroundColor:
                        selected == false ? Colors.white : const Color(0xFF374151),
                    side: BorderSide(
                      color: selected == false
                          ? const Color(0xFFDC2626)
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                  child: const Text('NO', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _questions.length;
    final answered = _answers.length;
    final progress = total > 0 ? answered / total : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadChecklist,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Progress: $answered / $total Completed',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${(progress * 100).toInt()}%',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: progress,
                                color: const Color(0xFF2563EB),
                                minHeight: 6,
                              ),
                            ],
                          ),
                        ),
                        if (_errorMessage.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _errorMessage,
                              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
                            ),
                          ),
                        for (int i = 0; i < _questions.length; i++)
                          _buildQuestionCard(_questions[i], i),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    color: Colors.white,
                    child: SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_submitting || _submitted) ? null : _submitAudit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'SUBMIT AUDIT & SEND WHATSAPP REPORT',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}