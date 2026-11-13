import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/medication_reminder_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class MedicationsScreen extends ConsumerStatefulWidget {
  const MedicationsScreen({super.key});

  @override
  ConsumerState<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends ConsumerState<MedicationsScreen> {
  bool _loading = true;
  String? _ringingMedId;
  String? _deletingMedId;
  String? _advisingMedId;
  String? _notifyingMedId;
  List<Map<String, dynamic>> _medications = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadMedications());
  }

  Future<void> _loadMedications() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(apiProvider).listMedications();
      if (!mounted) return;
      setState(() {
        _medications = list;
        _loading = false;
      });
      try {
        await MedicationReminderService.sync(list);
      } catch (_) {
        // Keep the medication list usable when notifications are unavailable.
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnack(context, 'Failed to load medications: $e', error: true);
    }
  }

  Future<void> _ringWatchLed(Map<String, dynamic> med, String deviceId) async {
    final id = '${med['id'] ?? med['name']}';
    final name = (med['name'] as String?)?.trim().isNotEmpty == true
        ? med['name'] as String
        : 'Scheduled Dose';
    final times =
        (med['reminderTimes'] as List?)?.whereType<String>().toList() ??
            const ['08:00'];
    final slot = times.isNotEmpty ? times.first : '08:00';

    setState(() => _ringingMedId = id);
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.mediumImpact();
    try {
      await ref.read(apiProvider).triggerReminder(deviceId, name, slot);
      await ref.read(devicesProvider.notifier).refresh();
      if (mounted) {
        showSnack(
          context,
          'VitaWatch ($deviceId) reminder LED & buzzer triggered for $name ($slot)!',
        );
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Could not trigger VitaWatch reminder: $e',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _ringingMedId = null);
    }
  }

  Future<void> _deleteMedication(Map<String, dynamic> med) async {
    final id = '${med['id'] ?? ''}';
    if (id.isEmpty) return;
    setState(() => _deletingMedId = id);
    try {
      await ref.read(apiProvider).deleteMedication(id);
      if (!mounted) return;
      setState(() {
        _medications = _medications.where((m) => '${m['id']}' != id).toList();
      });
      try {
        await MedicationReminderService.sync(_medications);
      } catch (_) {}
      showSnack(context, 'Removed ${med['name'] ?? 'medication'}.');
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Could not delete medication: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _deletingMedId = null);
    }
  }

  Future<void> _askAiPharmacistMissedDose(Map<String, dynamic> med) async {
    final id = '${med['id'] ?? med['name']}';
    final name = (med['name'] as String?) ?? 'Medication';
    final dosage = (med['dosage'] as String?) ?? '';
    final times = (med['reminderTimes'] as List?)?.map((e) => '$e').toList() ??
        const ['08:00'];
    final slot = times.isNotEmpty ? times.first : '08:00';

    setState(() => _advisingMedId = id);
    try {
      final res = await ref.read(apiProvider).medicationAdvice(
            drugName: name,
            dosage: dosage,
            scheduledTime: slot,
            missedBy: '2 hours',
          );
      if (!mounted) return;
      final adviceText =
          '${res['advice'] ?? res['recommendation'] ?? res['response'] ?? 'Take the missed dose as soon as you remember unless it is nearly time for your next scheduled dose. Do not double the dose.'}'
              .trim();
      final actionLabel =
          '${res['action'] ?? 'CLINICAL PHARMACIST GUIDANCE'}'.toUpperCase();
      final warnings = ((res['warnings'] ?? res['precautions']) as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [];

      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Palette.teal.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.medical_information_rounded,
                        color: Palette.teal, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Pharmacist • $name ($dosage)',
                          style: const TextStyle(
                              color: Palette.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Scheduled slot: $slot • $actionLabel',
                          style: const TextStyle(
                              color: Palette.teal,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon:
                        const Icon(Icons.close_rounded, color: Palette.textDim),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Palette.surfaceHi,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Palette.teal.withValues(alpha: 0.35)),
                ),
                child: Text(
                  adviceText,
                  style: const TextStyle(
                      color: Palette.text, fontSize: 13.8, height: 1.45),
                ),
              ),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final w in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 15, color: Palette.amber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            w,
                            style: const TextStyle(
                                color: Palette.textDim, fontSize: 12.5),
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
    } catch (e) {
      if (mounted)
        showSnack(context, 'Could not fetch pharmacist advice: $e',
            error: true);
    } finally {
      if (mounted) setState(() => _advisingMedId = null);
    }
  }

  Future<void> _notifyCaregiverWhatsApp(Map<String, dynamic> med) async {
    final id = '${med['id'] ?? med['name']}';
    final name = (med['name'] as String?) ?? 'Medication';
    final dosage = (med['dosage'] as String?) ?? '';
    final times = (med['reminderTimes'] as List?)?.map((e) => '$e').toList() ??
        const ['08:00'];
    final slot = times.isNotEmpty ? times.first : '08:00';

    final phoneCtrl = TextEditingController(text: '+919876543210');
    bool taken = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Palette.surfaceHi,
          title: const Text('Notify Caregiver on WhatsApp'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send real-time WhatsApp & SMS dose status alert for $name ($dosage • $slot).',
                style: const TextStyle(color: Palette.textDim, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Caregiver WhatsApp / Phone',
                  hintText: '+919876543210',
                  prefixIcon: Icon(Icons.phone_rounded, color: Palette.green),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Dose Taken'),
                      selected: taken,
                      selectedColor: Palette.green.withValues(alpha: 0.22),
                      onSelected: (_) => setDialogState(() => taken = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Dose Missed'),
                      selected: !taken,
                      selectedColor: Palette.red.withValues(alpha: 0.22),
                      onSelected: (_) => setDialogState(() => taken = false),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: Palette.textDim)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 42),
                backgroundColor: Palette.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Send Alert'),
            ),
          ],
        ),
      ),
    );

    final phone = phoneCtrl.text.trim();
    phoneCtrl.dispose();
    if (confirmed != true || phone.isEmpty || !mounted) return;

    setState(() => _notifyingMedId = id);
    try {
      await ref.read(apiProvider).sendMedicationStatusAlert(
            phone: phone,
            medicationName: name,
            dosage: dosage,
            time: slot,
            taken: taken,
          );
      if (mounted) {
        showSnack(
          context,
          'Caregiver WhatsApp alert sent to $phone (${taken ? "DOSE TAKEN" : "DOSE MISSED"})!',
        );
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Could not send caregiver alert: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _notifyingMedId = null);
    }
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => _AddMedicationSheet(
        onAdd: ({
          required String name,
          required String dosage,
          required String frequency,
          required List<String> reminderTimes,
          String? doctorName,
        }) async {
          await ref.read(apiProvider).addMedication(
                name: name,
                dosage: dosage,
                frequency: frequency,
                reminderTimes: reminderTimes,
                doctorName: doctorName,
              );
        },
      ),
    );
    if (added == true && mounted) {
      await _loadMedications();
      if (mounted) showSnack(context, 'Medication added to schedule.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final devicesState = ref.watch(devicesProvider);
    final activeDeviceId =
        (devicesState.selected != null && devicesState.selected!.isNotEmpty)
            ? devicesState.selected!
            : 'esp32_jeevancare_01';

    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: canPop
          ? AppBar(
              title: const Text('💊 Medications & Dose Tracker'),
              actions: [
                IconButton(
                  tooltip: 'Refresh Medications',
                  onPressed: _loading ? null : _loadMedications,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Palette.red,
        foregroundColor: Colors.white,
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Medication',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        color: Palette.red,
        backgroundColor: Palette.surfaceHi,
        onRefresh: _loadMedications,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 100),
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
                    child: const Text('💊', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Medications',
                          style: TextStyle(
                            color: Palette.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '7-Day Adherence • VitaWatch LED • AI Pharmacist',
                          style:
                              TextStyle(color: Palette.textDim, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh Medications',
                    onPressed: _loading ? null : _loadMedications,
                    icon:
                        const Icon(Icons.refresh_rounded, color: Palette.text),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            // 7-Day Dose Adherence Calendar Strip (Matches MedicationsPage.tsx)
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '📅 7-Day Dose Adherence Tracker',
                        style: TextStyle(
                          color: Palette.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Palette.redLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _medications.isEmpty
                              ? '0% Adherence'
                              : '100% Adherence',
                          style: const TextStyle(
                            color: Palette.red,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final day in const [
                        'Sun',
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat'
                      ])
                        Column(
                          children: [
                            Text(
                              day,
                              style: const TextStyle(
                                color: Palette.textDim,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: day == 'Sun'
                                    ? Palette.red
                                    : Palette.surfaceHi,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: day == 'Sun'
                                      ? Palette.red
                                      : Palette.outline,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: day == 'Sun'
                                    ? Colors.white
                                    : Palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // VitaWatch Hardware Reminder Link Card
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: Palette.teal.withValues(alpha: 0.45),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Palette.amber.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Palette.amber,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VitaWatch Reminder Target: $activeDeviceId',
                          style: const TextStyle(
                            color: Palette.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Tap "Ring VitaWatch LED" on any prescription to light up the physical ESP32 reminder LED & alert the patient.',
                          style: TextStyle(
                            color: Palette.textDim,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            SectionHeader(
              'Active Prescriptions (${_medications.length})',
              action: TextButton.icon(
                onPressed: _openAddSheet,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: const Text('New Dose'),
              ),
            ),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 42),
                child: Center(
                  child: CircularProgressIndicator(color: Palette.teal),
                ),
              )
            else if (_medications.isEmpty)
              EmptyState(
                Icons.medication_liquid_rounded,
                'No Medications Scheduled',
                'Add daily prescriptions, reminder slots, and prescribing doctors. You can trigger the physical VitaWatch LED reminder anytime.',
                action: FilledButton.icon(
                  onPressed: _openAddSheet,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add First Medication'),
                ),
              )
            else
              ..._medications.map((med) {
                final id = '${med['id'] ?? med['name']}';
                final name = (med['name'] as String?) ?? 'Medication';
                final dosage = (med['dosage'] as String?) ?? '';
                final frequency = (med['frequency'] as String?) ?? 'Once daily';
                final doctorName = (med['doctorName'] as String?)?.trim();
                final adherence =
                    (med['adherenceScore'] as num?)?.toInt() ?? 100;
                final times = (med['reminderTimes'] as List?)
                        ?.map((e) => '$e')
                        .where((s) => s.isNotEmpty)
                        .toList() ??
                    const ['08:00'];

                final isRinging = _ringingMedId == id;
                final isDeleting = _deletingMedId == id;
                final isAdvising = _advisingMedId == id;
                final isNotifying = _notifyingMedId == id;
                final adherenceColor = adherence >= 85
                    ? Palette.green
                    : adherence >= 60
                        ? Palette.amber
                        : Palette.red;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: GlassCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Palette.teal.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.medication_rounded,
                                color: Palette.teal,
                                size: 24,
                              ),
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
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: adherenceColor.withValues(
                                              alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                            color: adherenceColor.withValues(
                                                alpha: 0.45),
                                          ),
                                        ),
                                        child: Text(
                                          '$adherence% Adherence',
                                          style: TextStyle(
                                            color: adherenceColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            fontFeatures: kTabular,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$dosage • $frequency',
                                    style: const TextStyle(
                                      color: Palette.teal,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (doctorName != null &&
                                      doctorName.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      'Prescribed by Dr. ${doctorName.replaceFirst(RegExp(r'^[Dd]r\.?\s*'), '')}',
                                      style: const TextStyle(
                                        color: Palette.textDim,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete Medication',
                              onPressed: isDeleting
                                  ? null
                                  : () => _deleteMedication(med),
                              icon: isDeleting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Palette.red,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Palette.red,
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Reminder time chips
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final slot in times)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Palette.surfaceHi,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Palette.outline),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.schedule_rounded,
                                      size: 13,
                                      color: Palette.amber,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      slot,
                                      style: const TextStyle(
                                        color: Palette.text,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: kTabular,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Prominent Ring VitaWatch LED button
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              backgroundColor:
                                  Palette.amber.withValues(alpha: 0.16),
                              foregroundColor: Palette.amber,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                    color:
                                        Palette.amber.withValues(alpha: 0.45)),
                              ),
                            ),
                            onPressed: isRinging
                                ? null
                                : () => _ringWatchLed(med, activeDeviceId),
                            icon: isRinging
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Palette.amber,
                                    ),
                                  )
                                : const Icon(Icons.lightbulb_circle_rounded,
                                    size: 20),
                            label: Text(
                              isRinging
                                  ? 'Ringing VitaWatch LED…'
                                  : 'Ring VitaWatch LED (${times.first})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Missed Dose AI Pharmacist + Caregiver WhatsApp Alert buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Palette.teal,
                                  side: BorderSide(
                                      color:
                                          Palette.teal.withValues(alpha: 0.45)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 11, horizontal: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: isAdvising
                                    ? null
                                    : () => _askAiPharmacistMissedDose(med),
                                icon: isAdvising
                                    ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Palette.teal,
                                        ),
                                      )
                                    : const Icon(Icons.psychology_alt_rounded,
                                        size: 17, color: Palette.teal),
                                label: const Text(
                                  'Missed Dose? Ask AI Pharmacist',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Palette.green,
                                  side: BorderSide(
                                      color: Palette.green
                                          .withValues(alpha: 0.45)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 11, horizontal: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: isNotifying
                                    ? null
                                    : () => _notifyCaregiverWhatsApp(med),
                                icon: isNotifying
                                    ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Palette.green,
                                        ),
                                      )
                                    : const Icon(Icons.chat_rounded,
                                        size: 16, color: Palette.green),
                                label: const Text(
                                  'Notify Caregiver on WhatsApp',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _AddMedicationSheet extends StatefulWidget {
  const _AddMedicationSheet({required this.onAdd});

  final Future<void> Function({
    required String name,
    required String dosage,
    required String frequency,
    required List<String> reminderTimes,
    String? doctorName,
  }) onAdd;

  @override
  State<_AddMedicationSheet> createState() => _AddMedicationSheetState();
}

class _AddMedicationSheetState extends State<_AddMedicationSheet> {
  final _nameCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _timesCtrl = TextEditingController(text: '08:00, 20:00');
  final _doctorCtrl = TextEditingController();
  String _frequency = 'Once daily';
  bool _saving = false;

  static const _frequencies = <String>[
    'Once daily',
    'Twice daily',
    'Three times daily',
    'Before meals',
    'At bedtime',
    'As needed (PRN)',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _timesCtrl.dispose();
    _doctorCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final dosage = _dosageCtrl.text.trim();
    if (name.isEmpty || dosage.isEmpty) {
      showSnack(context, 'Please enter both medication name and dosage.',
          error: true);
      return;
    }
    final reminderTimes = _timesCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (reminderTimes.isEmpty) {
      reminderTimes.add('08:00');
    }

    setState(() => _saving = true);
    try {
      await widget.onAdd(
        name: name,
        dosage: dosage,
        frequency: _frequency,
        reminderTimes: reminderTimes,
        doctorName:
            _doctorCtrl.text.trim().isEmpty ? null : _doctorCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Failed to add medication: $e', error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Palette.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.medication_rounded,
                      color: Palette.teal, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Add Medication & Watch Reminder',
                    style: TextStyle(
                      color: Palette.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded, color: Palette.textDim),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Medication Name *',
                hintText: 'e.g. Metformin, Atorvastatin, Amlodipine',
                prefixIcon: Icon(Icons.local_pharmacy_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dosageCtrl,
              decoration: const InputDecoration(
                labelText: 'Dosage *',
                hintText: 'e.g. 500 mg, 10 mg (1 tablet)',
                prefixIcon: Icon(Icons.scale_rounded),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _frequency,
              isExpanded: true,
              dropdownColor: Palette.surfaceHi,
              decoration: const InputDecoration(
                labelText: 'Frequency',
                prefixIcon: Icon(Icons.repeat_rounded),
              ),
              items: _frequencies
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _frequency = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timesCtrl,
              decoration: const InputDecoration(
                labelText: 'Reminder Times (comma-separated 24h)',
                hintText: '08:00, 14:00, 20:00',
                prefixIcon: Icon(Icons.access_time_filled_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _doctorCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Prescribing Doctor (Optional)',
                hintText: 'e.g. Dr. Ramesh Rao',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF042F2A),
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Saving…' : 'Save Medication'),
            ),
          ],
        ),
      ),
    );
  }
}
