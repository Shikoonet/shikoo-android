import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/clock.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/report.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
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
  final ValueChanged<ShikooPasted>? onAdded;

  /// Off on the sign-in page, whose pictures could hold a live code; [dateButton], where date settings show already.
  final bool report;
  final bool dateButton;

  @override
  ConsumerState<PasteLink> createState() => _PasteLinkState();
}

class _PasteLinkState extends ConsumerState<PasteLink> {
  bool _busy = false;
  ShikooPasteError? _error;

  /// Leaving mid-check does not stop it: the service is still added, so [ref] is read first.
  Future<void> _paste() async {
    if (_busy) return;
    final controller = ref.read(shikooControllerProvider);
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
    final pasted = await controller.pasteService(text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = pasted.error;
    });
    if (pasted.error == null) widget.onAdded?.call(pasted);
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
                ShikooPasteError.offline =>
                  (shikooDesktop
                      ? l.pasteOfflineHelpDesktop
                      : l.pasteOfflineHelp),
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

/// `phone-p4-screen`, from home's «+»: it closes with what the paste brought, for home to say.
class AddService extends StatelessWidget {
  const AddService({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    return SubPage(
      title: l.addServiceTitle,
      isTV: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s4,
        children: [
          Text(
            (shikooDesktop ? l.addServiceHelpDesktop : l.addServiceHelp),
            style: t.text(
              t.s.bodySm,
              color: t.c.textMuted,
              height: Leading.body,
            ),
          ),
          PasteLink(
            onAdded: (pasted) => Navigator.pop(context, pasted),
            builder: (context, busy, paste) => ShikooButton(
              label: busy ? l.pasteChecking : l.pasteLink,
              icon: ShikooIcon.paste,
              primary: true,
              busy: busy,
              onPressed: paste,
            ),
          ),
        ],
      ),
    );
  }
}
