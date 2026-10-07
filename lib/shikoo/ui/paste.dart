import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/clock.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/report.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Reads the clipboard only when pressed (frames `phone-paste-error`, `phone-cards-paste`), and
/// shows why it failed above what [builder] draws. What was pasted is never shown.
class PasteLink extends ConsumerStatefulWidget {
  const PasteLink({
    super.key,
    required this.builder,
    this.onAdded,
    this.report = true,
    this.dateButton = true,
  });

  final Widget Function(BuildContext context, bool busy, VoidCallback paste)
  builder;
  final VoidCallback? onAdded;

  /// Off on the sign-in page, where its pictures could hold a live code.
  final bool report;

  /// Off where the page already shows date settings for its own clock message.
  final bool dateButton;

  @override
  ConsumerState<PasteLink> createState() => _PasteLinkState();
}

class _PasteLinkState extends ConsumerState<PasteLink> {
  bool _busy = false;
  ShikooPasteError? _error;

  Future<void> _paste() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      text = null;
    }
    final error = await ref.read(shikooControllerProvider).pasteService(text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) widget.onAdded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = ShikooL10n.of(context);
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s3,
      children: [
        if (error != null)
          Semantics(
            liveRegion: true,
            child: MessageBox(
              icon: ShikooIcon.alert,
              danger: true,
              strong: switch (error) {
                ShikooPasteError.empty => l.pasteEmptyTitle,
                ShikooPasteError.notShikoo => l.pasteNotShikooTitle,
                ShikooPasteError.revoked => l.pasteRevokedTitle,
                ShikooPasteError.unavailable => l.pasteUnavailableTitle,
                ShikooPasteError.offline => l.pasteOfflineTitle,
                ShikooPasteError.clock => l.clockWrongTitle,
              },
              rest: switch (error) {
                ShikooPasteError.empty => l.pasteEmptyHelp,
                ShikooPasteError.notShikoo => l.pasteNotShikooHelp,
                ShikooPasteError.revoked => l.pasteRevokedHelp,
                ShikooPasteError.unavailable => l.pasteUnavailableHelp,
                ShikooPasteError.offline => l.pasteOfflineHelp,
                ShikooPasteError.clock => l.clockWrongHelp,
              },
            ),
          ),
        if (error == ShikooPasteError.clock && widget.dateButton)
          const DateSettingsButton()
        else if (error != null && widget.report)
          LinkButton(
            label: l.reportSendToSupport,
            onPressed: () =>
                unawaited(openReport(context, 'paste_${error.name}')),
          ),
        widget.builder(context, _busy, () => unawaited(_paste())),
      ],
    );
  }
}
