import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
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
        // The taller hint's room for either, so the column does not jump with the mode.
        LayoutBuilder(
          builder: (context, box) {
            final style = t.text(t.s.bodySm, color: t.c.textMuted);
            final width = math.min(ShikooSizes.modeHint, box.maxWidth);
            return SizedBox(
              width: width,
              height: [
                for (final hint in [l.modeTunnelHint, l.modeProxyHint])
                  _height(context, hint, style, width),
              ].reduce(math.max),
              child: Text(
                mode == ShikooMode.tunnel ? l.modeTunnelHint : l.modeProxyHint,
                textAlign: TextAlign.center,
                style: style,
              ),
            );
          },
        ),
      ],
    );
  }
}

double _height(
  BuildContext context,
  String text,
  TextStyle style,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: TextAlign.center,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return height;
}

const localProxyAddress = '127.0.0.1:$shikooDesktopPort';

/// `.lp` in local-proxy.html, cut to one line: where an app like Telegram reaches ShikooNet.
class LocalProxy extends StatefulWidget {
  const LocalProxy({super.key});

  @override
  State<LocalProxy> createState() => _LocalProxyState();
}

class _LocalProxyState extends State<LocalProxy> {
  Timer? _copied;

  @override
  void dispose() {
    _copied?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(const ClipboardData(text: localProxyAddress));
    if (!mounted) return;
    _copied?.cancel();
    setState(
      () => _copied = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    final copied = _copied?.isActive ?? false;
    final ink = copied ? t.c.positive : t.c.text;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.sm),
    );
    // Both words hold their room, so «کپی شد» moves nothing beside it.
    Widget word(String text, bool shown) => Visibility(
      visible: shown,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Text(
        text,
        style: t.text(s.bodySm, weight: FontWeight.w700, color: ink),
      ),
    );
    final copy = Pressable(
      shape: shape,
      onPressed: () => unawaited(_copy()),
      builder: (context, _) => Semantics(
        button: true,
        child: Container(
          height: s.buttonSm,
          padding: const EdgeInsetsDirectional.only(
            start: Space.s2,
            end: Space.s3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.s1,
            children: [
              SvgIcon(
                copied ? ShikooIcon.check : ShikooIcon.copy,
                size: s.iconSm,
                color: ink,
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  word(l.localProxyCopy, !copied),
                  word(l.localProxyCopied, copied),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final field = DecoratedBox(
      decoration: ShapeDecoration(color: t.c.surfaceSunken, shape: shape),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: Space.s3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.s2,
          children: [
            SelectableText(
              localProxyAddress,
              textDirection: TextDirection.ltr,
              style: t.text(s.bodySm, weight: FontWeight.w500, tabular: true),
            ),
            copy,
          ],
        ),
      ),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.s2,
      runSpacing: Space.s1,
      children: [
        Text(l.localProxyLabel, style: t.text(s.bodySm, color: t.c.textMuted)),
        field,
      ],
    );
  }
}
