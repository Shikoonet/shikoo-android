import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// `.mode` in win-modes.html (frame `win-m-a`): the two parts, and what the chosen one does.
class ModeSwitch extends ConsumerWidget {
  const ModeSwitch({super.key, required this.connecting});

  final bool connecting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final mode = ref.watch(shikooModeProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.s2,
      children: [
        Semantics(
          label: l.modeLabel,
          child: SizedBox(
            width: ShikooSizes.modeSwitch,
            child: Segmented<ShikooMode>(
              selected: mode,
              options: {
                ShikooMode.proxy: l.modeProxy,
                ShikooMode.tunnel: l.modeTunnel,
              },
              onSelect: connecting
                  ? null
                  : (mode) => unawaited(
                      ref.read(shikooControllerProvider).setMode(mode),
                    ),
            ),
          ),
        ),
        // Two lines' room for either hint, so the column does not jump with the mode.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ShikooSizes.modeHint,
            minHeight: twoLines(context, t.s.bodySm),
          ),
          child: Text(
            mode == ShikooMode.tunnel ? l.modeTunnelHint : l.modeProxyHint,
            textAlign: TextAlign.center,
            style: t.text(t.s.bodySm, color: t.c.textMuted),
          ),
        ),
      ],
    );
  }
}
