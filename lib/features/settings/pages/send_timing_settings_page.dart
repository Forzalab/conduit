import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit_core/utils/chat_send_timing.dart';

import '../../../core/services/native_sheet_bridge.dart';

/// The plain timing list opened from About.
const sendTimingPageId = 'send-timing';

/// The row that copies every kept record as one line per send.
const sendTimingCopyAllActionId = 'send-timing-copy-all';

NativeSheetDetailConfig buildSendTimingDetail(AppLocalizations l10n) {
  final records = ChatSendTiming.instance.records;
  return NativeSheetDetailConfig(
    id: sendTimingPageId,
    title: l10n.sendTimingTitle,
    items: [
      if (records.isEmpty)
        NativeSheetItemConfig(
          id: 'send-timing-empty',
          title: l10n.sendTimingEmpty,
          sfSymbol: 'timer',
          kind: NativeSheetItemKind.info,
        )
      else ...[
        NativeSheetItemConfig(
          id: sendTimingCopyAllActionId,
          title: l10n.sendTimingCopyAll,
          actionId: sendTimingCopyAllActionId,
          sfSymbol: 'doc.on.doc',
          showsDisclosure: false,
          accent: true,
        ),
        for (final record in records)
          NativeSheetItemConfig(
            id: 'send-timing:${record.messageId}',
            title: '${record.displayTotalMs} ms',
            subtitle: record.jsonLine,
            sfSymbol: 'clock',
            kind: NativeSheetItemKind.info,
          ),
      ],
    ],
  );
}
