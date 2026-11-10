import 'package:flutter_test/flutter_test.dart';
import 'package:jeevan_app/data/sse.dart';

void main() {
  group('SseParser', () {
    test('parses emergency, meta with sources, timing, token, and done across split chunks', () {
      final parser = SseParser();

      // Chunk 1 splits mid-line inside the meta payload
      final ev1 = parser.add(
        'event: emergency\n'
        'data: {"flag":true}\n\n'
        'event: meta\n'
        'data: {"retrieval_ms":14,"emergency":true,"sources":[{"n":1,"title":"CPR Guide",',
      );
      expect(ev1, hasLength(1));
      expect(ev1.first, isA<EmergencyEvent>());

      // Chunk 2 completes meta and streams timing + tokens + done
      final ev2 = parser.add(
        '"heading":"Adult Compressions","snippet":"Push hard and fast","private":false}]}\n\n'
        'event: timing\n'
        'data: {"first_token_ms":42}\n\n'
        'event: token\n'
        'data: {"t":"Start "}\n\n'
        'event: token\n'
        'data: {"t":"CPR [1]."}\n\n'
        'event: done\n'
        'data: {"total_ms":180}\n\n',
      );

      expect(ev2, hasLength(5));

      final meta = ev2[0] as MetaEvent;
      expect(meta.retrievalMs, 14);
      expect(meta.emergency, isTrue);
      expect(meta.sources, hasLength(1));
      expect(meta.sources.first.n, 1);
      expect(meta.sources.first.title, 'CPR Guide');
      expect(meta.sources.first.heading, 'Adult Compressions');
      expect(meta.sources.first.private, isFalse);

      final timing = ev2[1] as TimingEvent;
      expect(timing.firstTokenMs, 42);

      final tok1 = ev2[2] as TokenEvent;
      final tok2 = ev2[3] as TokenEvent;
      expect(tok1.text + tok2.text, 'Start CPR [1].');

      final done = ev2[4] as DoneEvent;
      expect(done.totalMs, 180);
    });
  });
}
