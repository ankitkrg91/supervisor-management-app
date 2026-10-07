import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';

class AuditScreen extends StatefulWidget {
  final String visitId;
  final String accessToken;
  final String title;
  final String? clientName;
  final String? siteName;
  final String? siteCode;

  const AuditScreen({
    super.key,
    required this.visitId,
    required this.accessToken,
    this.title = 'MSF',
    this.clientName,
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

  @override
  void initState() {
    super.initState();
    _loadChecklist();
  }

  // ==========================================================
  // LOAD CHECKLIST FROM BACKEND
  // ==========================================================

  Future<void> _loadChecklist() async {
    try {
      setState(() {
        _loading = true;
        _errorMessage = '';
      });

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/audit/checklist'),
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
        throw Exception(data['message'] ?? 'Failed to load audit checklist.');
      }

      final checklist = data['data']?['checklist'] ?? data['checklist'];

      if (checklist == null) {
        throw Exception('Audit checklist was not found.');
      }

      final rawQuestions = checklist['questions'];

      final List<Map<String, dynamic>> activeQuestions = [];

      if (rawQuestions is List) {
        for (final item in rawQuestions) {
          if (item is Map<String, dynamic>) {
            if (item['isActive'] != false) {
              activeQuestions.add(Map<String, dynamic>.from(item));
            }
          }
        }
      }

      activeQuestions.sort(
        (a, b) => (int.tryParse('${a['questionNo']}') ?? 0).compareTo(
          int.tryParse('${b['questionNo']}') ?? 0,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _templateId = checklist['id']?.toString();

        _templateName = checklist['name']?.toString() ?? widget.title;

        _questions = activeQuestions;
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

  // ==========================================================
  // RESPONSE DECODER
  // ==========================================================

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {};
    } catch (_) {
      return {};
    }
  }

  // ==========================================================
  // SELECT ANSWER
  // ==========================================================

  void _selectAnswer(String questionId, bool value) {
    if (_submitted || _submitting) {
      return;
    }

    setState(() {
      _answers[questionId] = value;
      _errorMessage = '';
    });
  }

  // ==========================================================
  // VALIDATE ANSWERS
  // ==========================================================

  String? _validateAnswers() {
    for (final question in _questions) {
      final questionId = question['id']?.toString();

      if (questionId == null || questionId.isEmpty) {
        continue;
      }

      final isRequired = question['isRequired'] != false;

      if (isRequired && !_answers.containsKey(questionId)) {
        final questionNo = question['questionNo']?.toString() ?? '';

        return questionNo.isNotEmpty
            ? 'Please answer question $questionNo.'
            : 'Please answer all required questions.';
      }
    }

    return null;
  }

  // ==========================================================
  // SUBMIT AUDIT
  // ==========================================================

  Future<void> _submitAudit() async {
    if (_submitted || _submitting) {
      return;
    }

    if (_templateId == null || _templateId!.isEmpty) {
      setState(() {
        _errorMessage = 'Audit template is not available.';
      });

      return;
    }

    if (widget.visitId.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Visit ID is missing.';
      });

      return;
    }

    final validationError = _validateAnswers();

    if (validationError != null) {
      setState(() {
        _errorMessage = validationError;
      });

      _showMessage(validationError, isError: true);

      return;
    }

    final answersPayload = _questions
        .where(
          (question) =>
              question['id'] != null &&
              _answers.containsKey(question['id'].toString()),
        )
        .map((question) {
          final questionId = question['id'].toString();

          return {
            'questionId': questionId,
            'booleanValue': _answers[questionId],
          };
        })
        .toList();

    try {
      setState(() {
        _submitting = true;
        _errorMessage = '';
      });

      final response = await http.post(
        Uri.parse(
          '${ApiService.baseUrl}/audit/visits/${widget.visitId}/submit',
        ),
        headers: {
          'Authorization': 'Bearer ${widget.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'templateId': _templateId,
          'answers': answersPayload,
        }),
      );

      final data = _decodeResponse(response);

      if (response.statusCode == 401) {
        throw Exception(
          data['message'] ?? 'Session expired. Please login again.',
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['message'] ?? 'Failed to submit audit.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
        _submitted = true;
      });

      await _showSuccessDialog();
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = error.toString().replaceFirst('Exception: ', '');

      setState(() {
        _submitting = false;
        _errorMessage = message;
      });

      _showMessage(message, isError: true);
    }
  }

  // ==========================================================
  // SUCCESS DIALOG
  // ==========================================================

  Future<void> _showSuccessDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Text('Audit Submitted'),
            ],
          ),
          content: const Text('The audit has been submitted successfully.'),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F4FD8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    // Return TRUE to MyTasksScreen.
    // MyTasksScreen will then:
    // 1. Mark task COMPLETED
    // 2. Refresh task list
    // 3. Open task-site CHECK-OUT
    Navigator.of(context).pop(true);
  }

  // ==========================================================
  // SNACKBAR
  // ==========================================================

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? Colors.red.shade700
              : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  // ==========================================================
  // PROGRESS
  // ==========================================================

  int get _answeredCount {
    return _answers.length;
  }

  int get _requiredQuestionCount {
    return _questions
        .where((question) => question['isRequired'] != false)
        .length;
  }

  double get _progressValue {
    if (_requiredQuestionCount == 0) {
      return 0;
    }

    final answeredRequired = _questions.where((question) {
      final id = question['id']?.toString();

      return question['isRequired'] != false &&
          id != null &&
          _answers.containsKey(id);
    }).length;

    return answeredRequired / _requiredQuestionCount;
  }

  // ==========================================================
  // QUESTION CARD
  // ==========================================================

  Widget _buildQuestionCard(Map<String, dynamic> question) {
    final questionId = question['id']?.toString() ?? '';

    final questionNo = question['questionNo']?.toString() ?? '';

    final questionText = question['question']?.toString() ?? '';

    final isRequired = question['isRequired'] != false;

    final selected = _answers[questionId];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '$questionNo. $questionText',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF202124),
                    height: 1.35,
                  ),
                ),
              ),
              if (isRequired)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Required',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // YES
          SizedBox(
            width: double.infinity,
            height: 56,
            child: _buildAnswerButton(
              label: 'YES',
              selected: selected == true,
              activeColor: const Color(0xFF16B63A),
              onTap: () {
                _selectAnswer(questionId, true);
              },
            ),
          ),

          const SizedBox(height: 10),

          // NO
          SizedBox(
            width: double.infinity,
            height: 56,
            child: _buildAnswerButton(
              label: 'NO',
              selected: selected == false,
              activeColor: const Color(0xFFE53935),
              onTap: () {
                _selectAnswer(questionId, false);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ANSWER BUTTON
  // ==========================================================

  Widget _buildAnswerButton({
    required String label,
    required bool selected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final backgroundColor = selected ? activeColor : Colors.white;

    final textColor = selected ? Colors.white : const Color(0xFF3C4043);

    final borderColor = selected ? activeColor : const Color(0xFFB9BEC7);

    return ElevatedButton(
      onPressed: (_submitted || _submitting) ? null : onTap,
      style: ElevatedButton.styleFrom(
        elevation: selected ? 1 : 0,
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
        disabledBackgroundColor: backgroundColor,
        disabledForegroundColor: textColor,
        side: BorderSide(color: borderColor, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (selected) const Icon(Icons.check, size: 21),
          if (selected) const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // HEADER INFO
  // ==========================================================

  Widget _buildHeaderInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E2FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _templateName.isNotEmpty ? _templateName : widget.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A3E94),
            ),
          ),

          if ((widget.siteCode ?? '').isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'Site: ${widget.siteCode}',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF4F5B70),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],

          if ((widget.siteName ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.siteName!,
              style: const TextStyle(fontSize: 14, color: Color(0xFF4F5B70)),
            ),
          ],

          if ((widget.clientName ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Client: ${widget.clientName}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF4F5B70)),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // PROGRESS BAR
  // ==========================================================

  Widget _buildProgressSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Audit Progress',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Text(
                '$_answeredCount/${_questions.length}',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF5F6368),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: _progressValue.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFE4E7EC),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF2F67E8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMPTY STATE
  // ==========================================================

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),

            const SizedBox(height: 16),

            const Text(
              'No audit questions available',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            Text(
              'Please ask the administrator to add audit questions.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),

            const SizedBox(height: 18),

            OutlinedButton.icon(
              onPressed: _loadChecklist,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // ERROR STATE
  // ==========================================================

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 58, color: Colors.red.shade400),

            const SizedBox(height: 16),

            const Text(
              'Unable to load audit',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 8),

            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),

            const SizedBox(height: 18),

            ElevatedButton.icon(
              onPressed: _loadChecklist,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // SUBMIT BUTTON
  // ==========================================================

  Widget _buildSubmitButton() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.10),
              blurRadius: 12,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_submitting || _submitted) ? null : _submitAudit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2F5BEA),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF9AA7C2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 1,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.send, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _submitted ? 'SUBMITTED' : 'SUBMIT',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4B4FE8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty && _questions.isEmpty
          ? _buildErrorState()
          : _questions.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadChecklist,
                    child: ListView(
                      padding: const EdgeInsets.only(top: 0, bottom: 12),
                      children: [
                        _buildHeaderInfo(),
                        _buildProgressSection(),

                        if (_errorMessage.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFFFC9C9),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage,
                                    style: const TextStyle(
                                      color: Color(0xFFB42318),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        ..._questions.map(_buildQuestionCard),
                      ],
                    ),
                  ),
                ),

                _buildSubmitButton(),
              ],
            ),
    );
  }
}
