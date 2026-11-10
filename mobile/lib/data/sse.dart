import 'dart:async';
import 'dart:convert';

import 'models.dart';

/// Parsed server-sent events from the assistant endpoint.
sealed class ChatEvent {}

class EmergencyEvent extends ChatEvent {}

class MetaEvent extends ChatEvent {
  MetaEvent(this.sources, this.retrievalMs, this.emergency);
  final List<Source> sources;
  final int retrievalMs;
  final bool emergency;
}

class TokenEvent extends ChatEvent {
  TokenEvent(this.text);
  final String text;
}

class TimingEvent extends ChatEvent {
  TimingEvent(this.firstTokenMs);
  final int firstTokenMs;
}

class FallbackEvent extends ChatEvent {}

class DoneEvent extends ChatEvent {
  DoneEvent(this.totalMs);
  final int totalMs;
}

/// Incremental SSE parser. Feed decoded text chunks; get complete events out. Pure => unit-testable.
class SseParser {
  String _pending = '';
  String _event = 'message';
  final _data = StringBuffer();

  List<ChatEvent> add(String chunk) {
    _pending += chunk;
    final out = <ChatEvent>[];
    int nl;
    while ((nl = _pending.indexOf('\n')) >= 0) {
      final line = _pending.substring(0, nl).replaceAll('\r', '');
      _pending = _pending.substring(nl + 1);
      if (line.isEmpty) {
        final e = _dispatch();
        if (e != null) out.add(e);
      } else if (line.startsWith('event:')) {
        _event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        if (_data.isNotEmpty) _data.write('\n');
        _data.write(line.substring(5).trimLeft());
      }
    }
    return out;
  }

  ChatEvent? _dispatch() {
    final name = _event;
    final raw = _data.toString();
    _event = 'message';
    _data.clear();
    if (raw.isEmpty) return null;
    Map<String, dynamic> d;
    try {
      d = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    switch (name) {
      case 'emergency':
        return EmergencyEvent();
      case 'meta':
        return MetaEvent(
          ((d['sources'] as List?) ?? const []).map((e) => Source.fromJson(e as Map<String, dynamic>)).toList(),
          (d['retrieval_ms'] as num?)?.toInt() ?? 0,
          d['emergency'] == true,
        );
      case 'token':
        return TokenEvent('${d['t']}');
      case 'timing':
        return TimingEvent((d['first_token_ms'] as num?)?.toInt() ?? 0);
      case 'fallback':
        return FallbackEvent();
      case 'done':
        return DoneEvent((d['total_ms'] as num?)?.toInt() ?? 0);
    }
    return null;
  }
}
