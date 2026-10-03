import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:intl/intl.dart' show Bidi, NumberFormat;
import 'package:material_ui/material_ui.dart';

/// Numbers in the UI language: Persian digits under `fa`.
String localNumber(BuildContext context, num value, [String pattern = '0']) =>
    NumberFormat(
      pattern,
      Localizations.localeOf(context).languageCode,
    ).format(value);

/// A name from the subscription keeps its own script's direction, so `آلمان ۲` stays whole in
/// the English layout, while it still lines up with the UI's start edge.
Text nameText(BuildContext context, String name, TextStyle style) => Text(
  name,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: style,
  textDirection: Bidi.detectRtlDirectionality(name)
      ? TextDirection.rtl
      : TextDirection.ltr,
  textAlign: Directionality.of(context) == TextDirection.rtl
      ? TextAlign.right
      : TextAlign.left,
);

/// A focusable, pressable surface. The remote's OK key and a tap both press it.
/// The focus ring (`.is-focused`: 3dp, 2dp away) is drawn outside the child.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onPressed,
    required this.shape,
    required this.builder,
    this.autofocus = false,
    this.focusNode,
  });

  final VoidCallback onPressed;
  final OutlinedBorder shape;
  final bool autofocus;
  final FocusNode? focusNode;
  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _focused = false;

  /// Traversal reveals only the widget, cutting the ring drawn outside it in a scrolled column.
  void _revealWithRing(bool focused) {
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = mounted ? context.findRenderObject() : null;
      if (box is RenderBox && box.attached) {
        box.showOnScreen(rect: (Offset.zero & box.size).inflate(Space.s2));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    const gap = ShikooSizes.focusRingOffset;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: _revealWithRing,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            widget.builder(context, _focused),
            if (_focused)
              Positioned.fill(
                left: -gap,
                top: -gap,
                right: -gap,
                bottom: -gap,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: _grow(widget.shape, gap).copyWith(
                        side: BorderSide(
                          color: t.c.focusRing,
                          width: ShikooSizes.focusRingWidth,
                          strokeAlign: BorderSide.strokeAlignOutside,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  OutlinedBorder _grow(OutlinedBorder shape, double by) => switch (shape) {
    RoundedSuperellipseBorder(:final borderRadius) => RoundedSuperellipseBorder(
      borderRadius: borderRadius.add(BorderRadius.circular(by)),
    ),
    _ => shape,
  };
}

/// `.brand`: the letter mark and the word.
class Brand extends StatelessWidget {
  const Brand({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final mark = t.s.mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: mark,
          height: mark,
          alignment: Alignment.center,
          padding: EdgeInsets.only(bottom: mark * 0.1),
          decoration: ShapeDecoration(
            color: t.c.primary,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(mark * Radii.markRatio),
            ),
          ),
          child: Text(
            l.brandMark,
            style: t.text(
              mark * 0.56,
              weight: FontWeight.w800,
              color: t.c.onPrimary,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: Space.s2),
        Text(l.appTitle, style: t.text(t.s.title, weight: FontWeight.w800)),
      ],
    );
  }
}

/// `.btn-primary` and `.btn-outline`, with an icon before the label.
class ShikooButton extends StatelessWidget {
  const ShikooButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final ShikooIcon icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final radius = BorderRadius.circular(Radii.md);
    final fg = primary ? t.c.onPrimary : t.c.text;
    return Pressable(
      shape: RoundedSuperellipseBorder(borderRadius: radius),
      onPressed: onPressed,
      // A foreground, as the mockup's inset box-shadow: a decoration border widens the button.
      builder: (context, focused) => Container(
        height: t.s.button,
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        decoration: ShapeDecoration(
          color: primary ? t.c.primary : (focused ? t.c.focusBg : null),
          shadows: focused ? t.c.raisedShadow : null,
          shape: RoundedSuperellipseBorder(borderRadius: radius),
        ),
        foregroundDecoration: primary || focused
            ? null
            : ShapeDecoration(
                shape: RoundedSuperellipseBorder(
                  borderRadius: radius,
                  side: BorderSide(
                    color: t.c.outline,
                    width: t.s.borderControl,
                  ),
                ),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgIcon(icon, size: t.s.icon, color: fg),
            const SizedBox(width: Space.s2),
            Text(
              label,
              maxLines: 1,
              style: t.text(t.s.body, weight: FontWeight.w700, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.chip`: the service's status.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final ShikooServiceStatus status;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final ok = status == ShikooServiceStatus.active;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s3,
        vertical: Space.s1,
      ),
      decoration: ShapeDecoration(
        color: ok ? t.c.positiveSoft : t.c.dangerSoft,
        shape: const StadiumBorder(),
      ),
      child: Text(
        switch (status) {
          ShikooServiceStatus.active => l.statusActive,
          ShikooServiceStatus.expired => l.statusExpired,
          ShikooServiceStatus.exhausted => l.statusExhausted,
        },
        style: t.text(
          t.s.caption,
          weight: FontWeight.w700,
          color: ok ? t.c.positive : t.c.danger,
        ),
      ),
    );
  }
}

/// `.power-ring` and `.power`: off, connecting, on and couldn't-connect.
class PowerButton extends StatefulWidget {
  const PowerButton({
    super.key,
    required this.connection,
    required this.connectedFor,
    required this.isTV,
    required this.onPressed,
  });

  final ShikooConnection connection;
  final Duration connectedFor;
  final bool isTV;
  final VoidCallback onPressed;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PowerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final spin =
        widget.connection == ShikooConnection.connecting &&
        !MediaQuery.disableAnimationsOf(context);
    if (!spin) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  String _clock(Duration d) => [
    d.inHours,
    d.inMinutes % 60,
    d.inSeconds % 60,
  ].map((part) => localNumber(context, part, '00')).join(':');

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final c = t.c;
    final s = t.s;
    final l = ShikooL10n.of(context);
    final conn = widget.connection;
    final on = conn == ShikooConnection.on;
    final error = conn == ShikooConnection.error;
    final halo = switch (conn) {
      ShikooConnection.on => c.positiveSoft,
      ShikooConnection.error => c.dangerSoft,
      _ => null,
    };
    final label = switch (conn) {
      ShikooConnection.off => l.powerConnect,
      ShikooConnection.connecting => l.powerConnecting,
      ShikooConnection.on => l.powerOn,
      ShikooConnection.error => l.powerFailed,
    };
    final sub = switch (conn) {
      ShikooConnection.connecting =>
        widget.isTV ? l.subCancelTv : l.subCancelTouch,
      ShikooConnection.error => widget.isTV ? l.subRetryTv : l.subRetryTouch,
      _ => null,
    };
    final fg = on ? c.onPositive : c.text;
    return SizedBox.square(
      dimension: s.powerRing,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: halo,
                border: conn == ShikooConnection.off
                    ? Border.all(color: c.border)
                    : null,
              ),
            ),
          ),
          Pressable(
            autofocus: true,
            shape: const CircleBorder(),
            onPressed: widget.onPressed,
            builder: (context, focused) => Container(
              width: s.power,
              height: s.power,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? c.positive : c.surface,
                boxShadow: focused ? c.raisedShadow : c.cardShadow,
              ),
              child: Semantics(
                button: true,
                label: label,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgIcon(
                      error ? ShikooIcon.alert : ShikooIcon.power,
                      size: conn == ShikooConnection.off
                          ? ShikooSizes.powerIcon
                          : ShikooSizes.powerIconOn,
                      stroke: ShikooSizes.iconStrokeStrong,
                      color: on ? fg : (error ? c.danger : c.textMuted),
                    ),
                    const SizedBox(height: Space.s1),
                    Text(
                      label,
                      style: t.text(
                        s.body,
                        weight: FontWeight.w700,
                        color: error ? c.danger : fg,
                      ),
                    ),
                    if (on) ...[
                      const SizedBox(height: Space.s1),
                      Text(
                        _clock(widget.connectedFor),
                        textDirection: TextDirection.ltr,
                        style: t.text(
                          s.display,
                          weight: FontWeight.w700,
                          color: fg,
                          tabular: true,
                        ),
                      ),
                    ],
                    if (sub != null) ...[
                      const SizedBox(height: Space.s1),
                      Text(sub, style: t.text(s.caption, color: c.textMuted)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (conn == ShikooConnection.connecting)
            Positioned.fill(
              child: IgnorePointer(
                child: RotationTransition(
                  turns: _spin,
                  child: CustomPaint(
                    painter: _ArcPainter(track: c.border, head: c.primary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.arc`: a circle of r=48 in a 100-unit box, stroke 2, the head 28% of it, from the top.
class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.track, required this.head});

  final Color track;
  final Color head;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * ShikooSizes.arcStrokeRatio;
    final rect = (Offset.zero & size).deflate(size.shortestSide * 0.02);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(rect, paint..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * 0.28,
      false,
      paint..color = head,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.track != track || old.head != head;
}

class Ping extends StatelessWidget {
  const Ping({super.key, required this.server});

  final ShikooServer server;

  // ponytail: one fixed threshold taken from the frames (112 green, 130 amber); tune with real pings.
  static const _slowMs = 120;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final ping = server.ping;
    if (server.testing || ping == null) {
      return Text(
        server.testing ? '…' : '',
        style: t.text(t.s.bodySm, color: t.c.textMuted),
      );
    }
    final failed = ping < 0;
    final dot = failed
        ? t.c.danger
        : (ping > _slowMs ? t.c.warning : t.c.positive);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: ShikooSizes.dot,
          height: ShikooSizes.dot,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: Space.s2),
        Text.rich(
          failed
              ? TextSpan(text: l.noResponse)
              : TextSpan(
                  children: [
                    TextSpan(text: localNumber(context, ping)),
                    if (l.msUnit.isNotEmpty)
                      TextSpan(
                        text: ' ${l.msUnit}',
                        style: TextStyle(fontSize: t.s.caption),
                      ),
                  ],
                ),
          style: t.text(
            t.s.bodySm,
            color: failed ? t.c.danger : t.c.textMuted,
            tabular: true,
          ),
        ),
      ],
    );
  }
}

/// `.server`: flag, name, ping and tick; `.is-selected` adds the green start bar.
class ServerRow extends StatelessWidget {
  const ServerRow({
    super.key,
    required this.server,
    required this.selected,
    required this.onPressed,
    this.focusNode,
  });

  final ShikooServer server;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.md),
    );
    return Pressable(
      shape: shape,
      focusNode: focusNode,
      onPressed: onPressed,
      builder: (context, focused) => Container(
        constraints: BoxConstraints(minHeight: t.s.row),
        decoration: ShapeDecoration(
          shape: shape,
          color: focused ? t.c.focusBg : (selected ? t.c.selectedBg : null),
          shadows: focused ? t.c.raisedShadow : null,
        ),
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.s2),
              child: Row(
                children: [
                  Flag(country: server.country),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: nameText(
                      context,
                      server.label,
                      t.text(
                        t.s.body,
                        weight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s3),
                  Ping(server: server),
                  const SizedBox(width: Space.s3),
                  Opacity(
                    opacity: selected ? 1 : 0,
                    child: SvgIcon(
                      ShikooIcon.check,
                      size: t.s.icon,
                      color: t.c.positive,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              PositionedDirectional(
                start: 0,
                top: Space.s2,
                bottom: Space.s2,
                child: Container(
                  width: ShikooSizes.selectedBar,
                  decoration: ShapeDecoration(
                    color: t.c.positive,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.now`: the selected server under the power button.
class NowPill extends StatelessWidget {
  const NowPill({super.key, required this.server});

  final ShikooServer server;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s2,
      ),
      decoration: ShapeDecoration(
        color: t.c.surface,
        shape: const StadiumBorder(),
        shadows: t.c.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flag(country: server.country),
          const SizedBox(width: Space.s2),
          Flexible(
            child: nameText(
              context,
              server.label,
              t.text(t.s.body, weight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: Space.s2),
          Ping(server: server),
        ],
      ),
    );
  }
}
