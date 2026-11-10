import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/markdown_lite.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  static const _quickPrompts = <String>[
    'How do I perform adult CPR?',
    'Analyze my live VitaWatch vitals',
    'First aid for severe bleeding',
    'Warning signs of stroke (BE-FAST)',
    'What if I missed my medication dose?',
  ];

  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;

  @override
  void dispose() {
    _speech.stop();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _sendPrompt([String? preset]) {
    final text = (preset ?? _inputCtrl.text).trim();
    if (text.isEmpty) return;
    if (preset == null) _inputCtrl.clear();
    if (_listening) {
      _speech.stop();
      setState(() => _listening = false);
    }
    ref.read(chatProvider.notifier).send(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleVoice() async {
    try {
      if (_listening) {
        await _speech.stop();
        if (mounted) setState(() => _listening = false);
        return;
      }
      final available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!available) {
        if (mounted) {
          showSnack(context, 'Speech recognition is unavailable on this device.', error: true);
        }
        return;
      }
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _inputCtrl.text = result.recognizedWords;
            _inputCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: _inputCtrl.text.length),
            );
          });
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _listening = false);
        showSnack(context, 'Could not start voice input.', error: true);
      }
    }
  }

  void _openSourcesSheet(List<Source> sources) {
    if (sources.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Palette.outline,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.menu_book_rounded, color: Palette.teal, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Clinical Sources (${sources.length})',
                    style: const TextStyle(
                      color: Palette.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: sources.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, idx) {
                    final s = sources[idx];
                    return GlassCard(
                      padding: const EdgeInsets.all(16),
                      color: Palette.bg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Palette.teal.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Palette.teal.withOpacity(0.45)),
                                ),
                                child: Text(
                                  '[${s.n}]',
                                  style: const TextStyle(
                                    color: Palette.teal,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: kTabular,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  s.title,
                                  style: const TextStyle(
                                    color: Palette.text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              if (s.private)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Palette.amber.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: Palette.amber.withOpacity(0.4)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock_rounded, size: 12, color: Palette.amber),
                                      SizedBox(width: 4),
                                      Text(
                                        'Private Doc',
                                        style: TextStyle(
                                          color: Palette.amber,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          if (s.heading.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              s.heading,
                              style: const TextStyle(
                                color: Palette.blue,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            s.snippet,
                            style: const TextStyle(
                              color: Palette.textDim,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPrivateDocsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _PrivateDocsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final streaming = messages.isNotEmpty && messages.last.streaming;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Jeevan AI Assistant',
              style: TextStyle(color: Palette.text, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              'Hybrid Transformer RAG + Live Vitals Context',
              style: TextStyle(color: Palette.textDim, fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _openPrivateDocsSheet,
            icon: const Icon(Icons.folder_shared_outlined, size: 18, color: Palette.teal),
            label: const Text(
              'My Medical Docs',
              style: TextStyle(color: Palette.teal, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          if (messages.isNotEmpty)
            IconButton(
              onPressed: () => ref.read(chatProvider.notifier).clear(),
              tooltip: 'Clear',
              icon: const Icon(Icons.delete_sweep_outlined, color: Palette.textDim),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const EmptyState(
                          Icons.health_and_safety_outlined,
                          'Clinical RAG Health Assistant',
                          'Grounded in verified first-aid & triage protocols, your private medical records, and live VitaWatch sensor telemetry.',
                        ),
                        const SizedBox(height: 22),
                        const SectionHeader('Quick Clinical Prompts'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 10,
                          children: [
                            for (final prompt in _quickPrompts)
                              ActionChip(
                                backgroundColor: Palette.surface,
                                side: const BorderSide(color: Palette.outline),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                avatar: const Icon(Icons.bolt_rounded, size: 16, color: Palette.teal),
                                label: Text(
                                  prompt,
                                  style: const TextStyle(
                                    color: Palette.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: () => _sendPrompt(prompt),
                              ),
                          ],
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (ctx, i) {
                      final m = messages[i];
                      if (m.fromUser) {
                        return _UserBubble(text: m.text);
                      }
                      return _AssistantBubble(
                        message: m,
                        onOpenSources: () => _openSourcesSheet(m.sources),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: const BoxDecoration(
              color: Palette.surface,
              border: Border(top: BorderSide(color: Palette.outline)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  IconButton(
                    onPressed: _toggleVoice,
                    tooltip: _listening ? 'Stop listening' : 'Voice input',
                    style: IconButton.styleFrom(
                      backgroundColor: _listening ? Palette.red.withOpacity(0.18) : Palette.surfaceHi,
                    ),
                    icon: Icon(
                      _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _listening ? Palette.red : Palette.teal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendPrompt(),
                      style: const TextStyle(color: Palette.text, fontSize: 14.5),
                      decoration: InputDecoration(
                        hintText: _listening ? 'Listening…' : 'Ask about symptoms, first aid, or vitals…',
                        fillColor: Palette.bg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (streaming)
                    IconButton(
                      onPressed: () => ref.read(chatProvider.notifier).cancel(),
                      tooltip: 'Stop',
                      style: IconButton.styleFrom(
                        backgroundColor: Palette.red.withOpacity(0.18),
                      ),
                      icon: const Icon(Icons.stop_rounded, color: Palette.red),
                    )
                  else
                    IconButton(
                      onPressed: _sendPrompt,
                      tooltip: 'Send',
                      style: IconButton.styleFrom(
                        backgroundColor: Palette.teal,
                      ),
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF042F2A), size: 20),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Palette.teal.withOpacity(0.18),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
            border: Border.all(color: Palette.teal.withOpacity(0.45)),
          ),
          child: Text(
            text,
            style: const TextStyle(color: Palette.text, fontSize: 14.5, height: 1.45),
          ),
        ),
      ),
    );
  }
}

class _AssistantBubble extends ConsumerWidget {
  const _AssistantBubble({required this.message, required this.onOpenSources});

  final ChatMessage message;
  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: message.emergency ? Palette.red.withOpacity(0.6) : Palette.outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.emergency) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Palette.red.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Palette.red.withOpacity(0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Palette.red, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Medical Emergency Detected — Act Immediately',
                                style: TextStyle(
                                  color: Palette.red,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Palette.red,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(40),
                                ),
                                onPressed: () => launchUrl(Uri(scheme: 'tel', path: '112')),
                                icon: const Icon(Icons.call_rounded, size: 18),
                                label: const Text('Call 112'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Palette.red,
                                  side: const BorderSide(color: Palette.red),
                                  minimumSize: const Size.fromHeight(40),
                                ),
                                onPressed: () => ref.read(sosProvider.notifier).trigger(source: 'assistant_emergency'),
                                icon: const Icon(Icons.sos_rounded, size: 18),
                                label: const Text('Trigger SOS'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (message.text.isEmpty && message.streaming)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Palette.teal),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Retrieving clinical guidelines…',
                        style: TextStyle(color: Palette.textDim, fontSize: 13.5),
                      ),
                    ],
                  )
                else
                  MarkdownLite(
                    message.text,
                    onCitationTap: (_) => onOpenSources(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (message.fallback)
                _MetaBadge(
                  icon: Icons.offline_bolt_outlined,
                  label: 'Offline KB Extractive',
                  color: Palette.amber,
                )
              else if (message.firstTokenMs != null)
                _MetaBadge(
                  icon: Icons.bolt_rounded,
                  label: '⚡ First token ${message.firstTokenMs} ms',
                  color: Palette.teal,
                ),
              if (message.sources.isNotEmpty)
                GestureDetector(
                  onTap: onOpenSources,
                  child: _MetaBadge(
                    icon: Icons.library_books_outlined,
                    label: '${message.sources.length} clinical sources',
                    color: Palette.blue,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              fontFeatures: kTabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivateDocsSheet extends ConsumerStatefulWidget {
  const _PrivateDocsSheet();

  @override
  ConsumerState<_PrivateDocsSheet> createState() => _PrivateDocsSheetState();
}

class _PrivateDocsSheetState extends ConsumerState<_PrivateDocsSheet> {
  final _titleCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  int? _chunks;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadChunks();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChunks() async {
    try {
      final count = await ref.read(apiProvider).documentChunks();
      if (mounted) setState(() => _chunks = count);
    } catch (_) {
      if (mounted) setState(() => _chunks = 0);
    }
  }

  Future<void> _addDoc() async {
    final title = _titleCtrl.text.trim();
    final text = _textCtrl.text.trim();
    if (title.isEmpty || text.isEmpty) {
      showSnack(context, 'Enter both a document title and clinical notes.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final count = await ref.read(apiProvider).addDocument(title, text);
      _titleCtrl.clear();
      _textCtrl.clear();
      if (mounted) {
        setState(() => _chunks = count);
        showSnack(context, 'Indexed into your private RAG vault ($count chunks).');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not index document: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearDocs() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).clearDocuments();
      if (mounted) {
        setState(() => _chunks = 0);
        showSnack(context, 'Cleared all private RAG documents.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not clear documents: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Palette.outline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.lock_person_rounded, color: Palette.teal, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Private Medical Documents (RAG)',
                    style: TextStyle(color: Palette.text, fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Palette.teal.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _chunks == null ? '… chunks' : '$_chunks chunks indexed',
                    style: const TextStyle(
                      color: Palette.teal,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: kTabular,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Add prescriptions, allergies, or lab reports. These are isolated to your account and retrieved automatically during assistant answers.',
              style: TextStyle(color: Palette.textDim, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Palette.text),
              decoration: const InputDecoration(
                labelText: 'Document Title (e.g. Cardiology Prescription, Allergies)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textCtrl,
              minLines: 3,
              maxLines: 5,
              style: const TextStyle(color: Palette.text),
              decoration: const InputDecoration(
                labelText: 'Content (medications, dosages, known allergies, lab values)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _addDoc,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('Index Private Document'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy || (_chunks ?? 0) == 0 ? null : _clearDocs,
              style: OutlinedButton.styleFrom(
                foregroundColor: Palette.red,
                side: BorderSide(color: Palette.red.withOpacity(0.5)),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Clear Private Docs'),
            ),
          ],
        ),
      ),
    );
  }
}
