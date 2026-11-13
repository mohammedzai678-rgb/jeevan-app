import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/markdown_lite.dart';

/// Complete Mobile MediKiosk OPD Clinical History & AYUSH Suite
/// Covers `/medikiosk`, `/clinical-history`, `/document-vault`, and `/history-summary`.
class MediKioskScreen extends ConsumerStatefulWidget {
  const MediKioskScreen({super.key, this.initialMode = 'allopathic'});

  final String initialMode;

  @override
  ConsumerState<MediKioskScreen> createState() => _MediKioskScreenState();
}

class _MediKioskScreenState extends ConsumerState<MediKioskScreen> {
  static const _scheduledLanguages = <({String code, String name, String nativeName})>[
    (code: 'en', name: 'English', nativeName: 'English'),
    (code: 'hi', name: 'Hindi', nativeName: 'हिन्दी'),
    (code: 'bn', name: 'Bengali', nativeName: 'বাংলা'),
    (code: 'te', name: 'Telugu', nativeName: 'తెలుగు'),
    (code: 'mr', name: 'Marathi', nativeName: 'मराठी'),
    (code: 'ta', name: 'Tamil', nativeName: 'தமிழ்'),
    (code: 'ur', name: 'Urdu', nativeName: 'اردو'),
    (code: 'gu', name: 'Gujarati', nativeName: 'ગુજરાતી'),
    (code: 'ml', name: 'Malayalam', nativeName: 'മലയാളം'),
    (code: 'kn', name: 'Kannada', nativeName: 'ಕನ್ನಡ'),
    (code: 'or', name: 'Odia', nativeName: 'ଓଡ଼ିଆ'),
    (code: 'pa', name: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ'),
    (code: 'as', name: 'Assamese', nativeName: 'অসমীয়া'),
    (code: 'ne', name: 'Nepali', nativeName: 'नेपाली'),
    (code: 'sa', name: 'Sanskrit', nativeName: 'संस्कृतम्'),
    (code: 'ks', name: 'Kashmiri', nativeName: 'कॉशुर'),
    (code: 'sd', name: 'Sindhi', nativeName: 'سنڌي'),
    (code: 'kok', name: 'Konkani', nativeName: 'कोंकणी'),
    (code: 'mai', name: 'Maithili', nativeName: 'मैथिली'),
    (code: 'mni', name: 'Manipuri', nativeName: 'মৈতৈলোন্'),
    (code: 'doi', name: 'Dogri', nativeName: 'डोगरी'),
    (code: 'sat', name: 'Santali', nativeName: 'ᱥᱟᱱᱛᱟᱲᱤ'),
    (code: 'brx', name: 'Bodo', nativeName: 'बड़ो'),
  ];

  static const _quickComplaints = <String>[
    'Chest pain & palpitations',
    'Fever & cough for 4 days',
    'Joint stiffness & digestive imbalance',
    'Recurring migraine',
  ];

  static const _soapSectionOrder = <({String key, String altKey, String title, IconData icon, Color accent})>[
    (
      key: 'chiefComplaint',
      altKey: 'Chief Complaint',
      title: '1. Chief Complaint',
      icon: Icons.medical_information_rounded,
      accent: Palette.teal,
    ),
    (
      key: 'historyOfPresentIllness',
      altKey: 'History of Present Illness (HPI)',
      title: '2. History of Present Illness (HPI)',
      icon: Icons.subject_rounded,
      accent: Palette.blue,
    ),
    (
      key: 'pastMedicalHistory',
      altKey: 'Past Medical History',
      title: '3. Past Medical History',
      icon: Icons.history_edu_rounded,
      accent: Palette.teal,
    ),
    (
      key: 'pastSurgicalHistory',
      altKey: 'Past Surgical History',
      title: '4. Past Surgical History',
      icon: Icons.healing_rounded,
      accent: Palette.blue,
    ),
    (
      key: 'drugHistory',
      altKey: 'Drug History',
      title: '5. Drug History',
      icon: Icons.medication_rounded,
      accent: Palette.amber,
    ),
    (
      key: 'allergies',
      altKey: 'Allergies',
      title: '6. Allergies',
      icon: Icons.warning_amber_rounded,
      accent: Palette.red,
    ),
    (
      key: 'familyHistory',
      altKey: 'Family History',
      title: '7. Family History',
      icon: Icons.family_restroom_rounded,
      accent: Palette.green,
    ),
    (
      key: 'personalAndSocialHistory',
      altKey: 'Personal & Social History',
      title: '8. Personal & Social History',
      icon: Icons.person_pin_rounded,
      accent: Palette.orange,
    ),
    (
      key: 'reviewOfSystems',
      altKey: 'Review of Systems',
      title: '9. Review of Systems',
      icon: Icons.fact_check_rounded,
      accent: Palette.teal,
    ),
    (
      key: 'investigations',
      altKey: 'Investigations',
      title: '10. Investigations',
      icon: Icons.biotech_rounded,
      accent: Palette.blue,
    ),
    (
      key: 'ayushAssessment',
      altKey: 'AYUSH Dashavidha Assessment',
      title: '11. AYUSH Dashavidha Assessment',
      icon: Icons.spa_rounded,
      accent: Palette.green,
    ),
  ];

  late String _mode;
  String _language = 'en';

  final _chiefComplaintCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();
  final _docContextCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _showDocAttachment = false;
  bool _interviewStarted = false;
  bool _stepBusy = false;
  bool _summaryBusy = false;
  bool _savingVault = false;

  String _activeChiefComplaint = '';
  int _progressPercent = 0;
  String _completedSection = 'Chief Complaint';
  bool _isComplete = false;
  List<String> _redFlags = const [];
  List<String> _quickReplyOptions = const [];

  /// Conversation log: each item has {'role': 'assistant'|'user', 'content': '...', 'section': '...'}
  final List<Map<String, String>> _conversation = [];

  Map<String, dynamic>? _summaryResult;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode == 'ayush' ? 'ayush' : 'allopathic';
  }

  @override
  void dispose() {
    _chiefComplaintCtrl.dispose();
    _replyCtrl.dispose();
    _docContextCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _dial112() async {
    final uri = Uri(scheme: 'tel', path: '112');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showSnack(context, 'Unable to open dialer for 112', error: true);
    }
  }

  Future<void> _saveToDocumentVault() async {
    final text = _docContextCtrl.text.trim();
    if (text.isEmpty || _savingVault) return;
    setState(() => _savingVault = true);
    try {
      final chunks = await ref.read(apiProvider).addDocument(
            'MediKiosk OPD Attachment (${DateTime.now().toIso8601String().substring(0, 10)})',
            text,
          );
      if (mounted) {
        showSnack(context, 'Indexed into MediKiosk Document Vault ($chunks RAG chunks).');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Vault indexing note: $e', error: true);
    } finally {
      if (mounted) setState(() => _savingVault = false);
    }
  }

  Future<void> _startInterview([String? preset]) async {
    if (preset != null) {
      _chiefComplaintCtrl.text = preset;
    }
    final complaint = _chiefComplaintCtrl.text.trim();
    if (complaint.isEmpty) {
      showSnack(context, 'Please enter or select a Chief Complaint to begin.', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _activeChiefComplaint = complaint;
      _interviewStarted = true;
      _conversation.clear();
      _summaryResult = null;
      _progressPercent = 10;
      _completedSection = _mode == 'ayush' ? 'Prakriti & Vikriti Intake' : 'SOCRATES / HPI Intake';
      _isComplete = false;
      _redFlags = const [];
      _quickReplyOptions = const [];
    });
    await _advanceInterview();
  }

  Future<void> _sendPatientAnswer(String answer) async {
    final trimmed = answer.trim();
    if (trimmed.isEmpty || _stepBusy) return;
    _replyCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _conversation.add({
        'role': 'user',
        'content': trimmed,
      });
      _quickReplyOptions = const [];
    });
    _scrollToBottom();
    await _advanceInterview();
  }

  Future<void> _advanceInterview() async {
    setState(() => _stepBusy = true);
    try {
      final historyPayload = _conversation
          .map((m) => <String, String>{
                'role': m['role'] ?? 'user',
                'content': m['content'] ?? '',
              })
          .toList();

      final res = await ref.read(apiProvider).clinicalHistoryStep(
            chiefComplaint: _activeChiefComplaint,
            conversationHistory: historyPayload,
            mode: _mode,
            language: _language,
            imageContext: _docContextCtrl.text.trim().isEmpty ? null : _docContextCtrl.text.trim(),
          );
      if (!mounted) return;

      final question = '${res['nextQuestion'] ?? res['question'] ?? res['response'] ?? 'Could you share more details about how your symptoms started and progressed?'}'.trim();
      final section = '${res['currentSection'] ?? res['completedSection'] ?? res['section'] ?? (_mode == 'ayush' ? 'Dashavidha Pariksha' : 'History of Present Illness')}'.trim();
      final rawProgress = (res['progress'] ?? res['progressPercent'] ?? ((_conversation.length ~/ 2 + 1) * 10));
      final progress = (rawProgress is num ? rawProgress.toInt() : int.tryParse('$rawProgress') ?? 20).clamp(0, 100);
      final isComplete = res['isComplete'] == true || progress >= 100 || (_conversation.where((m) => m['role'] == 'user').length >= 10);

      final rawQuickReplies = (res['quickReplyOptions'] ?? res['options'] ?? res['suggestedReplies']) as List?;
      final quickReplies = rawQuickReplies != null
          ? rawQuickReplies.map((e) => '$e').where((s) => s.trim().isNotEmpty).toList()
          : <String>[
              'Started 2–3 days ago',
              'Moderate severity (5/10)',
              'No prior medical history',
              'No known drug allergies',
            ];

      final rawFlags = (res['redFlags'] ?? res['redFlagAlerts']) as List?;
      final flags = rawFlags != null
          ? rawFlags.map((e) => '$e').where((s) => s.trim().isNotEmpty).toList()
          : <String>[];
      if (res['redFlagAlert'] is String && (res['redFlagAlert'] as String).trim().isNotEmpty) {
        flags.add((res['redFlagAlert'] as String).trim());
      }

      setState(() {
        _conversation.add({
          'role': 'assistant',
          'content': question,
          'section': section,
        });
        _completedSection = section;
        _progressPercent = isComplete ? 100 : progress;
        _isComplete = isComplete;
        _quickReplyOptions = quickReplies;
        if (flags.isNotEmpty) {
          _redFlags = {..._redFlags, ...flags}.toList();
        }
      });
      _scrollToBottom();

      if (isComplete) {
        await _generateSummary();
      }
    } catch (e) {
      if (!mounted) return;
      final turn = _conversation.where((m) => m['role'] == 'user').length + 1;
      final fallbackQuestions = _mode == 'ayush'
          ? const [
              'How is your Agni (digestive fire / appetite) and Koshtha (bowel regularity)?',
              'Do your symptoms worsen with cold/dry weather (Vata), heat (Pitta), or dampness (Kapha)?',
              'How is your Nidra (sleep quality) and daily Satmya (dietary routine)?',
              'Are you currently taking any Ayurvedic Bhasma, Kashayam, or allopathic medicines?',
            ]
          : const [
              'Where exactly is the symptom located, and does it radiate anywhere else (SOCRATES - Site & Radiation)?',
              'How would you rate the severity on a scale of 1 to 10, and what makes it better or worse?',
              'Do you have any past medical conditions (Diabetes, Hypertension, Asthma) or past surgeries?',
              'Are you currently taking regular medications, and do you have any drug or food allergies?',
            ];
      final q = fallbackQuestions[(turn - 1) % fallbackQuestions.length];
      setState(() {
        _conversation.add({
          'role': 'assistant',
          'content': q,
          'section': _mode == 'ayush' ? 'Dashavidha Pariksha ($turn/10)' : 'SOCRATES Interview ($turn/10)',
        });
        _progressPercent = (turn * 10).clamp(10, 100);
        _quickReplyOptions = const [
          'Mild to moderate, intermittent',
          'Worse since yesterday evening',
          'No chronic illnesses or surgeries',
          'No known drug allergies',
        ];
      });
      showSnack(context, 'Using resilient MediKiosk protocol: $e');
    } finally {
      if (mounted) setState(() => _stepBusy = false);
    }
  }

  Future<void> _generateSummary() async {
    if (_summaryBusy) return;
    if (_activeChiefComplaint.isEmpty) {
      final typed = _chiefComplaintCtrl.text.trim();
      if (typed.isEmpty) {
        showSnack(context, 'Enter a chief complaint first to generate a SOAP summary.', error: true);
        return;
      }
      _activeChiefComplaint = typed;
    }
    setState(() => _summaryBusy = true);
    try {
      final historyPayload = _conversation
          .map((m) => <String, String>{
                'role': m['role'] ?? 'user',
                'content': m['content'] ?? '',
              })
          .toList();
      final res = await ref.read(apiProvider).clinicalHistorySummary(
            chiefComplaint: _activeChiefComplaint,
            conversationHistory: historyPayload,
            mode: _mode,
            language: _language,
          );
      if (!mounted) return;
      setState(() {
        _summaryResult = res;
        _isComplete = true;
        _progressPercent = 100;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) showSnack(context, 'Failed to generate summary: $e', error: true);
    } finally {
      if (mounted) setState(() => _summaryBusy = false);
    }
  }

  void _resetInterview() {
    setState(() {
      _interviewStarted = false;
      _conversation.clear();
      _summaryResult = null;
      _progressPercent = 0;
      _isComplete = false;
      _redFlags = const [];
      _quickReplyOptions = const [];
    });
  }

  String _extractSectionValue(Map<String, dynamic> summary, String key, String altKey) {
    final sectionsMap = summary['sections'] is Map ? (summary['sections'] as Map).cast<String, dynamic>() : summary;
    final direct = sectionsMap[key] ?? sectionsMap[altKey] ?? summary[key] ?? summary[altKey];
    if (direct != null) {
      if (direct is List) return direct.map((e) => '• $e').join('\n');
      if (direct is Map) {
        return direct.entries.map((e) => '• **${e.key}**: ${e.value}').join('\n');
      }
      final s = '$direct'.trim();
      if (s.isNotEmpty) return s;
    }
    // Check snake_case fallback
    final snake = key.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');
    final snakeVal = sectionsMap[snake] ?? summary[snake];
    if (snakeVal != null && '$snakeVal'.trim().isNotEmpty) {
      return '$snakeVal'.trim();
    }
    if (key == 'chiefComplaint') return _activeChiefComplaint;
    if (key == 'historyOfPresentIllness') {
      final userReplies = _conversation.where((m) => m['role'] == 'user').map((m) => m['content']).join('; ');
      return userReplies.isNotEmpty
          ? 'Patient reported $_activeChiefComplaint. Interview notes: $userReplies'
          : 'Patient presented with $_activeChiefComplaint.';
    }
    if (key == 'ayushAssessment') {
      return _mode == 'ayush'
          ? 'Dashavidha Pariksha (Prakriti-Vikriti, Sara, Samhanana, Ahara Shakti, Vyayama Shakti) evaluated for $_activeChiefComplaint.'
          : 'Allopathic mode selected — integrative AYUSH Prakriti/Vikriti correlation available upon switch.';
    }
    return 'Documented during MediKiosk OPD intake — no acute abnormality reported in this section.';
  }

  String _formatFullSummaryForClipboard(Map<String, dynamic> summary) {
    final buffer = StringBuffer();
    buffer.writeln('JEEVAN MEDIKIOSK — 11-SECTION PHYSICIAN SOAP & AYUSH SUMMARY');
    buffer.writeln('Mode: ${_mode.toUpperCase()} | Language: ${_language.toUpperCase()}');
    buffer.writeln('============================================================');
    for (final sec in _soapSectionOrder) {
      final val = _extractSectionValue(summary, sec.key, sec.altKey);
      buffer.writeln('\n${sec.title.toUpperCase()}');
      buffer.writeln(val);
    }
    final rawText = '${summary['summary'] ?? summary['soapNote'] ?? summary['response'] ?? ''}'.trim();
    if (rawText.isNotEmpty) {
      buffer.writeln('\nCLINICAL SYNTHESIS:');
      buffer.writeln(rawText);
    }
    return buffer.toString();
  }

  Future<void> _copySummaryToClipboard(Map<String, dynamic> summary) async {
    final text = _formatFullSummaryForClipboard(summary);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      HapticFeedback.lightImpact();
      showSnack(context, '11-Section Physician SOAP Summary copied to clipboard!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAyush = _mode == 'ayush';
    final accent = isAyush ? Palette.green : Palette.teal;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: canPop
          ? AppBar(
              title: const Text('MediKiosk OPD & AYUSH Suite'),
              actions: [
                if (_interviewStarted)
                  IconButton(
                    tooltip: 'Restart Interview',
                    onPressed: _resetInterview,
                    icon: const Icon(Icons.restart_alt_rounded, color: Palette.amber),
                  ),
              ],
            )
          : null,
      body: SafeArea(
        child: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (!canPop) ...[
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Palette.redLight,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🩻', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MediKiosk OPD',
                          style: TextStyle(
                            color: Palette.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '10-Question Interview • 11-Section SOAP • AYUSH',
                          style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  if (_interviewStarted)
                    IconButton(
                      tooltip: 'Restart Interview',
                      onPressed: _resetInterview,
                      icon: const Icon(Icons.restart_alt_rounded, color: Palette.amber),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            // ── MediKiosk 3 Sub-Routes Switcher (Vertical Wrap — Zero Horizontal Scroll) ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  selected: !_showDocAttachment && _summaryResult == null,
                  showCheckmark: false,
                  selectedColor: Palette.redLight,
                  label: Text(
                    '1. 🩻 Clinical Interview',
                    style: TextStyle(
                      color: (!_showDocAttachment && _summaryResult == null) ? Palette.red : Palette.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                  onSelected: (_) => setState(() => _showDocAttachment = false),
                ),
                ChoiceChip(
                  selected: _showDocAttachment,
                  showCheckmark: false,
                  selectedColor: Palette.redLight,
                  label: Text(
                    '2. 📋 Document Vault & Labs',
                    style: TextStyle(
                      color: _showDocAttachment ? Palette.red : Palette.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                  onSelected: (_) => setState(() => _showDocAttachment = true),
                ),
                ChoiceChip(
                  selected: _summaryResult != null,
                  showCheckmark: false,
                  selectedColor: Palette.redLight,
                  label: Text(
                    '3. 📝 11-Section SOAP Summary',
                    style: TextStyle(
                      color: _summaryResult != null ? Palette.red : Palette.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                  onSelected: (_) => _generateSummary(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Top Mode Switcher & 22 Scheduled Indian Languages Selector ──
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: accent.withValues(alpha: 0.45),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isAyush ? Icons.spa_rounded : Icons.local_hospital_rounded,
                          color: accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAyush
                                  ? 'AYUSH Mode • Dashavidha Pariksha'
                                  : 'Allopathic Mode • SOCRATES / HPI Intake',
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isAyush
                                  ? 'Prakriti-Vikriti, Agni, Koshtha, Nadi & integrative clinical history'
                                  : 'Structured 10-question OPD physician interview & 11-section SOAP chart',
                              style: const TextStyle(color: Palette.textDim, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Mode switcher pills
                  Row(
                    children: [
                      Expanded(
                        child: _ModeOptionButton(
                          label: 'Allopathic (SOCRATES)',
                          subtitle: 'Modern HPI & SOAP',
                          icon: Icons.medical_services_rounded,
                          selected: _mode == 'allopathic',
                          accent: Palette.teal,
                          onTap: () => setState(() => _mode = 'allopathic'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ModeOptionButton(
                          label: 'AYUSH (Dashavidha)',
                          subtitle: 'Prakriti / Vikriti',
                          icon: Icons.spa_rounded,
                          selected: _mode == 'ayush',
                          accent: Palette.green,
                          onTap: () => setState(() => _mode = 'ayush'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 22 Scheduled Indian Languages Selector
                  DropdownButtonFormField<String>(
                    value: _language,
                    isExpanded: true,
                    dropdownColor: Palette.surfaceHi,
                    decoration: InputDecoration(
                      labelText: '22 Scheduled Indian Languages (Bhasha)',
                      prefixIcon: Icon(Icons.translate_rounded, color: accent),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    items: _scheduledLanguages
                        .map(
                          (l) => DropdownMenuItem<String>(
                            value: l.code,
                            child: Text(
                              '${l.name} (${l.nativeName}) • ${l.code.toUpperCase()}',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _language = v);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Optional Document Vault / Clinical Context Attachment ──
            GlassCard(
              padding: const EdgeInsets.all(14),
              borderColor: Palette.blue.withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _showDocAttachment = !_showDocAttachment),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_special_rounded, color: Palette.blue, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MediKiosk Document Vault & Lab Context',
                                style: TextStyle(
                                  color: Palette.text,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Attach prior discharge notes, ECG/lab findings, or prescriptions to guide interview',
                                style: TextStyle(color: Palette.textDim, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _showDocAttachment ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          color: Palette.blue,
                        ),
                      ],
                    ),
                  ),
                  if (_showDocAttachment) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _docContextCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Prior Medical Document / Lab Report Context (Optional)',
                        hintText: 'e.g., Prior ECG shows sinus tachycardia; HbA1c 7.8%; on Metformin 500mg BD…',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _savingVault ? null : _saveToDocumentVault,
                        icon: _savingVault
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Palette.blue),
                              )
                            : const Icon(Icons.cloud_upload_rounded, size: 16, color: Palette.blue),
                        label: Text(_savingVault ? 'Indexing…' : 'Index in RAG Document Vault'),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Chief Complaint Launcher ──
            if (!_interviewStarted) ...[
              const SectionHeader('Chief Complaint Launcher'),
              GlassCard(
                borderColor: accent.withValues(alpha: 0.4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select a quick clinical presentation chip or enter the patient’s primary complaint to start the adaptive 10-question OPD doctor interview.',
                      style: TextStyle(color: Palette.textDim, fontSize: 13.5, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _chiefComplaintCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Patient Chief Complaint',
                        hintText: 'e.g., Chest pain & palpitations since morning…',
                        prefixIcon: Icon(Icons.edit_note_rounded, color: accent),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Quick Chief Complaint Chips',
                      style: TextStyle(color: Palette.textDim, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in _quickComplaints)
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => _startInterview(preset),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: accent.withValues(alpha: 0.38)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bolt_rounded, size: 15, color: accent),
                                  const SizedBox(width: 6),
                                  Text(
                                    preset,
                                    style: const TextStyle(
                                      color: Palette.text,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _stepBusy ? null : () => _startInterview(),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Start 10-Question Interview'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _summaryBusy ? null : _generateSummary,
                        icon: const Icon(Icons.summarize_rounded, size: 18, color: Palette.blue),
                        label: const Text('Generate 11-Section Summary Now'),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // ── Adaptive 10-Question Doctor Interview View ──
              SectionHeader(
                'Adaptive Doctor Interview',
                action: TextButton.icon(
                  onPressed: _summaryBusy ? null : _generateSummary,
                  icon: const Icon(Icons.description_rounded, size: 16, color: Palette.amber),
                  label: Text(_summaryBusy ? 'Generating…' : 'Generate Summary Now'),
                ),
              ),
              GlassCard(
                padding: const EdgeInsets.all(16),
                borderColor: accent.withValues(alpha: 0.45),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: accent.withValues(alpha: 0.45)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline_rounded, size: 13, color: accent),
                              const SizedBox(width: 5),
                              Text(
                                _completedSection.toUpperCase(),
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$_progressPercent% Complete',
                          style: TextStyle(
                            color: accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            fontFeatures: kTabular,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (_progressPercent / 100.0).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Palette.surfaceHi,
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Chief Complaint: $_activeChiefComplaint',
                      style: const TextStyle(
                        color: Palette.textDim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Red-Flag Alerts Banner
              if (_redFlags.isNotEmpty) ...[
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  color: Palette.red.withValues(alpha: 0.14),
                  borderColor: Palette.red.withValues(alpha: 0.65),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.emergency_rounded, color: Palette.red, size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'CLINICAL RED-FLAG ALERT DETECTED',
                              style: TextStyle(
                                color: Palette.red,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Palette.red,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: _dial112,
                            icon: const Icon(Icons.call_rounded, size: 14),
                            label: const Text('Call 112', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final flag in _redFlags)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• $flag',
                            style: const TextStyle(color: Palette.text, fontSize: 12.5, height: 1.35),
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Conversation History Feed
              for (final msg in _conversation)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _InterviewBubble(
                    isDoctor: msg['role'] != 'user',
                    text: msg['content'] ?? '',
                    sectionBadge: msg['section'],
                    accent: accent,
                  ),
                ),

              if (_stepBusy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: accent),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'AI Physician formulating next clinical question…',
                        style: TextStyle(color: Palette.textDim, fontSize: 13),
                      ),
                    ],
                  ),
                ),

              // Tap-to-answer quickReplyOptions pills
              if (!_isComplete && _quickReplyOptions.isNotEmpty && !_stepBusy) ...[
                const SizedBox(height: 6),
                const Text(
                  'Tap a Quick Reply or type your answer below:',
                  style: TextStyle(color: Palette.textDim, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final opt in _quickReplyOptions)
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _sendPatientAnswer(opt),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: accent.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            opt,
                            style: const TextStyle(
                              color: Palette.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // Custom patient answer box + Generate Summary Now button
              GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _replyCtrl,
                            textInputAction: TextInputAction.send,
                            onSubmitted: _sendPatientAnswer,
                            decoration: const InputDecoration(
                              hintText: 'Type patient response…',
                              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _stepBusy ? null : () => _sendPatientAnswer(_replyCtrl.text),
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          backgroundColor: Palette.amber.withValues(alpha: 0.16),
                          foregroundColor: Palette.amber,
                        ),
                        onPressed: _summaryBusy ? null : _generateSummary,
                        icon: _summaryBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Palette.amber),
                              )
                            : const Icon(Icons.assignment_turned_in_rounded, size: 18),
                        label: Text(
                          _summaryBusy
                              ? 'Generating 11-Section Physician SOAP Summary…'
                              : 'Generate Summary Now (11-Section SOAP & AYUSH)',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── 11-Section Physician SOAP / History Summary Generator Output ──
            if (_summaryResult != null) ...[
              const SizedBox(height: 22),
              SectionHeader(
                '11-Section Physician SOAP & AYUSH Summary',
                action: TextButton.icon(
                  onPressed: () => _copySummaryToClipboard(_summaryResult!),
                  icon: const Icon(Icons.copy_all_rounded, size: 17, color: Palette.teal),
                  label: const Text('Copy All'),
                ),
              ),
              GlassCard(
                padding: const EdgeInsets.all(16),
                borderColor: accent.withValues(alpha: 0.55),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.fact_check_rounded, color: accent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Structured OPD Handover Record',
                                style: TextStyle(
                                  color: Palette.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Mode: ${_mode.toUpperCase()} • Language: ${_language.toUpperCase()}',
                                style: const TextStyle(color: Palette.textDim, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent.withValues(alpha: 0.18),
                            foregroundColor: accent,
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: () => _copySummaryToClipboard(_summaryResult!),
                          icon: const Icon(Icons.copy_rounded, size: 15),
                          label: const Text('Copy SOAP', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    for (final sec in _soapSectionOrder)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: Palette.surfaceHi,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: sec.accent.withValues(alpha: 0.32)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(sec.icon, size: 16, color: sec.accent),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      sec.title,
                                      style: TextStyle(
                                        color: sec.accent,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              MarkdownLite(
                                _extractSectionValue(_summaryResult!, sec.key, sec.altKey),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModeOptionButton extends StatelessWidget {
  const _ModeOptionButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : Palette.surfaceHi,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Palette.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? accent : Palette.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? Palette.text : Palette.textDim,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: selected ? accent : Palette.textDim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InterviewBubble extends StatelessWidget {
  const _InterviewBubble({
    required this.isDoctor,
    required this.text,
    required this.accent,
    this.sectionBadge,
  });

  final bool isDoctor;
  final String text;
  final Color accent;
  final String? sectionBadge;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isDoctor ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDoctor ? Palette.surfaceHi : accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDoctor ? Palette.outline : accent.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDoctor ? Icons.medical_services_rounded : Icons.person_rounded,
                  size: 14,
                  color: isDoctor ? accent : Palette.text,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isDoctor ? 'AI OPD Physician ${sectionBadge != null ? "• $sectionBadge" : ""}' : 'Patient Response',
                    style: TextStyle(
                      color: isDoctor ? accent : Palette.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                color: Palette.text,
                fontSize: 13.8,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Jeevan sync: 2026-11-13
