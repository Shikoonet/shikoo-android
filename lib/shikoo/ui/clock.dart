import 'dart:async';

import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

String clockText(ShikooL10n l) => '${l.clockWrongTitle} ${l.clockWrongHelp}';

class DateSettingsButton extends StatelessWidget {
  const DateSettingsButton({
    super.key,
    this.focusNode,
    this.primary = false,
    this.autofocus = false,
  });

  final FocusNode? focusNode;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => ShikooButton(
    label: ShikooL10n.of(context).dateSettings,
    icon: ShikooIcon.gear,
    primary: primary,
    autofocus: autofocus,
    focusNode: focusNode,
    onPressed: () => unawaited(openDateSettings()),
  );
}

/// Phone and TV alike; the app goes no further until [onRetry] finds the clock right.
class ClockPage extends StatelessWidget {
  const ClockPage({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    return Scaffold(
      backgroundColor: t.c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.s6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.s4,
                children: [
                  const Center(child: Brand()),
                  MessageBox(
                    icon: ShikooIcon.alert,
                    danger: true,
                    strong: l.clockWrongTitle,
                    rest: l.clockWrongHelp,
                  ),
                  const DateSettingsButton(primary: true, autofocus: true),
                  ShikooButton(
                    label: l.retry,
                    icon: ShikooIcon.refresh,
                    onPressed: onRetry,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
