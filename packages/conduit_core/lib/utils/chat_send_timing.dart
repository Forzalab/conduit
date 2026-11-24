import 'dart:convert';

import 'package:conduit_core/utils/debug_logger.dart';

/// Sends the one-line timing record somewhere the release app can see it.
typedef ChatSendTimingLineSink = void Function(String line);

/// Milliseconds from a send's tap to each mark it reached.
///
/// One record belongs to one send, named by the assistant (and, when known,
/// user) message id. Marks are monotonic: they all read the same [Stopwatch],
/// which starts at the tap, so wall-clock changes cannot reorder them. A step
/// that did not run has no start, and so no entry in the JSON.
final class ChatSendTimingRecord {
  ChatSendTimingRecord._({
    required Stopwatch stopwatch,
    this.userMessageId,
    this.assistantMessageId,
  }) : _stopwatch = stopwatch;

  final Stopwatch _stopwatch;
  final String? userMessageId;
  final String? assistantMessageId;

  /// First-reached instant of a one-shot mark, in microseconds after the tap.
  final Map<String, int> _marksUs = <String, int>{};

  /// Start of each step still running, and the summed duration of those that
  /// finished (a step can legitimately run twice: the temporary-chat socket
  /// connect is one).
  final Map<String, int> _stepStartsUs = <String, int>{};
  final Map<String, int> _stepTotalsUs = <String, int>{};

  bool _emitted = false;
  bool _failed = false;

  String get messageId => assistantMessageId ?? userMessageId ?? '';

  bool get emitted => _emitted;

  bool get failed => _failed;

  int get elapsedMicroseconds => _stopwatch.elapsedMicroseconds;

  /// The headline a list shows: to the first paint when it happened, else to
  /// the POST, else how long this record has been open.
  int get displayTotalMs =>
      _markMs('first_paint') ??
      _markMs('post_sent') ??
      elapsedMicroseconds ~/ 1000;

  /// Marks [name] the first time only.
  void mark(String name) {
    _marksUs.putIfAbsent(name, () => elapsedMicroseconds);
  }

  void startStep(String name) {
    _stepStartsUs.putIfAbsent(name, () => elapsedMicroseconds);
  }

  void endStep(String name) {
    final startedAt = _stepStartsUs.remove(name);
    if (startedAt == null) return;
    final elapsed = elapsedMicroseconds - startedAt;
    _stepTotalsUs.update(
      name,
      (total) => total + elapsed,
      ifAbsent: () => elapsed,
    );
  }

  int? _markMs(String name) {
    final us = _marksUs[name];
    return us == null ? null : us ~/ 1000;
  }

  /// The record as a JSON object. It carries identifiers and durations only:
  /// never text, prompts, locations, or credentials.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'message_id': messageId,
      if (userMessageId != null) 'user_message_id': userMessageId,
      'total_post_sent_ms': _markMs('post_sent'),
      'total_first_content_event_ms': _markMs('first_content_event'),
      'total_first_paint_ms': _markMs('first_paint'),
      'steps': <String, int>{
        for (final entry in _stepTotalsUs.entries)
          entry.key: entry.value ~/ 1000,
      },
      if (_failed) 'failed': true,
    };
  }

  String get jsonLine => 'MIMI_TIMING ${jsonEncode(toJson())}';
}

/// The send timing recorder: one record per send, newest 20 kept in memory.
///
/// Call [tap] from the composer's send handler, [beginSend] when the message
/// ids are minted, [startStep]/[endStep] around awaited work, and
/// [markFirstContent]/[markFirstPaint] as those land. The line is emitted once,
/// on the first paint or on [fail].
final class ChatSendTiming {
  ChatSendTiming({
    this.capacity = 20,
    Stopwatch Function()? stopwatchFactory,
    this.debugLineSink,
  }) : _newStopwatch = stopwatchFactory ?? Stopwatch.new;

  /// The app's recorder. Tests build their own with a fake Stopwatch.
  static final ChatSendTiming instance = ChatSendTiming();

  /// Finished (or failed) records kept for the debug screen.
  final int capacity;

  /// A Flutter host installs `debugPrint` here: [DebugLogger] is silent in
  /// release builds, and the timing line must still reach logcat.
  ChatSendTimingLineSink? debugLineSink;

  final Stopwatch Function() _newStopwatch;
  final List<ChatSendTimingRecord> _records = <ChatSendTimingRecord>[];
  ChatSendTimingRecord? _pendingTap;

  /// Newest first.
  List<ChatSendTimingRecord> get records =>
      List<ChatSendTimingRecord>.unmodifiable(_records.reversed);

  /// Every kept record as its one-line JSON, newest first.
  List<String> get lines => <String>[
    for (final record in records) record.jsonLine,
  ];

  /// A tap that has not yet been claimed by a send. Taken in the composer, so
  /// the measure includes everything the UI does before the provider runs.
  void tap() {
    final stopwatch = _newStopwatch()..start();
    _pendingTap = ChatSendTimingRecord._(stopwatch: stopwatch)..mark('tap');
  }

  /// Claims the pending tap (or starts a record now, for a send with no tap,
  /// such as an outbox op drained after a restart) for [assistantMessageId].
  ChatSendTimingRecord? beginSend({
    required String assistantMessageId,
    String? userMessageId,
  }) {
    for (final existing in _records) {
      if (existing.assistantMessageId == assistantMessageId) {
        return existing;
      }
    }
    final pending = _pendingTap;
    _pendingTap = null;
    final record =
        pending ?? ChatSendTimingRecord._(stopwatch: _newStopwatch()..start());
    final bound = ChatSendTimingRecord._(
      stopwatch: record._stopwatch,
      assistantMessageId: assistantMessageId,
      userMessageId: userMessageId,
    );
    // A pending record may already carry marks (nothing is marked before the
    // ids exist today, but keeping them costs nothing and keeps this honest).
    bound._marksUs.addAll(record._marksUs);
    bound._stepStartsUs.addAll(record._stepStartsUs);
    bound._stepTotalsUs.addAll(record._stepTotalsUs);
    bound.mark('tap');

    _records.add(bound);
    while (_records.length > capacity) {
      _records.removeAt(0);
    }
    return bound;
  }

  ChatSendTimingRecord? recordFor(String assistantMessageId) {
    for (final record in _records) {
      if (record.assistantMessageId == assistantMessageId) return record;
    }
    return null;
  }

  /// The first non-empty streamed content reached the message notifier.
  void markFirstContent(String assistantMessageId) {
    recordFor(assistantMessageId)?.mark('first_content_event');
  }

  /// The first token was painted; emits this send's one line.
  void markFirstPaint(String assistantMessageId) {
    final record = recordFor(assistantMessageId);
    if (record == null) return;
    record.mark('first_paint');
    _emit(record);
  }

  /// The send failed before a first paint; emits what was reached so far.
  void fail(String assistantMessageId) {
    final record = recordFor(assistantMessageId);
    if (record == null) return;
    record._failed = true;
    _emit(record);
  }

  void _emit(ChatSendTimingRecord record) {
    if (record._emitted) return;
    record._emitted = true;
    final line = record.jsonLine;
    DebugLogger.log(line, scope: 'chat/timing');
    debugLineSink?.call(line);
  }
}
