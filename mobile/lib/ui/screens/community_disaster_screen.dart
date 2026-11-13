import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/map_gesture_layer.dart';
import '../widgets/map_tile_image.dart';

/// Community, Disaster Response, Blood Bank, Verified NGOs, ABDM/ABHA ID & Emergency Medical QR Profile.
class CommunityDisasterScreen extends ConsumerStatefulWidget {
  const CommunityDisasterScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<CommunityDisasterScreen> createState() =>
      _CommunityDisasterScreenState();
}

class _CommunityDisasterScreenState
    extends ConsumerState<CommunityDisasterScreen> {
  late int _section;

  static const _sections = <(IconData, String)>[
    (Icons.thunderstorm_rounded, 'Disaster & Radar'),
    (Icons.bloodtype_rounded, 'Blood Bank'),
    (Icons.volunteer_activism_rounded, 'Verified NGOs'),
    (Icons.badge_rounded, 'ABHA Health ID'),
    (Icons.qr_code_2_rounded, 'Medical ID & QR'),
  ];

  // ── 1. Disaster & Weather Radar state ───────────────────────────────────────
  double _lat = 12.9716;
  double _lng = 77.5946;
  double _mapCenterLat = 12.9716;
  double _mapCenterLng = 77.5946;
  bool _mapWasMoved = false;
  int _mapZoom = 11;
  bool _loadingDisaster = false;
  String? _disasterError;
  Map<String, dynamic>? _riskData;
  Map<String, dynamic>? _radarData;

  // ── 2. Blood Bank state ─────────────────────────────────────────────────────
  static const _bloodGroups = <String>[
    'All',
    'Not specified',
    'O+',
    'O-',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-'
  ];
  String _selectedBloodGroup = 'All';
  final _citySearchCtrl = TextEditingController();
  bool _loadingDonors = false;
  String? _donorsError;
  List<Map<String, dynamic>> _donors = const [];

  // ── 3. Verified NGOs state ──────────────────────────────────────────────────
  static const _ngoCategories = <(String, String)>[
    ('all', 'All'),
    ('disaster-relief', 'Disaster Relief'),
    ('medical-aid', 'Medical Aid'),
    ('mental-health', 'Mental Health'),
    ('food-shelter', 'Food & Shelter'),
    ('child-welfare', 'Child Welfare'),
  ];
  String _selectedNgoCategory = 'all';
  bool _loadingNgos = false;
  String? _ngosError;
  List<Map<String, dynamic>> _ngos = const [];

  // ── 4. ABHA Health ID (ABDM) state ──────────────────────────────────────────
  final _aadhaarCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _generatingOtp = false;
  bool _verifyingOtp = false;
  String? _txnId;
  String? _otpHintMessage;
  String? _abhaNumber;

  // ── 5. Emergency Medical ID & QR Profile state ──────────────────────────────
  bool _loadingSummary = false;
  bool _savingSummary = false;
  String _uid = '';
  final _nameCtrl = TextEditingController();
  String _profileBloodGroup = 'Not specified';
  final _dobCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _medicationsCtrl = TextEditingController();
  List<Map<String, String>> _contacts = [];

  @override
  void initState() {
    super.initState();
    _section = widget.initialTab.clamp(0, _sections.length - 1);
    unawaited(_loadAllInitial());
  }

  @override
  void dispose() {
    _citySearchCtrl.dispose();
    _aadhaarCtrl.dispose();
    _otpCtrl.dispose();
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    _medicationsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllInitial() async {
    await Future.wait([
      _loadDisasterAndWeather(tryGps: true),
      _loadBloodDonors(),
      _loadNgos(),
      _loadEmergencySummary(),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. DISASTER & WEATHER RADAR LOGIC
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _loadDisasterAndWeather({bool tryGps = false}) async {
    if (!mounted) return;
    setState(() {
      _loadingDisaster = true;
      _disasterError = null;
    });

    if (tryGps) {
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse) {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) {
            _lat = last.latitude;
            _lng = last.longitude;
          }
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 4),
            ),
          );
          _lat = pos.latitude;
          _lng = pos.longitude;
        }
      } catch (_) {
        // Keep fallback coordinates
      }
    }
    if (!_mapWasMoved) {
      _mapCenterLat = _lat;
      _mapCenterLng = _lng;
    }

    try {
      final api = ref.read(apiProvider);
      final results = await Future.wait([
        api.disasterRiskScore(lat: _lat, lng: _lng),
        api.weatherRadar(lat: _lat, lon: _lng),
      ]);
      if (!mounted) return;
      setState(() {
        _riskData = results[0];
        _radarData = results[1];
        _loadingDisaster = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _disasterError = e.toString();
        _loadingDisaster = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. BLOOD BANK LOGIC
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _loadBloodDonors() async {
    if (!mounted) return;
    setState(() {
      _loadingDonors = true;
      _donorsError = null;
    });
    try {
      final bt = _selectedBloodGroup == 'All' ? '' : _selectedBloodGroup;
      final city = _citySearchCtrl.text.trim();
      final list = await ref
          .read(apiProvider)
          .searchBloodBank(bloodType: bt, city: city);
      if (!mounted) return;
      setState(() {
        _donors = list;
        _loadingDonors = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _donorsError = e.toString();
        _loadingDonors = false;
      });
    }
  }

  Future<void> _showRegisterDonorDialog() async {
    final nameCtrl = TextEditingController(text: _nameCtrl.text.trim());
    final cityCtrl = TextEditingController(text: _citySearchCtrl.text.trim());
    final phoneCtrl = TextEditingController();
    String bloodGroup =
        _selectedBloodGroup == 'All' ? _profileBloodGroup : _selectedBloodGroup;
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Palette.outline),
          ),
          title: const Row(
            children: [
              Icon(Icons.bloodtype_rounded, color: Palette.red),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Become a Blood Donor',
                  style: TextStyle(
                      color: Palette.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Palette.text),
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    prefixIcon:
                        Icon(Icons.person_outline_rounded, color: Palette.teal),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: bloodGroup,
                  dropdownColor: Palette.surfaceHi,
                  style: const TextStyle(
                      color: Palette.text, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    labelText: 'Blood Group *',
                    prefixIcon:
                        Icon(Icons.bloodtype_outlined, color: Palette.red),
                  ),
                  items: _bloodGroups
                      .where((g) => g != 'All')
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => bloodGroup = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cityCtrl,
                  style: const TextStyle(color: Palette.text),
                  decoration: const InputDecoration(
                    labelText: 'City *',
                    prefixIcon:
                        Icon(Icons.location_city_rounded, color: Palette.blue),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Palette.text),
                  decoration: const InputDecoration(
                    labelText: 'Contact Phone (Optional)',
                    hintText: '+91 9876543210',
                    prefixIcon:
                        Icon(Icons.phone_outlined, color: Palette.green),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: Palette.textDim)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(130, 44),
                backgroundColor: Palette.red,
                foregroundColor: Colors.white,
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final city = cityCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();
                      if (name.length < 2 || city.length < 2) {
                        showSnack(context, 'Please enter your name and city.',
                            error: true);
                        return;
                      }
                      if (bloodGroup == 'Not specified') {
                        showSnack(context,
                            'Choose your blood group to register as a donor.',
                            error: true);
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        await ref.read(apiProvider).registerBloodDonor(
                              name: name,
                              bloodType: bloodGroup,
                              city: city,
                              phone: phone.isEmpty ? null : phone,
                            );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          showSnack(context,
                              'Registered $name ($bloodGroup) in $city Blood Bank!');
                          await _loadBloodDonors();
                        }
                      } catch (e) {
                        if (mounted)
                          showSnack(context, 'Registration failed: $e',
                              error: true);
                      } finally {
                        if (ctx.mounted)
                          setDialogState(() => submitting = false);
                      }
                    },
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.favorite_rounded, size: 18),
              label: Text(submitting ? 'Saving…' : 'Register'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    cityCtrl.dispose();
    phoneCtrl.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. VERIFIED NGOS LOGIC
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _loadNgos() async {
    if (!mounted) return;
    setState(() {
      _loadingNgos = true;
      _ngosError = null;
    });
    try {
      final list =
          await ref.read(apiProvider).listNgos(category: _selectedNgoCategory);
      if (!mounted) return;
      setState(() {
        _ngos = list;
        _loadingNgos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ngosError = e.toString();
        _loadingNgos = false;
      });
    }
  }

  Future<void> _showContactNgoDialog(Map<String, dynamic> ngo) async {
    final senderCtrl = TextEditingController(text: _nameCtrl.text.trim());
    final msgCtrl = TextEditingController();
    bool sending = false;
    final ngoId = '${ngo['id'] ?? ''}';
    final ngoName = '${ngo['name'] ?? 'NGO'}';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Palette.outline),
          ),
          title: Row(
            children: [
              const Icon(Icons.volunteer_activism_rounded, color: Palette.teal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Contact $ngoName',
                  style: const TextStyle(
                      color: Palette.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: senderCtrl,
                  style: const TextStyle(color: Palette.text),
                  decoration: const InputDecoration(
                    labelText: 'Your Name *',
                    prefixIcon:
                        Icon(Icons.person_outline_rounded, color: Palette.teal),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: Palette.text),
                  decoration: const InputDecoration(
                    labelText: 'Aid Request / Situation Details *',
                    hintText:
                        'Describe location, urgency, number of people affected, or medical aid needed…',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: Palette.textDim)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(130, 44)),
              onPressed: sending
                  ? null
                  : () async {
                      final sender = senderCtrl.text.trim();
                      final msg = msgCtrl.text.trim();
                      if (sender.isEmpty || msg.isEmpty) {
                        showSnack(
                            context, 'Please enter your name and message.',
                            error: true);
                        return;
                      }
                      setDialogState(() => sending = true);
                      try {
                        final res = await ref.read(apiProvider).contactNgo(
                              ngoId: ngoId,
                              senderName: sender,
                              message: msg,
                            );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          showSnack(
                            context,
                            '${res['message'] ?? 'Request sent to $ngoName.'}',
                          );
                        }
                      } catch (e) {
                        if (mounted)
                          showSnack(context, 'Failed to contact NGO: $e',
                              error: true);
                      } finally {
                        if (ctx.mounted) setDialogState(() => sending = false);
                      }
                    },
              icon: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF042F2A)),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(sending ? 'Sending…' : 'Send Request'),
            ),
          ],
        ),
      ),
    );

    senderCtrl.dispose();
    msgCtrl.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. ABDM / ABHA HEALTH ID LOGIC
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _generateAbdmOtp() async {
    final aadhaar = _aadhaarCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (aadhaar.length != 12) {
      showSnack(context, 'Enter a valid 12-digit Aadhaar number.', error: true);
      return;
    }
    setState(() => _generatingOtp = true);
    try {
      final res = await ref.read(apiProvider).abdmGenerateOtp(aadhaar);
      if (!mounted) return;
      setState(() {
        _txnId = '${res['txnId'] ?? ''}';
        _otpHintMessage =
            '${res['message'] ?? 'OTP sent to Aadhaar-linked mobile.'}';
        _generatingOtp = false;
      });
      showSnack(context, 'Aadhaar OTP generated! Enter the 6-digit OTP below.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _generatingOtp = false);
      showSnack(context, 'Could not generate OTP: $e', error: true);
    }
  }

  Future<void> _verifyAbdmOtp() async {
    final txnId = _txnId;
    if (txnId == null || txnId.isEmpty) {
      showSnack(context, 'Generate an Aadhaar OTP first.', error: true);
      return;
    }
    final otp = _otpCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (otp.length != 6) {
      showSnack(context, 'Enter a valid 6-digit OTP.', error: true);
      return;
    }
    setState(() => _verifyingOtp = true);
    try {
      final res = await ref.read(apiProvider).abdmVerifyOtp(txnId, otp);
      if (!mounted) return;
      setState(() {
        _abhaNumber = '${res['abhaNumber'] ?? ''}';
        _verifyingOtp = false;
      });
      unawaited(HapticFeedback.mediumImpact());
      showSnack(context, '${res['message'] ?? 'ABHA ID verified!'}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifyingOtp = false);
      showSnack(context, 'OTP verification failed: $e', error: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. EMERGENCY MEDICAL ID & QR PROFILE LOGIC
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _loadEmergencySummary() async {
    if (!mounted) return;
    setState(() => _loadingSummary = true);
    try {
      final data = await ref.read(apiProvider).getEmergencySummary();
      if (!mounted) return;
      _applyEmergencySummary(data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSummary = false);
    }
  }

  void _applyEmergencySummary(Map<String, dynamic> data) {
    final bt = '${data['bloodType'] ?? 'Not specified'}';
    List<String> values(dynamic raw) => (raw is List
            ? raw.map((item) => item.toString())
            : raw is String
                ? raw.split(',')
                : const <String>[])
        .map((item) => item.trim())
        .where((item) =>
            item.isNotEmpty &&
            !item.toLowerCase().startsWith('none') &&
            item.toLowerCase() != 'not provided' &&
            item.toLowerCase() != 'unknown')
        .toList();
    final allergies = values(data['allergies']);
    final conditions = values(data['conditions']);
    final meds = values(data['currentMedications']);
    final rawContacts = (data['emergencyContacts'] as List?) ?? const [];

    setState(() {
      _uid = '${data['uid'] ?? ''}';
      _nameCtrl.text = '${data['name'] ?? ''}';
      _profileBloodGroup =
          _bloodGroups.contains(bt) && bt != 'All' ? bt : 'Not specified';
      _dobCtrl.text = '${data['dob'] ?? ''}';
      _allergiesCtrl.text = allergies.join(', ');
      _conditionsCtrl.text = conditions.join(', ');
      _medicationsCtrl.text = meds.join(', ');
      _contacts = rawContacts.whereType<Map>().map((c) {
        return <String, String>{
          'name': '${c['name'] ?? ''}',
          'phone': '${c['phone'] ?? ''}',
          'email': '${c['email'] ?? ''}',
          'relationship': '${c['relationship'] ?? 'Family'}',
        };
      }).toList();
      final abha = data['abhaNumber'];
      if (abha is String && abha.isNotEmpty) {
        _abhaNumber = abha;
      }
      _loadingSummary = false;
    });
  }

  List<String> _splitCsv(String input) {
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.toLowerCase().startsWith('none'))
        .toList();
  }

  Future<void> _saveEmergencySummary() async {
    setState(() => _savingSummary = true);
    try {
      final body = <String, dynamic>{
        'name': _nameCtrl.text.trim().isEmpty
            ? ref.read(storeProvider).patientName
            : _nameCtrl.text.trim(),
        'bloodType': _profileBloodGroup,
        'dob': _dobCtrl.text.trim(),
        'allergies': _splitCsv(_allergiesCtrl.text),
        'conditions': _splitCsv(_conditionsCtrl.text),
        'currentMedications': _splitCsv(_medicationsCtrl.text),
        'emergencyContacts': _contacts
            .map((c) => {
                  'name': c['name'] ?? '',
                  'phone': c['phone'] ?? '',
                  if ((c['email'] ?? '').isNotEmpty) 'email': c['email'],
                  'relationship': c['relationship'] ?? 'Family',
                })
            .toList(),
        'showEmergencyContacts':
            ref.read(storeProvider).showEmergencyContactsOnQr,
      };
      final res = await ref.read(apiProvider).updateEmergencySummary(body);
      if (!mounted) return;
      final saved = res['summary'];
      if (saved is Map<String, dynamic>) {
        _applyEmergencySummary(saved);
      } else {
        setState(() => _savingSummary = false);
      }
      setState(() => _savingSummary = false);
      showSnack(context, 'Emergency Medical ID & QR Profile saved!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingSummary = false);
      showSnack(context, 'Could not save Emergency Profile: $e', error: true);
    }
  }

  Future<void> _showAddContactDialog() async {
    final cName = TextEditingController();
    final cPhone = TextEditingController();
    final cEmail = TextEditingController();
    final cRel = TextEditingController(text: 'Family');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Palette.outline),
        ),
        title: const Text(
          'Add Emergency Contact',
          style: TextStyle(
              color: Palette.text, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cName,
                style: const TextStyle(color: Palette.text),
                decoration: const InputDecoration(
                  labelText: 'Contact Name *',
                  prefixIcon:
                      Icon(Icons.person_outline_rounded, color: Palette.teal),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cPhone,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Palette.text),
                decoration: const InputDecoration(
                  labelText: 'Phone Number *',
                  prefixIcon: Icon(Icons.phone_outlined, color: Palette.green),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cEmail,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Palette.text),
                decoration: const InputDecoration(
                  labelText: 'Email (Optional)',
                  prefixIcon: Icon(Icons.email_outlined, color: Palette.blue),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cRel,
                style: const TextStyle(color: Palette.text),
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  hintText: 'Spouse / Parent / Physician',
                  prefixIcon: Icon(Icons.group_outlined, color: Palette.amber),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: Palette.textDim)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
            onPressed: () {
              final name = cName.text.trim();
              final phone = cPhone.text.trim();
              if (name.isEmpty || phone.isEmpty) {
                showSnack(context, 'Enter contact name and phone number.',
                    error: true);
                return;
              }
              setState(() {
                _contacts = [
                  ..._contacts,
                  {
                    'name': name,
                    'phone': phone,
                    'email': cEmail.text.trim(),
                    'relationship':
                        cRel.text.trim().isEmpty ? 'Family' : cRel.text.trim(),
                  },
                ];
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    cName.dispose();
    cPhone.dispose();
    cEmail.dispose();
    cRel.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Disaster, Blood, NGOs & ABHA'),
        actions: [
          IconButton(
            tooltip: 'Refresh All',
            onPressed: _loadAllInitial,
            icon: const Icon(Icons.refresh_rounded, color: Palette.teal),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── 5-Section Horizontal Chip Bar ──────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(
              children: [
                for (var i = 0; i < _sections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: _section == i,
                      onSelected: (_) => setState(() => _section = i),
                      avatar: Icon(
                        _sections[i].$1,
                        size: 16,
                        color: _section == i ? Palette.teal : Palette.textDim,
                      ),
                      label: Text(_sections[i].$2),
                      selectedColor: Palette.teal.withOpacity(0.18),
                      backgroundColor: Palette.surface,
                      side: BorderSide(
                        color: _section == i ? Palette.teal : Palette.outline,
                      ),
                      labelStyle: TextStyle(
                        color: _section == i ? Palette.teal : Palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: Palette.outline, height: 1),

          // ── Section Body ───────────────────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _section,
              children: [
                _buildDisasterSection(),
                _buildBloodBankSection(),
                _buildNgoSection(),
                _buildAbhaSection(),
                _buildEmergencyProfileSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 1: DISASTER & WEATHER RADAR
  // ───────────────────────────────────────────────────────────────────────────
  double _tileWorldX(double lon, int zoom) =>
      (lon + 180) / 360 * (1 << zoom) * 256;

  double _tileWorldY(double lat, int zoom) {
    final safeLat = lat.clamp(-85.05112878, 85.05112878);
    final radians = safeLat * math.pi / 180;
    return (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
        2 *
        (1 << zoom) *
        256;
  }

  void _panDisasterMap(Offset delta) {
    if (delta.distance < 0.5) return;
    final worldSize = (1 << _mapZoom) * 256.0;
    final worldX = _tileWorldX(_mapCenterLng, _mapZoom) - delta.dx;
    final worldY =
        (_tileWorldY(_mapCenterLat, _mapZoom) - delta.dy).clamp(0.0, worldSize);
    setState(() {
      _mapCenterLng = worldX / worldSize * 360 - 180;
      final n = math.pi * (1 - 2 * worldY / worldSize);
      _mapCenterLat =
          math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
      _mapWasMoved = true;
    });
  }

  Widget _disasterMapControl(IconData icon, VoidCallback onTap) => Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 19, color: Palette.text),
          ),
        ),
      );

  Widget _buildDisasterMap(String? weatherTileUrl) {
    final zoom = _mapZoom;
    const height = 230.0;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final centerX = width / 2;
          final centerY = height / 2;
          final worldX = _tileWorldX(_mapCenterLng, zoom);
          final worldY = _tileWorldY(_mapCenterLat, zoom);
          final centerTileX = (worldX / 256).floor();
          final centerTileY = (worldY / 256).floor();
          final fracX = worldX - centerTileX * 256;
          final fracY = worldY - centerTileY * 256;
          final tileCount = 1 << zoom;
          final horizontalRadius = (width / 512).ceil();
          final verticalRadius = (height / 512).ceil();
          final tiles = <Widget>[];

          for (var dx = -horizontalRadius; dx <= horizontalRadius; dx++) {
            for (var dy = -verticalRadius; dy <= verticalRadius; dy++) {
              final x = (centerTileX + dx) % tileCount;
              final y = centerTileY + dy;
              if (y < 0 || y >= tileCount) continue;
              final left = centerX + dx * 256 - fracX;
              final top = centerY + dy * 256 - fracY;
              final weatherUrl = weatherTileUrl
                  ?.replaceAll('{z}', '$zoom')
                  .replaceAll('{x}', '$x')
                  .replaceAll('{y}', '$y');

              tiles.add(Positioned(
                left: left,
                top: top,
                width: 256,
                height: 256,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MapTileImage(zoom: zoom, x: x, y: y),
                    if (weatherUrl != null)
                      Opacity(
                        opacity: 0.45,
                        child: Image.network(
                          weatherUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ));
            }
          }

          final userX = centerX + _tileWorldX(_lng, zoom) - worldX;
          final userY = centerY + _tileWorldY(_lat, zoom) - worldY;
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: MapGestureLayer(
              onPan: _panDisasterMap,
              onZoom: (delta) =>
                  setState(() => _mapZoom = (_mapZoom + delta).clamp(4, 19)),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  const Positioned.fill(
                      child: ColoredBox(color: Color(0xFFE8EDF0))),
                  ...tiles,
                  Positioned(
                    left: userX - 7,
                    top: userY - 7,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Palette.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 5)
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Column(children: [
                      _disasterMapControl(
                          Icons.add_rounded,
                          () => setState(
                              () => _mapZoom = (_mapZoom + 1).clamp(4, 19))),
                      const SizedBox(height: 4),
                      _disasterMapControl(
                          Icons.remove_rounded,
                          () => setState(
                              () => _mapZoom = (_mapZoom - 1).clamp(4, 19))),
                    ]),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 7,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Tooltip(
                        message:
                            'Map: OpenStreetMap contributors. TomTom is the keyed fallback.',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.88),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '© OpenStreetMap contributors • TomTom backup',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildDisasterSection() {
    final risk = _riskData;
    final radar = _radarData;

    final overallScore = (risk?['overallScore'] as num?)?.toInt() ?? 0;
    final riskLevel = '${risk?['riskLevel'] ?? 'low'}'.toLowerCase();
    final floodRisk = (risk?['floodRisk'] as num?)?.toInt() ?? 0;
    final fireRisk = (risk?['fireRisk'] as num?)?.toInt() ?? 0;
    final earthquakeRisk = (risk?['earthquakeRisk'] as num?)?.toInt() ?? 10;

    final weather = (risk?['weather'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final tempC =
        weather['tempC'] ?? (radar?['current']?['main']?['temp']) ?? '--';
    final humidity = weather['humidity'] ??
        (radar?['current']?['main']?['humidity']) ??
        '--';
    final windMs =
        weather['windMs'] ?? (radar?['current']?['wind']?['speed']) ?? '--';
    final desc = '${weather['description'] ?? 'clear sky'}';

    final radarSource = '${radar?['source'] ?? 'simulated'}';
    final tileUrl = radar?['tileUrl'] as String?;
    final radarMsg = radar?['message'] as String?;

    final Color levelColor = riskLevel == 'high'
        ? Palette.red
        : riskLevel == 'moderate'
            ? Palette.amber
            : Palette.green;

    return RefreshIndicator(
      color: Palette.teal,
      onRefresh: () => _loadDisasterAndWeather(tryGps: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Palette.teal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Palette.teal.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.my_location_rounded,
                        color: Palette.teal, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)}',
                      style: const TextStyle(
                        color: Palette.teal,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFeatures: kTabular,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Palette.teal,
                  side: BorderSide(color: Palette.teal.withOpacity(0.45)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loadingDisaster
                    ? null
                    : () => _loadDisasterAndWeather(tryGps: true),
                icon: _loadingDisaster
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Palette.teal),
                      )
                    : const Icon(Icons.gps_fixed_rounded, size: 16),
                label: const Text('Update GPS Radar',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_disasterError != null)
            EmptyState(
              Icons.cloud_off_rounded,
              'Disaster Radar Unavailable',
              _disasterError!,
              action: FilledButton.icon(
                onPressed: () => _loadDisasterAndWeather(tryGps: false),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            )
          else ...[
            // Overall Disaster Risk Score Hero Card
            GlassCard(
              padding: const EdgeInsets.all(18),
              borderColor: levelColor.withOpacity(0.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  levelColor.withOpacity(0.14),
                  Palette.surface,
                ],
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 86,
                    height: 86,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 82,
                          height: 82,
                          child: CircularProgressIndicator(
                            value: (overallScore / 100.0).clamp(0.0, 1.0),
                            strokeWidth: 8,
                            backgroundColor: Palette.outline,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(levelColor),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$overallScore',
                              style: TextStyle(
                                color: levelColor,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                fontFeatures: kTabular,
                              ),
                            ),
                            const Text(
                              '/ 100',
                              style: TextStyle(
                                  color: Palette.textDim,
                                  fontSize: 10,
                                  fontFeatures: kTabular),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'DISASTER RISK SCORE',
                              style: TextStyle(
                                color: Palette.textDim,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: levelColor.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: levelColor.withOpacity(0.45)),
                              ),
                              child: Text(
                                riskLevel.toUpperCase(),
                                style: TextStyle(
                                  color: levelColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          riskLevel == 'high'
                              ? 'High environmental hazard detected. Keep emergency kit & SOS ready.'
                              : riskLevel == 'moderate'
                                  ? 'Moderate weather hazard level. Monitor local advisories.'
                                  : 'Low environmental risk across flood, wildfire, and seismic indices.',
                          style: const TextStyle(
                            color: Palette.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Source: ${risk?['source'] ?? 'openweather'}',
                          style: const TextStyle(
                              color: Palette.textDim, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const SectionHeader('Disaster & Weather Map'),
            GlassCard(
              padding: const EdgeInsets.all(10),
              child: _buildDisasterMap(tileUrl),
            ),

            const SizedBox(height: 16),

            // Hazard Breakdown Meters
            const SectionHeader('Hazard Risk Breakdown'),
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _HazardMeterRow(
                    icon: Icons.water_rounded,
                    label: 'Flood & Precipitation Risk',
                    score: floodRisk,
                    color: Palette.blue,
                  ),
                  const SizedBox(height: 14),
                  _HazardMeterRow(
                    icon: Icons.local_fire_department_rounded,
                    label: 'Wildfire & Heatwave Risk',
                    score: fireRisk,
                    color: Palette.orange,
                  ),
                  const SizedBox(height: 14),
                  _HazardMeterRow(
                    icon: Icons.vibration_rounded,
                    label: 'Seismic / Earthquake Baseline',
                    score: earthquakeRisk,
                    color: Palette.amber,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Live OpenWeatherMap Telemetry
            const SectionHeader('OpenWeatherMap Live Telemetry'),
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Palette.teal.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.wb_cloudy_rounded,
                            color: Palette.teal, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              desc.toUpperCase(),
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Area: ${radar?['current']?['name'] ?? 'Local Sector'}',
                              style: const TextStyle(
                                  color: Palette.textDim, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _WeatherStatTile(
                          icon: Icons.thermostat_rounded,
                          label: 'Temperature',
                          value: '$tempC °C',
                          color: Palette.amber,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WeatherStatTile(
                          icon: Icons.water_drop_rounded,
                          label: 'Humidity',
                          value: '$humidity%',
                          color: Palette.blue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WeatherStatTile(
                          icon: Icons.air_rounded,
                          label: 'Wind Speed',
                          value: '$windMs m/s',
                          color: Palette.teal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Weather Radar Tile Status
            const SectionHeader('Precipitation Radar Tile Status'),
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: (tileUrl != null ? Palette.teal : Palette.amber)
                  .withOpacity(0.45),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.radar_rounded,
                        color: tileUrl != null ? Palette.teal : Palette.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tileUrl != null
                              ? 'OpenWeather Live Precipitation Tile Layer Active'
                              : 'Simulated Radar Mode (Baseline Heuristic)',
                          style: const TextStyle(
                            color: Palette.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              (tileUrl != null ? Palette.green : Palette.amber)
                                  .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          radarSource.toUpperCase(),
                          style: TextStyle(
                            color:
                                tileUrl != null ? Palette.green : Palette.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tileUrl ?? radarMsg ?? 'Radar precipitation overlay ready.',
                    style: const TextStyle(
                      color: Palette.textDim,
                      fontSize: 12,
                      fontFeatures: kTabular,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 2: BLOOD BANK
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildBloodBankSection() {
    return RefreshIndicator(
      color: Palette.teal,
      onRefresh: _loadBloodDonors,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          // Top CTA Banner
          GlassCard(
            padding: const EdgeInsets.all(16),
            color: Palette.red.withOpacity(0.10),
            borderColor: Palette.red.withOpacity(0.45),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Palette.red.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.bloodtype_rounded,
                      color: Palette.red, size: 26),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Community Blood Donor Network',
                        style: TextStyle(
                            color: Palette.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Find verified donors by blood type or register to save lives.',
                        style: TextStyle(color: Palette.textDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    backgroundColor: Palette.red,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: _showRegisterDonorDialog,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Become a Donor',
                      style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Blood Type Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final bg in _bloodGroups)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(bg),
                      selected: _selectedBloodGroup == bg,
                      selectedColor: Palette.red.withOpacity(0.22),
                      backgroundColor: Palette.surface,
                      side: BorderSide(
                        color: _selectedBloodGroup == bg
                            ? Palette.red
                            : Palette.outline,
                      ),
                      labelStyle: TextStyle(
                        color: _selectedBloodGroup == bg
                            ? Palette.red
                            : Palette.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() => _selectedBloodGroup = bg);
                        unawaited(_loadBloodDonors());
                      },
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // City Search Input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _citySearchCtrl,
                  onSubmitted: (_) => _loadBloodDonors(),
                  style: const TextStyle(color: Palette.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Filter by city (e.g. Bangalore, Mumbai, Delhi)…',
                    prefixIcon:
                        const Icon(Icons.search_rounded, color: Palette.teal),
                    suffixIcon: _citySearchCtrl.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _citySearchCtrl.clear();
                              unawaited(_loadBloodDonors());
                            },
                            icon: const Icon(Icons.clear_rounded,
                                color: Palette.textDim, size: 18),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(84, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: _loadingDonors ? null : _loadBloodDonors,
                child: const Text('Search'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          SectionHeader(
            'Matching Donors (${_donors.length})',
            action: _loadingDonors
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Palette.teal),
                  )
                : null,
          ),

          if (_donorsError != null)
            EmptyState(
              Icons.error_outline_rounded,
              'Could Not Search Blood Bank',
              _donorsError!,
              action: FilledButton(
                  onPressed: _loadBloodDonors, child: const Text('Retry')),
            )
          else if (!_loadingDonors && _donors.isEmpty)
            EmptyState(
              Icons.bloodtype_outlined,
              'No Matching Donors Found',
              'Try selecting "All" blood groups or clearing the city filter.',
              action: FilledButton.icon(
                onPressed: _showRegisterDonorDialog,
                icon: const Icon(Icons.favorite_rounded),
                label: const Text('Register as a Donor'),
              ),
            )
          else
            for (final d in _donors)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildDonorCard(d),
              ),
        ],
      ),
    );
  }

  Widget _buildDonorCard(Map<String, dynamic> d) {
    final name = '${d['name'] ?? 'Donor'}';
    final bt = '${d['bloodType'] ?? 'Not specified'}';
    final city = '${d['city'] ?? ''}';
    final phone = '${d['phone'] ?? ''}';
    final available = d['available'] == true;
    final units = d['units'] ?? 1;
    final lastDonated = '${d['lastDonated'] ?? ''}';

    return GlassCard(
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Palette.red.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Palette.red.withOpacity(0.45)),
            ),
            child: Text(
              bt,
              style: const TextStyle(
                color: Palette.red,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                fontFeatures: kTabular,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Palette.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (available ? Palette.green : Palette.textDim)
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (available ? Palette.green : Palette.textDim)
                              .withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        available ? 'AVAILABLE' : 'UNAVAILABLE',
                        style: TextStyle(
                          color: available ? Palette.green : Palette.textDim,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$city • $units unit(s)${lastDonated.isNotEmpty ? ' • Last: $lastDonated' : ''}',
                  style:
                      const TextStyle(color: Palette.textDim, fontSize: 12.5),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    phone,
                    style: const TextStyle(
                      color: Palette.teal,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      fontFeatures: kTabular,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Call Donor',
              style: IconButton.styleFrom(
                backgroundColor: Palette.green.withOpacity(0.15),
              ),
              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
              icon: const Icon(Icons.call_rounded,
                  color: Palette.green, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 3: VERIFIED NGOS
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildNgoSection() {
    return RefreshIndicator(
      color: Palette.teal,
      onRefresh: _loadNgos,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final cat in _ngoCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat.$2),
                      selected: _selectedNgoCategory == cat.$1,
                      selectedColor: Palette.teal.withOpacity(0.20),
                      backgroundColor: Palette.surface,
                      side: BorderSide(
                        color: _selectedNgoCategory == cat.$1
                            ? Palette.teal
                            : Palette.outline,
                      ),
                      labelStyle: TextStyle(
                        color: _selectedNgoCategory == cat.$1
                            ? Palette.teal
                            : Palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() => _selectedNgoCategory = cat.$1);
                        unawaited(_loadNgos());
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionHeader(
            'Verified Relief & Support NGOs (${_ngos.length})',
            action: _loadingNgos
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Palette.teal),
                  )
                : null,
          ),
          if (_ngosError != null)
            EmptyState(
              Icons.error_outline_rounded,
              'Could Not Load NGOs',
              _ngosError!,
              action: FilledButton(
                  onPressed: _loadNgos, child: const Text('Retry')),
            )
          else if (!_loadingNgos && _ngos.isEmpty)
            const EmptyState(
              Icons.volunteer_activism_outlined,
              'No NGOs in Category',
              'Switch to "All" to view all verified partner organizations.',
            )
          else
            for (final ngo in _ngos)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildNgoCard(ngo),
              ),
        ],
      ),
    );
  }

  Widget _buildNgoCard(Map<String, dynamic> ngo) {
    final name = '${ngo['name'] ?? 'NGO'}';
    final category = '${ngo['category'] ?? 'relief'}';
    final desc = '${ngo['description'] ?? ''}';
    final phone = '${ngo['phone'] ?? ''}';
    final website = '${ngo['website'] ?? ''}';
    final location = '${ngo['location'] ?? 'India'}';
    final verified = ngo['verified'] != false;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Palette.teal.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.handshake_rounded,
                    color: Palette.teal, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Palette.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (verified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Palette.green.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: Palette.green.withOpacity(0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded,
                                    color: Palette.green, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'VERIFIED',
                                  style: TextStyle(
                                    color: Palette.green,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          category.toUpperCase(),
                          style: const TextStyle(
                            color: Palette.blue,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '• $location',
                          style: const TextStyle(
                              color: Palette.textDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              desc,
              style: const TextStyle(
                  color: Palette.textDim, fontSize: 13, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              if (phone.isNotEmpty)
                InkWell(
                  onTap: () => launchUrl(Uri.parse('tel:$phone')),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.call_rounded,
                          size: 14, color: Palette.green),
                      const SizedBox(width: 5),
                      Text(
                        phone,
                        style: const TextStyle(
                          color: Palette.green,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ],
                  ),
                ),
              if (website.isNotEmpty)
                InkWell(
                  onTap: () => launchUrl(Uri.parse(website),
                      mode: LaunchMode.externalApplication),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.language_rounded,
                          size: 14, color: Palette.blue),
                      const SizedBox(width: 5),
                      Text(
                        website.replaceFirst(RegExp(r'^https?://'), ''),
                        style: const TextStyle(
                          color: Palette.blue,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Palette.teal,
                side: BorderSide(color: Palette.teal.withOpacity(0.45)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _showContactNgoDialog(ngo),
              icon:
                  const Icon(Icons.send_rounded, size: 16, color: Palette.teal),
              label: const Text(
                'Request Aid / Contact Coordinator',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 4: ABHA HEALTH ID (ABDM)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildAbhaSection() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        // Digital ABHA Health ID Card (shown when linked)
        if (_abhaNumber != null && _abhaNumber!.isNotEmpty) ...[
          GlassCard(
            padding: const EdgeInsets.all(20),
            borderColor: Palette.teal.withOpacity(0.6),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Palette.teal.withOpacity(0.22),
                Palette.blue.withOpacity(0.14),
                Palette.surface,
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Palette.teal.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.verified_user_rounded,
                          color: Palette.teal, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AYUSHMAN BHARAT DIGITAL MISSION',
                            style: TextStyle(
                              color: Palette.teal,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'ABHA Digital Health ID Card',
                            style: TextStyle(
                              color: Palette.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const StatusPill('normal', label: 'VERIFIED'),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'ABHA NUMBER',
                  style: TextStyle(
                    color: Palette.textDim,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _abhaNumber!,
                        style: const TextStyle(
                          color: Palette.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy ABHA ID',
                      onPressed: () {
                        unawaited(Clipboard.setData(
                            ClipboardData(text: _abhaNumber!)));
                        showSnack(
                            context, 'ABHA Health ID copied to clipboard.');
                      },
                      icon: const Icon(Icons.copy_rounded,
                          color: Palette.teal, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Holder: ${_nameCtrl.text.trim().isEmpty ? 'Jeevan Patient' : _nameCtrl.text.trim()}',
                      style: const TextStyle(
                          color: Palette.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Blood: $_profileBloodGroup',
                      style: const TextStyle(
                          color: Palette.teal,
                          fontSize: 13,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],

        const SectionHeader('Create / Link ABHA ID via Aadhaar OTP'),
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Step 1: Enter 12-Digit Aadhaar Number',
                style: TextStyle(
                    color: Palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Generates an ABDM sandbox OTP to link your Ayushman Bharat Digital Health Account (XX-XXXX-XXXX-XXXX) with Jeevan.',
                style: TextStyle(
                    color: Palette.textDim, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _aadhaarCtrl,
                keyboardType: TextInputType.number,
                maxLength: 12,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  color: Palette.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontFeatures: kTabular,
                ),
                decoration: const InputDecoration(
                  labelText: '12-Digit Aadhaar Number',
                  hintText: '123456789012',
                  counterText: '',
                  prefixIcon:
                      Icon(Icons.fingerprint_rounded, color: Palette.teal),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _generatingOtp ? null : _generateAbdmOtp,
                icon: _generatingOtp
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF042F2A)),
                      )
                    : const Icon(Icons.sms_rounded),
                label: Text(_generatingOtp
                    ? 'Requesting OTP…'
                    : 'Generate Aadhaar OTP'),
              ),
              if (_txnId != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Divider(color: Palette.outline, height: 1),
                ),
                const Text(
                  'Step 2: Verify 6-Digit OTP',
                  style: TextStyle(
                      color: Palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                if (_otpHintMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Palette.blue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Palette.blue.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            color: Palette.blue, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _otpHintMessage!,
                            style: const TextStyle(
                                color: Palette.text,
                                fontSize: 12,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    color: Palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    fontFeatures: kTabular,
                  ),
                  decoration: const InputDecoration(
                    labelText: '6-Digit OTP',
                    hintText: '123456',
                    counterText: '',
                    prefixIcon:
                        Icon(Icons.lock_clock_rounded, color: Palette.teal),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _verifyingOtp ? null : _verifyAbdmOtp,
                  icon: _verifyingOtp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF042F2A)),
                        )
                      : const Icon(Icons.verified_rounded),
                  label: Text(_verifyingOtp
                      ? 'Verifying…'
                      : 'Verify OTP & Generate ABHA ID'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 5: EMERGENCY MEDICAL ID & QR PROFILE
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildEmergencyProfileSection() {
    final api = ref.read(apiProvider);
    final publicPath = _uid.isNotEmpty
        ? '/api/emergency-summary/$_uid'
        : '/api/emergency-summary/{uid}';
    final fullPublicUrl = '${api.baseUrl}$publicPath';

    return RefreshIndicator(
      color: Palette.teal,
      onRefresh: _loadEmergencySummary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
        children: [
          // Public Responder Emergency URL & QR Card
          GlassCard(
            padding: const EdgeInsets.all(18),
            borderColor: Palette.teal.withOpacity(0.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Palette.teal.withOpacity(0.14),
                Palette.surface,
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Palette.teal.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: Palette.teal.withOpacity(0.45)),
                      ),
                      child: const Icon(Icons.qr_code_2_rounded,
                          color: Palette.teal, size: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FIRST RESPONDER EMERGENCY URL',
                            style: TextStyle(
                              color: Palette.teal,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            publicPath,
                            style: const TextStyle(
                              color: Palette.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: kTabular,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Paramedics and ER physicians can open this endpoint without login to view your blood group, allergies, chronic conditions, and emergency contacts.',
                  style: TextStyle(
                      color: Palette.textDim, fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Palette.teal,
                          side:
                              BorderSide(color: Palette.teal.withOpacity(0.45)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13)),
                        ),
                        onPressed: () {
                          unawaited(Clipboard.setData(
                              ClipboardData(text: fullPublicUrl)));
                          showSnack(context, 'Responder Emergency URL copied!');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy URL'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Palette.blue,
                          side:
                              BorderSide(color: Palette.blue.withOpacity(0.45)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13)),
                        ),
                        onPressed: _uid.isEmpty
                            ? null
                            : () => launchUrl(Uri.parse(fullPublicUrl),
                                mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Open Public View'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          SectionHeader(
            'Medical ID Details',
            action: _loadingSummary
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Palette.teal),
                  )
                : null,
          ),

          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Palette.text),
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.badge_outlined, color: Palette.teal),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _profileBloodGroup,
                        dropdownColor: Palette.surfaceHi,
                        style: const TextStyle(
                            color: Palette.text, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(
                          labelText: 'Blood Group',
                          prefixIcon: Icon(Icons.bloodtype_outlined,
                              color: Palette.red),
                        ),
                        items: _bloodGroups
                            .where((g) => g != 'All')
                            .map((g) =>
                                DropdownMenuItem(value: g, child: Text(g)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _profileBloodGroup = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _dobCtrl,
                        style: const TextStyle(color: Palette.text),
                        decoration: const InputDecoration(
                          labelText: 'Date of Birth',
                          hintText: 'YYYY-MM-DD',
                          prefixIcon:
                              Icon(Icons.cake_outlined, color: Palette.amber),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _allergiesCtrl,
                  style: const TextStyle(color: Palette.text),
                  decoration: const InputDecoration(
                    labelText: 'Allergies (comma-separated)',
                    hintText: 'Penicillin, Peanuts, Latex',
                    prefixIcon:
                        Icon(Icons.warning_amber_rounded, color: Palette.red),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _conditionsCtrl,
                  style: const TextStyle(color: Palette.text),
                  decoration: const InputDecoration(
                    labelText: 'Chronic Conditions (comma-separated)',
                    hintText: 'Hypertension, Type 2 Diabetes, Asthma',
                    prefixIcon:
                        Icon(Icons.monitor_heart_outlined, color: Palette.blue),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _medicationsCtrl,
                  style: const TextStyle(color: Palette.text),
                  decoration: const InputDecoration(
                    labelText: 'Current Medications (comma-separated)',
                    hintText: 'Metformin 500mg, Amlodipine 5mg',
                    prefixIcon:
                        Icon(Icons.medication_outlined, color: Palette.teal),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          SectionHeader(
            'Emergency Contacts (${_contacts.length})',
            action: TextButton.icon(
              onPressed: _showAddContactDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded,
                  size: 18, color: Palette.teal),
              label: const Text(
                'Add Contact',
                style:
                    TextStyle(color: Palette.teal, fontWeight: FontWeight.w700),
              ),
            ),
          ),

          if (_contacts.isEmpty)
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.contact_phone_outlined,
                      color: Palette.textDim),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'No emergency contacts added yet. Add family or caregiver numbers for SOS alerts.',
                      style: TextStyle(color: Palette.textDim, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    onPressed: _showAddContactDialog,
                    icon: const Icon(Icons.add_circle_outline_rounded,
                        color: Palette.teal),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < _contacts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Palette.teal.withOpacity(0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_rounded,
                            color: Palette.teal, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_contacts[i]['name']} (${_contacts[i]['relationship'] ?? 'Family'})',
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if ((_contacts[i]['phone'] ?? '').isNotEmpty)
                                  _contacts[i]['phone']!,
                                if ((_contacts[i]['email'] ?? '').isNotEmpty)
                                  _contacts[i]['email']!,
                              ].join(' • '),
                              style: const TextStyle(
                                  color: Palette.textDim, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove Contact',
                        onPressed: () {
                          setState(() {
                            final next =
                                List<Map<String, String>>.from(_contacts)
                                  ..removeAt(i);
                            _contacts = next;
                          });
                        },
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Palette.red, size: 20),
                      ),
                    ],
                  ),
                ),
              ),

          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed: _savingSummary ? null : _saveEmergencySummary,
            icon: _savingSummary
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF042F2A)),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_savingSummary
                ? 'Saving Profile…'
                : 'Save Emergency Medical ID'),
          ),
        ],
      ),
    );
  }
}

class _HazardMeterRow extends StatelessWidget {
  const _HazardMeterRow({
    required this.icon,
    required this.label,
    required this.score,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                    color: Palette.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '$clamped / 100',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFeatures: kTabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: clamped / 100.0,
            minHeight: 8,
            backgroundColor: Palette.bg,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _WeatherStatTile extends StatelessWidget {
  const _WeatherStatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Palette.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.outline),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Palette.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              fontFeatures: kTabular,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Palette.textDim, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
