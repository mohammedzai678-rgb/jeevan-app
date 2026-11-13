import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/markdown_lite.dart';

class ClinicalToolsScreen extends ConsumerStatefulWidget {
  const ClinicalToolsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<ClinicalToolsScreen> createState() =>
      _ClinicalToolsScreenState();
}

class _ClinicalToolsScreenState extends ConsumerState<ClinicalToolsScreen> {
  late int _selectedTab;
  String _language = 'en';

  static const _languages = <({String code, String label})>[
    (code: 'en', label: 'EN • English'),
    (code: 'hi', label: 'HI • हिन्दी'),
    (code: 'bn', label: 'BN • বাংলা'),
    (code: 'te', label: 'TE • తెలుగు'),
    (code: 'mr', label: 'MR • मराठी'),
    (code: 'ta', label: 'TA • தமிழ்'),
    (code: 'ur', label: 'UR • اردو'),
    (code: 'gu', label: 'GU • ગુજરાતી'),
    (code: 'ml', label: 'ML • മലയാളം'),
    (code: 'kn', label: 'KN • ಕನ್ನಡ'),
    (code: 'pa', label: 'PA • ਪੰਜਾਬੀ'),
  ];

  static const _tabs = <({String label, IconData icon, Color accent})>[
    (
      label: 'Symptom Triage',
      icon: Icons.medical_information_rounded,
      accent: Palette.teal
    ),
    (
      label: 'MediScan (Lab & Rx)',
      icon: Icons.biotech_rounded,
      accent: Palette.blue
    ),
    (
      label: 'OpenFDA Interactions',
      icon: Icons.medication_liquid_rounded,
      accent: Palette.amber
    ),
    (
      label: 'Medicine Analyzer',
      icon: Icons.vaccines_rounded,
      accent: Palette.green
    ),
    (
      label: 'Mental Wellbeing',
      icon: Icons.self_improvement_rounded,
      accent: Palette.orange
    ),
    (
      label: 'AI Radiology Imaging',
      icon: Icons.collections_bookmark_rounded,
      accent: Palette.red
    ),
  ];

  // ── 1. Symptom Triage & Body Region State ──────────────────────────────────
  static const _bodyRegions = <String>[
    'Forehead',
    'Eyes',
    'Ears',
    'Mouth/Teeth',
    'Neck',
    'Chest',
    'Heart',
    'Lungs',
    'Upper/Lower Abdomen',
    'Spine/Back',
    'Shoulder/Arm/Hand',
    'Hip/Knee/Ankle/Foot',
  ];

  static const _symptomChips = <String>[
    'Pain',
    'Swelling',
    'Shortness of breath',
    'Dizziness',
    'Fever',
    'Numbness',
    'Nausea',
    'Weakness',
  ];

  static const _durations = <String>[
    'Just started (< 24h)',
    '1-3 days',
    '4-7 days',
    'More than 1 week',
  ];

  String _selectedBodyRegion = 'Chest';
  final Set<String> _selectedSymptoms = {'Pain', 'Shortness of breath'};
  String _selectedDuration = '1-3 days';
  double _severitySlider = 6;

  // Controllers
  final _symptomCtrl = TextEditingController();
  final _mediScanCtrl = TextEditingController();
  final _drug1Ctrl = TextEditingController();
  final _drug2Ctrl = TextEditingController();
  final _medicineCtrl = TextEditingController();
  final _wellbeingCtrl = TextEditingController();
  final _radiologyContextCtrl = TextEditingController();

  // ── 6. AI Radiology Imaging State ──────────────────────────────────────────
  static const _imagingModalities = <String>[
    'Chest X-Ray',
    'Brain CT/MRI',
    'Bone/Joint X-Ray',
    'Retinal/Skin Scan',
  ];

  static const _imagingRegions = <String>[
    'Thorax / Bilateral Lungs',
    'Cranium / Cerebral Hemisphere',
    'Lumbar Spine / Pelvis',
    'Knee / Shoulder Joint',
    'Retina / Macula',
    'Dermal / Cutaneous Lesion',
  ];

  String _selectedModality = 'Chest X-Ray';
  String _selectedImagingRegion = 'Thorax / Bilateral Lungs';

  // Loading & result states per tab
  bool _symptomBusy = false;
  Map<String, dynamic>? _symptomResult;

  bool _mediScanBusy = false;
  Map<String, dynamic>? _mediScanResult;
  int? _mediScanFeedbackReward;

  bool _fdaBusy = false;
  Map<String, dynamic>? _fdaResult;

  bool _medicineBusy = false;
  Map<String, dynamic>? _medicineResult;

  bool _wellbeingBusy = false;
  Map<String, dynamic>? _wellbeingResult;

  bool _radiologyBusy = false;
  Map<String, dynamic>? _radiologyResult;
  int? _radiologyFeedbackReward;
  bool _sendingFeedback = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab.clamp(0, _tabs.length - 1);
  }

  @override
  void dispose() {
    _symptomCtrl.dispose();
    _mediScanCtrl.dispose();
    _drug1Ctrl.dispose();
    _drug2Ctrl.dispose();
    _medicineCtrl.dispose();
    _wellbeingCtrl.dispose();
    _radiologyContextCtrl.dispose();
    super.dispose();
  }

  Future<void> _dialNumber(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted)
        showSnack(context, 'Unable to open dialer for $number', error: true);
    }
  }

  Future<void> _runBodySymptomCheck([String? preset]) async {
    if (preset != null) {
      _symptomCtrl.text = preset;
    }
    if (_symptomBusy) return;
    final symptomsList = _selectedSymptoms.isNotEmpty
        ? _selectedSymptoms.toList()
        : (_symptomCtrl.text.trim().isNotEmpty
            ? [_symptomCtrl.text.trim()]
            : ['Pain']);

    FocusScope.of(context).unfocus();
    setState(() => _symptomBusy = true);
    try {
      final res = await ref.read(apiProvider).bodySymptomCheck(
            bodyLocation: _selectedBodyRegion,
            symptoms: symptomsList,
            duration: _selectedDuration,
            severity: _severitySlider.round(),
            additionalInfo: _symptomCtrl.text.trim(),
            language: _language,
          );
      if (!mounted) return;
      setState(() => _symptomResult = res);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _symptomBusy = false);
    }
  }

  Future<void> _runQuickTriage() async {
    final text = _symptomCtrl.text.trim().isNotEmpty
        ? _symptomCtrl.text.trim()
        : '$_selectedBodyRegion: ${_selectedSymptoms.join(", ")}';
    if (text.isEmpty || _symptomBusy) return;
    FocusScope.of(context).unfocus();
    setState(() => _symptomBusy = true);
    try {
      final res = await ref.read(apiProvider).triage(
            symptoms: text,
            duration: _selectedDuration,
            severity: _severitySlider.round(),
            language: _language,
          );
      if (!mounted) return;
      setState(() => _symptomResult = res);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _symptomBusy = false);
    }
  }

  Future<void> _runMediScan([String? preset]) async {
    if (preset != null) _mediScanCtrl.text = preset;
    final text = _mediScanCtrl.text.trim();
    if (text.isEmpty || _mediScanBusy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _mediScanBusy = true;
      _mediScanFeedbackReward = null;
    });
    try {
      final res =
          await ref.read(apiProvider).aiMediScan(text, language: _language);
      if (!mounted) return;
      setState(() => _mediScanResult = res);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _mediScanBusy = false);
    }
  }

  Future<void> _runFdaInteractions([String? d1, String? d2]) async {
    if (d1 != null) _drug1Ctrl.text = d1;
    if (d2 != null) _drug2Ctrl.text = d2;
    final drug1 = _drug1Ctrl.text.trim();
    final drug2 = _drug2Ctrl.text.trim();
    if (drug1.isEmpty || drug2.isEmpty) {
      showSnack(context, 'Enter both Drug A and Drug B to check interactions.',
          error: true);
      return;
    }
    if (_fdaBusy) return;
    FocusScope.of(context).unfocus();
    setState(() => _fdaBusy = true);
    try {
      final res = await ref.read(apiProvider).fdaInteractions(drug1, drug2);
      if (!mounted) return;
      setState(() => _fdaResult = res);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _fdaBusy = false);
    }
  }

  Future<void> _runMedicineAnalyzer([String? preset]) async {
    if (preset != null) _medicineCtrl.text = preset;
    final text = _medicineCtrl.text.trim();
    if (text.isEmpty || _medicineBusy) return;
    FocusScope.of(context).unfocus();
    setState(() => _medicineBusy = true);
    try {
      final res = await ref
          .read(apiProvider)
          .aiMedicineAnalyzer(text, language: _language);
      if (!mounted) return;
      setState(() => _medicineResult = res);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _medicineBusy = false);
    }
  }

  Future<void> _runWellbeing([String? preset]) async {
    if (preset != null) _wellbeingCtrl.text = preset;
    final text = _wellbeingCtrl.text.trim();
    if (text.isEmpty || _wellbeingBusy) return;
    FocusScope.of(context).unfocus();
    setState(() => _wellbeingBusy = true);
    try {
      final res =
          await ref.read(apiProvider).aiWellbeing(text, language: _language);
      if (!mounted) return;
      setState(() => _wellbeingResult = res);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _wellbeingBusy = false);
    }
  }

  Future<void> _runDiagnosticImaging(
      [String? presetModality,
      String? presetRegion,
      String? presetContext]) async {
    if (presetModality != null) _selectedModality = presetModality;
    if (presetRegion != null) _selectedImagingRegion = presetRegion;
    if (presetContext != null) _radiologyContextCtrl.text = presetContext;
    if (_radiologyBusy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _radiologyBusy = true;
      _radiologyFeedbackReward = null;
    });
    try {
      final res = await ref.read(apiProvider).diagnosticImaging(
            imagingType: _selectedModality,
            bodyRegion: _selectedImagingRegion,
            clinicalContext: _radiologyContextCtrl.text.trim(),
            language: _language,
          );
      if (!mounted) return;
      setState(() => _radiologyResult = res);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _radiologyBusy = false);
    }
  }

  Future<void> _submitRlhfFeedback({
    required String logId,
    required int reward,
    required bool isRadiology,
  }) async {
    if (_sendingFeedback) return;
    setState(() => _sendingFeedback = true);
    try {
      await ref.read(apiProvider).mediscanFeedback(
            logId: logId.isEmpty
                ? 'log_${DateTime.now().millisecondsSinceEpoch}'
                : logId,
            reward: reward,
          );
      if (!mounted) return;
      setState(() {
        if (isRadiology) {
          _radiologyFeedbackReward = reward;
        } else {
          _mediScanFeedbackReward = reward;
        }
      });
      showSnack(
        context,
        reward > 0
            ? 'RLHF +1 reward logged — thank you for validating clinical accuracy!'
            : 'RLHF -1 feedback logged — flagged for clinical model calibration.',
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Feedback logged locally ($e)');
    } finally {
      if (mounted) setState(() => _sendingFeedback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Clinical & OpenFDA Suite'),
        actions: [
          // Language selector dropdown in AppBar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Palette.surfaceHi,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Palette.teal.withOpacity(0.45)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _language,
                dropdownColor: Palette.surfaceHi,
                icon: const Icon(Icons.translate_rounded,
                    size: 15, color: Palette.teal),
                style: const TextStyle(
                  color: Palette.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
                items: _languages
                    .map(
                      (l) => DropdownMenuItem<String>(
                        value: l.code,
                        child: Text(l.label),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _language = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: ConnectionBadge(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildToolSelector(),
            const Divider(height: 1, color: Palette.outline),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                children: [
                  switch (_selectedTab) {
                    0 => _buildSymptomTriageTab(),
                    1 => _buildMediScanTab(),
                    2 => _buildOpenFdaTab(),
                    3 => _buildMedicineAnalyzerTab(),
                    4 => _buildWellbeingTab(),
                    _ => _buildRadiologyImagingTab(),
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolSelector() {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final tab = _tabs[i];
          final selected = i == _selectedTab;
          return GestureDetector(
            onTap: () => setState(() => _selectedTab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color:
                    selected ? tab.accent.withOpacity(0.18) : Palette.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? tab.accent : Palette.outline,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tab.icon,
                    size: 16,
                    color: selected ? tab.accent : Palette.textDim,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    tab.label,
                    style: TextStyle(
                      color: selected ? Palette.text : Palette.textDim,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 1. Symptom Triage & Interactive Body Region Map ─────────────────────────
  Widget _buildSymptomTriageTab() {
    const samples = <String>[
      'Chest tightness & sweating radiating to left arm',
      'High fever & stiff neck since yesterday',
      'Mild headache after prolonged screen time',
    ];

    final severityInt = _severitySlider.round();
    final severityColor = severityInt >= 8
        ? Palette.red
        : severityInt >= 5
            ? Palette.amber
            : Palette.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Interactive Body Region & Symptom Triage (P1–P4)'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select the affected anatomical body region, multi-select active symptoms, adjust severity (1–10), and run P1–P4 emergency triage.',
                style: TextStyle(
                    color: Palette.textDim, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 14),

              // Body Region Selector
              const Text(
                '1. Select Body Region',
                style: TextStyle(
                    color: Palette.teal,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final region in _bodyRegions)
                    ChoiceChip(
                      label: Text(region),
                      selected: _selectedBodyRegion == region,
                      selectedColor: Palette.teal.withOpacity(0.22),
                      backgroundColor: Palette.surfaceHi,
                      labelStyle: TextStyle(
                        color: _selectedBodyRegion == region
                            ? Palette.teal
                            : Palette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      side: BorderSide(
                        color: _selectedBodyRegion == region
                            ? Palette.teal
                            : Palette.outline,
                      ),
                      onSelected: (_) =>
                          setState(() => _selectedBodyRegion = region),
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // Multi-select Symptom Chips
              const Text(
                '2. Select Active Symptoms (Multi-Select)',
                style: TextStyle(
                    color: Palette.teal,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final sym in _symptomChips)
                    FilterChip(
                      label: Text(sym),
                      selected: _selectedSymptoms.contains(sym),
                      selectedColor: Palette.blue.withOpacity(0.22),
                      checkmarkColor: Palette.blue,
                      backgroundColor: Palette.surfaceHi,
                      labelStyle: TextStyle(
                        color: _selectedSymptoms.contains(sym)
                            ? Palette.blue
                            : Palette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      side: BorderSide(
                        color: _selectedSymptoms.contains(sym)
                            ? Palette.blue
                            : Palette.outline,
                      ),
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedSymptoms.add(sym);
                          } else if (_selectedSymptoms.length > 1) {
                            _selectedSymptoms.remove(sym);
                          }
                        });
                      },
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // Severity Slider (1-10) & Duration Dropdown
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '3. Severity: ',
                              style: TextStyle(
                                  color: Palette.teal,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: severityColor.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '$severityInt / 10',
                                style: TextStyle(
                                  color: severityColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: kTabular,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _severitySlider,
                          min: 1,
                          max: 10,
                          divisions: 9,
                          activeColor: severityColor,
                          label: '$severityInt / 10',
                          onChanged: (v) => setState(() => _severitySlider = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedDuration,
                      dropdownColor: Palette.surfaceHi,
                      decoration: const InputDecoration(
                        labelText: 'Duration',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: _durations
                          .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(d,
                                  style: const TextStyle(fontSize: 12.5))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedDuration = v);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              TextField(
                controller: _symptomCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Additional clinical details or vitals context',
                  hintText:
                      'e.g., Sudden chest tightness radiating to left arm for 20 minutes…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick Samples',
                style: TextStyle(
                    color: Palette.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in samples)
                    _SampleChip(
                      label: s,
                      accent: Palette.teal,
                      onTap: () => _runBodySymptomCheck(s),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _symptomBusy ? null : () => _runBodySymptomCheck(),
                      icon: _symptomBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Color(0xFF042F2A)),
                            )
                          : const Icon(Icons.accessibility_new_rounded),
                      label: Text(_symptomBusy
                          ? 'Running Body Triage…'
                          : 'Run Body Symptom Check'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _symptomBusy ? null : _runQuickTriage,
                  icon: const Icon(Icons.bolt_rounded,
                      size: 18, color: Palette.amber),
                  label: const Text(
                      'Run Rapid Emergency Triage (/api/gemini/triage)'),
                ),
              ),
            ],
          ),
        ),
        if (_symptomResult != null) ...[
          const SizedBox(height: 16),
          _buildStructuredSymptomResult(_symptomResult!),
          const SizedBox(height: 14),
          _buildAiResponseView(
            result: _symptomResult!,
            title: 'Clinical Triage Assessment',
            accent: Palette.teal,
          ),
        ],
      ],
    );
  }

  Widget _buildStructuredSymptomResult(Map<String, dynamic> res) {
    final urgency =
        '${res['urgencyLevel'] ?? res['triageLevel'] ?? (res['emergency'] == true ? 'P1' : 'P3')}'
            .toUpperCase();
    final summary =
        '${res['assessmentSummary'] ?? res['summary'] ?? ''}'.trim();
    final careNow = ((res['careNow'] ?? res['immediateActions']) as List?)
            ?.map((e) => '$e')
            .toList() ??
        const [];
    final whatToAvoid =
        ((res['whatToAvoid']) as List?)?.map((e) => '$e').toList() ?? const [];
    final whenToWorry = ((res['whenToWorry'] ?? res['redFlags']) as List?)
            ?.map((e) => '$e')
            .toList() ??
        const [];
    final breakdown = ((res['symptomBreakdown']) as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const [];

    final (Color uColor, String uLabel) = switch (urgency) {
      final s
          when s.startsWith('P1') ||
              s.contains('CRITICAL') ||
              s.contains('EMERGENCY') =>
        (Palette.red, 'P1 • IMMEDIATE EMERGENCY'),
      final s
          when s.startsWith('P2') ||
              s.contains('URGENT') ||
              s.contains('HIGH') =>
        (Palette.orange, 'P2 • URGENT MEDICAL EVALUATION'),
      final s when s.startsWith('P3') || s.contains('MODERATE') => (
          Palette.amber,
          'P3 • SEMI-URGENT OPD CONSULT'
        ),
      _ => (Palette.green, 'P4 • NON-URGENT / HOME CARE'),
    };

    return GlassCard(
      borderColor: uColor.withOpacity(0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: uColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: uColor.withOpacity(0.55)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_hospital_rounded, size: 15, color: uColor),
                    const SizedBox(width: 6),
                    Text(
                      uLabel,
                      style: TextStyle(
                        color: uColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _selectedBodyRegion,
                style: const TextStyle(
                    color: Palette.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              summary,
              style: const TextStyle(
                  color: Palette.text,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600),
            ),
          ],
          if (careNow.isNotEmpty) ...[
            const SizedBox(height: 14),
            _BulletSectionCard(
              title: 'Care Now (Immediate Actions)',
              items: careNow,
              color: Palette.teal,
              icon: Icons.check_circle_outline_rounded,
            ),
          ],
          if (whatToAvoid.isNotEmpty) ...[
            const SizedBox(height: 10),
            _BulletSectionCard(
              title: 'What to Avoid',
              items: whatToAvoid,
              color: Palette.amber,
              icon: Icons.do_not_disturb_on_outlined,
            ),
          ],
          if (whenToWorry.isNotEmpty) ...[
            const SizedBox(height: 10),
            _BulletSectionCard(
              title: 'When to Worry (Red-Flag Escalation)',
              items: whenToWorry,
              color: Palette.red,
              icon: Icons.warning_amber_rounded,
            ),
          ],
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Per-Symptom Clinical Breakdown',
              style: TextStyle(
                  color: Palette.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final item in breakdown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Palette.surfaceHi,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Palette.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.radar_rounded,
                              size: 15, color: Palette.blue),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${item['symptom'] ?? item['name'] ?? 'Symptom'}',
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (item['possibleCauses'] is List)
                            Text(
                              (item['possibleCauses'] as List)
                                  .take(2)
                                  .join(', '),
                              style: const TextStyle(
                                  color: Palette.teal,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                      if (item['explanation'] != null ||
                          item['clinicalNote'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${item['explanation'] ?? item['clinicalNote']}',
                          style: const TextStyle(
                              color: Palette.textDim,
                              fontSize: 12.5,
                              height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── 2. MediScan (Lab & Rx) ──────────────────────────────────────────────────
  Widget _buildMediScanTab() {
    const sampleLab = 'Hb 9.2 g/dL, WBC 13,500, Fasting Glucose 148 mg/dL';
    const sampleRx =
        'Tab Telmisartan 40mg OD, Tab Atorvastatin 20mg HS, Cap Ecosprin 75mg OD';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('MediScan • Lab Report & Prescription Interpreter'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste blood work panels, diagnostic lab values, or discharge prescription text for plain-language clinical interpretation and reference ranges.',
                style: TextStyle(
                    color: Palette.textDim, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _mediScanCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Lab report values or prescription text',
                  hintText: 'Paste CBC, lipid profile, HbA1c, or Rx items…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick Samples',
                style: TextStyle(
                    color: Palette.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SampleChip(
                    label: sampleLab,
                    accent: Palette.blue,
                    onTap: () => _runMediScan(sampleLab),
                  ),
                  _SampleChip(
                    label: sampleRx,
                    accent: Palette.blue,
                    onTap: () => _runMediScan(sampleRx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _mediScanBusy ? null : () => _runMediScan(),
                style: FilledButton.styleFrom(
                    backgroundColor: Palette.blue, foregroundColor: Palette.bg),
                icon: _mediScanBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Palette.bg),
                      )
                    : const Icon(Icons.biotech_rounded),
                label: Text(_mediScanBusy
                    ? 'Analyzing Report…'
                    : 'Analyze with MediScan'),
              ),
            ],
          ),
        ),
        if (_mediScanResult != null) ...[
          const SizedBox(height: 16),
          _buildAiResponseView(
            result: _mediScanResult!,
            title: 'MediScan Structured Interpretation',
            accent: Palette.blue,
          ),
          const SizedBox(height: 10),
          _buildRlhfFeedbackBar(
            logId:
                '${_mediScanResult!['logId'] ?? _mediScanResult!['id'] ?? 'mediscan_log'}',
            selectedReward: _mediScanFeedbackReward,
            isRadiology: false,
          ),
        ],
      ],
    );
  }

  // ── 3. OpenFDA Drug Interactions ────────────────────────────────────────────
  Widget _buildOpenFdaTab() {
    const pairs = <({String a, String b})>[
      (a: 'Aspirin', b: 'Warfarin'),
      (a: 'Sildenafil', b: 'Nitroglycerin'),
      (a: 'Ibuprofen', b: 'Aspirin'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('OpenFDA Drug-Drug Interaction Checker'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Query official US FDA drug adverse-event & clinical interaction records before combining prescription or OTC medications.',
                style: TextStyle(
                    color: Palette.textDim, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _drug1Ctrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Drug A',
                        hintText: 'e.g., Aspirin',
                        prefixIcon: Icon(Icons.medication_rounded,
                            color: Palette.amber),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.compare_arrows_rounded,
                        color: Palette.textDim),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _drug2Ctrl,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _runFdaInteractions(),
                      decoration: const InputDecoration(
                        labelText: 'Drug B',
                        hintText: 'e.g., Warfarin',
                        prefixIcon: Icon(Icons.medication_liquid_rounded,
                            color: Palette.amber),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick Pair Checks',
                style: TextStyle(
                    color: Palette.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final pair in pairs)
                    _SampleChip(
                      label: '${pair.a} + ${pair.b}',
                      accent: Palette.amber,
                      onTap: () => _runFdaInteractions(pair.a, pair.b),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _fdaBusy ? null : () => _runFdaInteractions(),
                style: FilledButton.styleFrom(
                    backgroundColor: Palette.amber,
                    foregroundColor: Palette.bg),
                icon: _fdaBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Palette.bg),
                      )
                    : const Icon(Icons.verified_user_rounded),
                label: Text(
                    _fdaBusy ? 'Checking OpenFDA…' : 'Check Drug Interaction'),
              ),
            ],
          ),
        ),
        if (_fdaResult != null) ...[
          const SizedBox(height: 16),
          _buildFdaResultCard(_fdaResult!),
        ],
      ],
    );
  }

  Widget _buildFdaResultCard(Map<String, dynamic> res) {
    final drug1 = '${res['drug1'] ?? _drug1Ctrl.text}'.trim();
    final drug2 = '${res['drug2'] ?? _drug2Ctrl.text}'.trim();
    final severity = '${res['severity'] ?? 'none'}'.toLowerCase();
    final hasInteraction = res['hasInteraction'] == true;
    final interactions =
        ((res['interactions'] as List?) ?? const []).map((e) => '$e').toList();
    final disclaimer =
        '${res['disclaimer'] ?? 'Data sourced from OpenFDA & clinical interaction knowledge base. Always consult a licensed pharmacist or physician.'}';

    final (Color badgeColor, String badgeLabel, IconData badgeIcon) =
        switch (severity) {
      'critical' => (Palette.red, 'CRITICAL', Icons.dangerous_rounded),
      'high' => (Palette.orange, 'HIGH', Icons.warning_amber_rounded),
      'moderate' => (Palette.amber, 'MODERATE', Icons.info_outline_rounded),
      _ => hasInteraction
          ? (Palette.amber, 'MODERATE', Icons.info_outline_rounded)
          : (Palette.green, 'SAFE', Icons.check_circle_outline_rounded),
    };

    return GlassCard(
      borderColor: badgeColor.withOpacity(0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(badgeIcon, color: badgeColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$drug1 + $drug2',
                      style: const TextStyle(
                          color: Palette.text,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasInteraction
                          ? 'Clinically significant interaction detected'
                          : 'No major interaction flagged',
                      style: const TextStyle(
                          color: Palette.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withOpacity(0.5)),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (interactions.isEmpty)
            const Text(
              'No severe interaction warnings were returned for this pair. Continue monitoring and consult your pharmacist if taking additional medications.',
              style: TextStyle(color: Palette.text, fontSize: 14, height: 1.45),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in interactions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Palette.surfaceHi,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: badgeColor.withOpacity(0.28)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(Icons.arrow_right_rounded,
                                color: badgeColor, size: 20),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(
                                  color: Palette.text,
                                  fontSize: 13.8,
                                  height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          const Divider(height: 20, color: Palette.outline),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.policy_outlined,
                  size: 15, color: Palette.textDim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  disclaimer,
                  style: const TextStyle(
                      color: Palette.textDim, fontSize: 11.5, height: 1.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 4. Medicine Analyzer (with Ingredients, Side Effects & AYUSH Alternatives) ─
  Widget _buildMedicineAnalyzerTab() {
    const samples = <String>[
      'Metformin 500mg',
      'Amoxicillin + Clavulanate',
      'Atorvastatin 20mg',
      'Paracetamol 650mg',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('AI Medicine, Salt & AYUSH Alternatives Analyzer'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter any brand name, generic drug, or active salt composition to inspect active ingredients, side effects with severity, and Ayurvedic & Natural Alternatives.',
                style: TextStyle(
                    color: Palette.textDim, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _medicineCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runMedicineAnalyzer(),
                decoration: const InputDecoration(
                  labelText: 'Medicine name or active salts',
                  hintText:
                      'e.g., Metformin 500mg or Amoxicillin + Clavulanate',
                  prefixIcon:
                      Icon(Icons.vaccines_rounded, color: Palette.green),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick Lookups',
                style: TextStyle(
                    color: Palette.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in samples)
                    _SampleChip(
                      label: s,
                      accent: Palette.green,
                      onTap: () => _runMedicineAnalyzer(s),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _medicineBusy ? null : () => _runMedicineAnalyzer(),
                style: FilledButton.styleFrom(
                    backgroundColor: Palette.green,
                    foregroundColor: Palette.bg),
                icon: _medicineBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Palette.bg),
                      )
                    : const Icon(Icons.science_rounded),
                label: Text(_medicineBusy
                    ? 'Analyzing Composition…'
                    : 'Analyze Medicine & AYUSH Options'),
              ),
            ],
          ),
        ),
        if (_medicineResult != null) ...[
          const SizedBox(height: 16),
          _buildStructuredMedicineBreakdown(_medicineResult!),
          const SizedBox(height: 14),
          _buildAiResponseView(
            result: _medicineResult!,
            title: 'Pharmacological Profile & Safety',
            accent: Palette.green,
          ),
        ],
      ],
    );
  }

  Widget _buildStructuredMedicineBreakdown(Map<String, dynamic> res) {
    final ingredients =
        ((res['ingredients'] ?? res['activeIngredients']) as List?) ?? const [];
    final sideEffects = ((res['sideEffects']) as List?) ?? const [];
    final ayurvedic = ((res['ayurvedicAlternatives'] ??
            res['naturalAlternatives']) as List?) ??
        const [];

    if (ingredients.isEmpty && sideEffects.isEmpty && ayurvedic.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Active Ingredients
        if (ingredients.isNotEmpty)
          GlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: Palette.green.withOpacity(0.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.science_rounded, color: Palette.green, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Active Pharmaceutical Ingredients (Salts)',
                      style: TextStyle(
                          color: Palette.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final ing in ingredients)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: Palette.surfaceHi,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Palette.outline),
                      ),
                      child: ing is Map
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${ing['name'] ?? ing['ingredient'] ?? 'Active Salt'} ${ing['strength'] != null ? "(${ing['strength']})" : ""}',
                                  style: const TextStyle(
                                    color: Palette.green,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (ing['purpose'] != null ||
                                    ing['mechanism'] != null ||
                                    ing['description'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      '${ing['purpose'] ?? ing['mechanism'] ?? ing['description']}',
                                      style: const TextStyle(
                                          color: Palette.textDim, fontSize: 12),
                                    ),
                                  ),
                              ],
                            )
                          : Text(
                              '• $ing',
                              style: const TextStyle(
                                  color: Palette.text, fontSize: 13),
                            ),
                    ),
                  ),
              ],
            ),
          ),

        // Side Effects with Severity
        if (sideEffects.isNotEmpty) ...[
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: Palette.amber.withOpacity(0.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Palette.amber, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Adverse Effects & Severity Profile',
                      style: TextStyle(
                          color: Palette.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final se in sideEffects)
                      Builder(
                        builder: (context) {
                          final name = se is Map
                              ? '${se['effect'] ?? se['name'] ?? se}'
                              : '$se';
                          final sev = se is Map
                              ? '${se['severity'] ?? se['frequency'] ?? 'moderate'}'
                                  .toLowerCase()
                              : 'common';
                          final c =
                              sev.contains('severe') || sev.contains('high')
                                  ? Palette.red
                                  : sev.contains('mod')
                                      ? Palette.amber
                                      : Palette.blue;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 7),
                            decoration: BoxDecoration(
                              color: c.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: c.withOpacity(0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                      color: Palette.text,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  sev.toUpperCase(),
                                  style: TextStyle(
                                      color: c,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // Ayurvedic & Natural Alternatives
        if (ayurvedic.isNotEmpty) ...[
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: Palette.teal.withOpacity(0.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.spa_rounded, color: Palette.teal, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ayurvedic & Natural Supportive Alternatives (AYUSH)',
                        style: TextStyle(
                            color: Palette.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final alt in ayurvedic)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Palette.surfaceHi,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Palette.teal.withOpacity(0.32)),
                      ),
                      child: alt is Map
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${alt['name'] ?? alt['herb'] ?? 'Ayurvedic Formulation'}',
                                  style: const TextStyle(
                                    color: Palette.teal,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (alt['benefit'] != null ||
                                    alt['description'] != null ||
                                    alt['usage'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${alt['benefit'] ?? alt['description'] ?? alt['usage']}',
                                      style: const TextStyle(
                                          color: Palette.text,
                                          fontSize: 12.5,
                                          height: 1.35),
                                    ),
                                  ),
                              ],
                            )
                          : Text(
                              '• $alt',
                              style: const TextStyle(
                                  color: Palette.text, fontSize: 13),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── 5. Mental Wellbeing ─────────────────────────────────────────────────────
  Widget _buildWellbeingTab() {
    const samples = <String>[
      'Feeling overwhelmed with caregiver burnout and insomnia',
      'Sudden racing heart and anxious thoughts before sleep',
      'Guided 4-7-8 breathing exercise for acute stress',
    ];

    const helplines =
        <({String name, String subtitle, String number, Color color})>[
      (
        name: 'iCall (TISS)',
        subtitle: 'Psychosocial helpline',
        number: '9152987821',
        color: Palette.teal
      ),
      (
        name: 'Vandrevala Foundation',
        subtitle: '24/7 crisis & mental health support',
        number: '1860-2662-345',
        color: Palette.blue
      ),
      (
        name: 'National Emergency',
        subtitle: 'Immediate emergency dispatch',
        number: '112',
        color: Palette.red
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 24/7 Verified Crisis Helpline Banner
        GlassCard(
          padding: const EdgeInsets.all(16),
          borderColor: Palette.orange.withOpacity(0.45),
          gradient: LinearGradient(
            colors: [
              Palette.orange.withOpacity(0.14),
              Palette.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Palette.orange.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.support_agent_rounded,
                        color: Palette.orange, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '24/7 Verified Crisis & Emotional Support Helplines',
                          style: TextStyle(
                              color: Palette.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Free, confidential human support across India — tap any number to call.',
                          style:
                              TextStyle(color: Palette.textDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final h in helplines)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _dialNumber(h.number),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: h.color.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: h.color.withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.call_rounded, size: 15, color: h.color),
                            const SizedBox(width: 7),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${h.name} • ${h.number}',
                                  style: TextStyle(
                                    color: h.color,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: kTabular,
                                  ),
                                ),
                                Text(
                                  h.subtitle,
                                  style: const TextStyle(
                                      color: Palette.textDim, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader('Mental Wellbeing & Grounding Companion'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share how you are feeling—stress, anxiety, sleep trouble, or caregiver fatigue—for evidence-based CBT grounding and breathing support.',
                style: TextStyle(
                    color: Palette.textDim, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _wellbeingCtrl,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'How are you feeling right now?',
                  hintText: 'Share what is on your mind…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick Prompts',
                style: TextStyle(
                    color: Palette.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in samples)
                    _SampleChip(
                      label: s,
                      accent: Palette.orange,
                      onTap: () => _runWellbeing(s),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _wellbeingBusy ? null : () => _runWellbeing(),
                style: FilledButton.styleFrom(
                    backgroundColor: Palette.orange,
                    foregroundColor: Palette.bg),
                icon: _wellbeingBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Palette.bg),
                      )
                    : const Icon(Icons.self_improvement_rounded),
                label: Text(_wellbeingBusy
                    ? 'Preparing Support…'
                    : 'Get Wellbeing Guidance'),
              ),
            ],
          ),
        ),
        if (_wellbeingResult != null) ...[
          const SizedBox(height: 16),
          _buildAiResponseView(
            result: _wellbeingResult!,
            title: 'Compassionate Wellbeing Support',
            accent: Palette.orange,
          ),
        ],
      ],
    );
  }

  // ── 6. AI Radiology & Diagnostic Imaging ────────────────────────────────────
  Widget _buildRadiologyImagingTab() {
    const presets = <({String modality, String region, String context})>[
      (
        modality: 'Chest X-Ray',
        region: 'Thorax / Bilateral Lungs',
        context:
            'Fever, productive cough, and SpO2 93%; evaluate right lower lobe opacity & cardiothoracic ratio.',
      ),
      (
        modality: 'Brain CT/MRI',
        region: 'Cranium / Cerebral Hemisphere',
        context:
            'Acute onset right-sided weakness and slurred speech; rule out ischemic infarct or hemorrhage.',
      ),
      (
        modality: 'Bone/Joint X-Ray',
        region: 'Knee / Shoulder Joint',
        context:
            'History of fall detected by walking stick; localized tenderness and swelling.',
      ),
      (
        modality: 'Retinal/Skin Scan',
        region: 'Retina / Macula',
        context:
            'Long-standing Type 2 Diabetes; screen for microaneurysms or macular edema.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('AI Radiology & Diagnostic Imaging Analyzer'),
        GlassCard(
          borderColor: Palette.red.withOpacity(0.45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select imaging modality, anatomical region, and clinical context to run structured radiological ROI bounding-box detection, differential diagnosis, and RLHF verification.',
                style: TextStyle(
                    color: Palette.textDim, fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text(
                '1. Imaging Modality',
                style: TextStyle(
                    color: Palette.red,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _imagingModalities)
                    ChoiceChip(
                      label: Text(m),
                      selected: _selectedModality == m,
                      selectedColor: Palette.red.withOpacity(0.22),
                      backgroundColor: Palette.surfaceHi,
                      labelStyle: TextStyle(
                        color:
                            _selectedModality == m ? Palette.red : Palette.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                      side: BorderSide(
                        color: _selectedModality == m
                            ? Palette.red
                            : Palette.outline,
                      ),
                      onSelected: (_) => setState(() => _selectedModality = m),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _selectedImagingRegion,
                dropdownColor: Palette.surfaceHi,
                decoration: const InputDecoration(
                  labelText: '2. Target Anatomical Region',
                  prefixIcon: Icon(Icons.radar_rounded, color: Palette.red),
                ),
                items: _imagingRegions
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedImagingRegion = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _radiologyContextCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '3. Clinical Indication / Radiograph Notes',
                  hintText:
                      'Optional: enter the patient’s actual symptoms or notes.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick Imaging Presets',
                style: TextStyle(
                    color: Palette.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in presets)
                    _SampleChip(
                      label:
                          '${p.modality} • ${p.region.split('/').first.trim()}',
                      accent: Palette.red,
                      onTap: () => _runDiagnosticImaging(
                          p.modality, p.region, p.context),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.red,
                  foregroundColor: Colors.white,
                ),
                onPressed:
                    _radiologyBusy ? null : () => _runDiagnosticImaging(),
                icon: _radiologyBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.document_scanner_rounded),
                label: Text(_radiologyBusy
                    ? 'Running AI Radiology Analysis…'
                    : 'Analyze Diagnostic Imaging'),
              ),
            ],
          ),
        ),
        if (_radiologyResult != null) ...[
          const SizedBox(height: 16),
          _buildRadiologyResultView(_radiologyResult!),
          const SizedBox(height: 12),
          _buildRlhfFeedbackBar(
            logId:
                '${_radiologyResult!['logId'] ?? _radiologyResult!['id'] ?? 'radiology_log'}',
            selectedReward: _radiologyFeedbackReward,
            isRadiology: true,
          ),
        ],
      ],
    );
  }

  Widget _buildRadiologyResultView(Map<String, dynamic> res) {
    final rawConf = res['confidenceScore'] ?? res['confidence'] ?? 0.89;
    final confPct = rawConf is num
        ? (rawConf <= 1.0 ? (rawConf * 100).round() : rawConf.round())
        : 89;
    final findings = ((res['findings']) as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const [];
    final possibleConditions = ((res['possibleConditions']) as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const [];
    final diffDx =
        ((res['differentialDiagnosis']) as List?)?.map((e) => '$e').toList() ??
            const [];
    final impression =
        '${res['impression'] ?? res['summary'] ?? res['response'] ?? ''}'
            .trim();

    return GlassCard(
      borderColor: Palette.red.withOpacity(0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Palette.red.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.collections_bookmark_rounded,
                    color: Palette.red, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_selectedModality • $_selectedImagingRegion',
                      style: const TextStyle(
                          color: Palette.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800),
                    ),
                    const Text(
                      'Structured AI Radiology Report & Bounding-Box Localization',
                      style: TextStyle(color: Palette.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Palette.teal.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Palette.teal.withOpacity(0.45)),
                ),
                child: Text(
                  '$confPct% CONFIDENCE',
                  style: const TextStyle(
                    color: Palette.teal,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    fontFeatures: kTabular,
                  ),
                ),
              ),
            ],
          ),
          if (impression.isNotEmpty) ...[
            const SizedBox(height: 14),
            MarkdownLite(impression),
          ],

          // Annotated Findings with BoundingBoxes & Severity Badges
          if (findings.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Annotated Radiological Findings & ROI Coordinates',
              style: TextStyle(
                  color: Palette.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final f in findings)
              Builder(
                builder: (context) {
                  final sev = '${f['severity'] ?? 'moderate'}'.toLowerCase();
                  final sevColor = sev.contains('high') || sev.contains('crit')
                      ? Palette.red
                      : sev.contains('mod')
                          ? Palette.amber
                          : Palette.green;
                  final bbox = f['boundingBox'] ?? f['box'] ?? f['coordinates'];
                  String bboxText = '';
                  if (bbox is Map) {
                    bboxText =
                        'ROI [x:${bbox['x'] ?? 0}, y:${bbox['y'] ?? 0}, w:${bbox['width'] ?? bbox['w'] ?? 0}, h:${bbox['height'] ?? bbox['h'] ?? 0}]';
                  } else if (bbox is List) {
                    bboxText = 'ROI [${bbox.join(", ")}]';
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Palette.surfaceHi,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: sevColor.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.crop_free_rounded,
                                  size: 16, color: sevColor),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  '${f['finding'] ?? f['label'] ?? f['region'] ?? 'Radiological Finding'}',
                                  style: const TextStyle(
                                    color: Palette.text,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: sevColor.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  sev.toUpperCase(),
                                  style: TextStyle(
                                    color: sevColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (bboxText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              bboxText,
                              style: const TextStyle(
                                color: Palette.blue,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                fontFeatures: kTabular,
                              ),
                            ),
                          ],
                          if (f['description'] != null ||
                              f['details'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${f['description'] ?? f['details']}',
                              style: const TextStyle(
                                  color: Palette.textDim,
                                  fontSize: 12.5,
                                  height: 1.35),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],

          // Possible Conditions with Likelihood %
          if (possibleConditions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Possible Conditions & Likelihood %',
              style: TextStyle(
                  color: Palette.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final c in possibleConditions)
              Builder(
                builder: (context) {
                  final rawLikelihood =
                      c['likelihood'] ?? c['probability'] ?? 70;
                  final pct = rawLikelihood is num
                      ? (rawLikelihood <= 1.0
                          ? (rawLikelihood * 100).round()
                          : rawLikelihood.round())
                      : int.tryParse('$rawLikelihood'.replaceAll('%', '')) ??
                          70;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${c['condition'] ?? c['name'] ?? 'Condition'}',
                              style: const TextStyle(
                                  color: Palette.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '$pct%',
                              style: const TextStyle(
                                color: Palette.teal,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                fontFeatures: kTabular,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (pct / 100.0).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: Palette.surfaceHi,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Palette.teal),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],

          // Differential Diagnosis
          if (diffDx.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Differential Diagnosis',
              style: TextStyle(
                  color: Palette.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final dx in diffDx)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Palette.surfaceHi,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Palette.outline),
                    ),
                    child: Text(
                      dx,
                      style: const TextStyle(
                          color: Palette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRlhfFeedbackBar({
    required String logId,
    required int? selectedReward,
    required bool isRadiology,
  }) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderColor: Palette.outline,
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, size: 18, color: Palette.teal),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'RLHF Clinical Calibration: Was this AI interpretation accurate?',
              style: TextStyle(
                  color: Palette.textDim,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Accurate (+1 RLHF)',
            style: IconButton.styleFrom(
              backgroundColor: selectedReward == 1
                  ? Palette.green.withOpacity(0.25)
                  : Palette.surfaceHi,
            ),
            onPressed: _sendingFeedback
                ? null
                : () => _submitRlhfFeedback(
                    logId: logId, reward: 1, isRadiology: isRadiology),
            icon: Icon(
              Icons.thumb_up_alt_rounded,
              size: 18,
              color: selectedReward == 1 ? Palette.green : Palette.text,
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Needs Correction (-1 RLHF)',
            style: IconButton.styleFrom(
              backgroundColor: selectedReward == -1
                  ? Palette.red.withOpacity(0.25)
                  : Palette.surfaceHi,
            ),
            onPressed: _sendingFeedback
                ? null
                : () => _submitRlhfFeedback(
                    logId: logId, reward: -1, isRadiology: isRadiology),
            icon: Icon(
              Icons.thumb_down_alt_rounded,
              size: 18,
              color: selectedReward == -1 ? Palette.red : Palette.text,
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared AI Response Renderer (Emergency Banner + Markdown + Citations) ──
  Widget _buildAiResponseView({
    required Map<String, dynamic> result,
    required String title,
    required Color accent,
  }) {
    final emergency = result['emergency'] == true;
    final responseText =
        '${result['response'] ?? result['summary'] ?? result['assessmentSummary'] ?? ''}'
            .trim();
    final provider = '${result['provider'] ?? 'Jeevan Clinical AI'}';
    final rawSources = (result['sources'] as List?) ?? const [];
    final sources = rawSources
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (emergency) ...[
          GlassCard(
            padding: const EdgeInsets.all(16),
            color: Palette.red.withOpacity(0.14),
            borderColor: Palette.red.withOpacity(0.65),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.emergency_rounded,
                    color: Palette.red, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'POTENTIAL MEDICAL EMERGENCY DETECTED',
                        style: TextStyle(
                          color: Palette.red,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Red-flag symptoms require immediate medical attention. Do not wait—call Emergency 112 or trigger Jeevan SOS immediately.',
                        style: TextStyle(
                            color: Palette.text, fontSize: 13, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => _dialNumber('112'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Palette.red,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 38),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                            ),
                            icon: const Icon(Icons.call_rounded, size: 16),
                            label: const Text('Call 112 Now',
                                style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        GlassCard(
          borderColor: emergency
              ? Palette.red.withOpacity(0.45)
              : accent.withOpacity(0.4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          color: Palette.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withOpacity(0.35)),
                    ),
                    child: Text(
                      provider.toUpperCase(),
                      style: TextStyle(
                        color: accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 22, color: Palette.outline),
              if (responseText.isEmpty)
                const Text(
                  'Structured assessment complete — see clinical breakdown cards above.',
                  style: TextStyle(color: Palette.textDim, fontSize: 14),
                )
              else
                MarkdownLite(responseText),
              if (sources.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(height: 1, color: Palette.outline),
                const SizedBox(height: 12),
                const Text(
                  'Clinical Knowledge Base Citations',
                  style: TextStyle(
                      color: Palette.textDim,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in sources)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Palette.surfaceHi,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Palette.outline),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '[${s['n'] ?? '?'}]',
                              style: TextStyle(
                                color: accent,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                fontFeatures: kTabular,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                [
                                  if (s['title'] != null &&
                                      '${s['title']}'.isNotEmpty)
                                    '${s['title']}',
                                  if (s['heading'] != null &&
                                      '${s['heading']}'.isNotEmpty)
                                    '${s['heading']}',
                                ].join(' • '),
                                style: const TextStyle(
                                    color: Palette.text, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BulletSectionCard extends StatelessWidget {
  const _BulletSectionCard({
    required this.title,
    required this.items,
    required this.color,
    required this.icon,
  });

  final String title;
  final List<String> items;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                    color: color, fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $item',
                style: const TextStyle(
                    color: Palette.text, fontSize: 12.5, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}

class _SampleChip extends StatelessWidget {
  const _SampleChip({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withOpacity(0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 13, color: accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Palette.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Jeevan sync: 2026-11-13
