import 'dart:convert';

import 'package:conduit_core/utils/chat_send_timing.dart';
import 'package:test/test.dart';

class _FakeStopwatch implements Stopwatch {
  int _microseconds = 0;

  void advance(int microseconds) => _microseconds += microseconds;

  @override
  Duration get elapsed => Duration(microseconds: _microseconds);

  @override
  int get elapsedMicroseconds => _microseconds;

  @override
  int get elapsedMilliseconds => _microseconds ~/ 1000;

  @override
  int get elapsedTicks => _microseconds;

  @override
  int get frequency => 1000000;

  @override
  bool get isRunning => true;

  @override
  void reset() => _microseconds = 0;

  @override
  void start() {}

  @override
  void stop() {}
}

void main() {
  test(
    'marks become durations, absent steps are omitted, one line is emitted',
    () {
      final stopwatch = _FakeStopwatch();
      final lines = <String>[];
      final timing = ChatSendTiming(
        stopwatchFactory: () => stopwatch,
        debugLineSink: lines.add,
      );

      timing.tap();
      stopwatch.advance(5000);
      final record = timing.beginSend(
        assistantMessageId: 'assistant-1',
        userMessageId: 'user-1',
      )!;
      expect(record.messageId, 'assistant-1');
      expect(timing.recordFor('assistant-1'), same(record));

      record.startStep('file_info');
      stopwatch.advance(12000);
      record.endStep('file_info');
      record.startStep('socket_session');
      stopwatch.advance(1000);
      record.endStep('socket_session');
      record.mark('post_sent');
      timing.markFirstContent('assistant-1');
      stopwatch.advance(7000);
      timing.markFirstPaint('assistant-1');
      timing.markFirstPaint('assistant-1');

      expect(lines, hasLength(1));
      expect(lines.single, startsWith('MIMI_TIMING {'));
      final json = jsonDecode(lines.single.substring('MIMI_TIMING '.length));
      expect(json['message_id'], 'assistant-1');
      expect(json['user_message_id'], 'user-1');
      expect(json['total_post_sent_ms'], 18);
      expect(json['total_first_content_event_ms'], 18);
      expect(json['total_first_paint_ms'], 25);
      expect(json['steps'], <String, int>{
        'file_info': 12,
        'socket_session': 1,
      });
      expect(
        (json['steps'] as Map<String, dynamic>).containsKey('user_settings'),
        isFalse,
      );
      expect(json.containsKey('failed'), isFalse);

      final failedLines = <String>[];
      final failedStopwatch = _FakeStopwatch();
      final failed = ChatSendTiming(
        stopwatchFactory: () => failedStopwatch,
        debugLineSink: failedLines.add,
      );
      failed.tap();
      failed.beginSend(assistantMessageId: 'assistant-2');
      failedStopwatch.advance(3000);
      failed.fail('assistant-2');
      failed.fail('assistant-2');
      expect(failedLines, hasLength(1));
      final failedJson = jsonDecode(
        failedLines.single.substring('MIMI_TIMING '.length),
      );
      expect(failedJson['total_first_paint_ms'], isNull);
      expect(failedJson['failed'], isTrue);

      final kept = ChatSendTiming(stopwatchFactory: _FakeStopwatch.new);
      for (var i = 0; i < 25; i += 1) {
        kept.beginSend(assistantMessageId: 'assistant-$i');
      }
      expect(kept.records, hasLength(20));
      expect(kept.records.first.messageId, 'assistant-24');
      expect(kept.records.last.messageId, 'assistant-5');
    },
  );
}
