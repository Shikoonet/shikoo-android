import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:intl/intl.dart' show Bidi, NumberFormat;
import 'package:material_ui/material_ui.dart';

const _slot = '\u{E000}';

/// [message] with [part] at its placeholder, which [_slot] marks: no translation holds it.
List<InlineSpan> sayWith(
  String Function(String part) message,
  List<InlineSpan> part,
) {
  final pieces = message(_slot).split(_slot);
  return [
    TextSpan(text: pieces.first),
    if (pieces.length > 1) ...[...part, TextSpan(text: pieces[1])],
  ];
}

/// Numbers in the UI language: Persian digits under `fa`.
String localNumber(BuildContext context, num value, [String pattern = '0']) =>
    NumberFormat(
      pattern,
      Localizations.localeOf(context).languageCode,
    ).format(value);

/// A name from the subscription keeps its own script's direction, so `آلمان ۲` stays whole in
/// the English layout, while it still lines up with the UI's start edge.
Text nameText(
  BuildContext context,
  String name,
  TextStyle style, {
  int? maxLines = 1,
}) => Text(
  name,
  maxLines: maxLines,
  overflow: maxLines == null ? null : TextOverflow.ellipsis,
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
        box.showOnScreen(
          rect: (Offset.zero & box.size).inflate(Space.s2 + ShikooSizes.ring),
        );
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: t.s.mark),
        const SizedBox(width: Space.s2),
        Text(
          ShikooL10n.of(context).appTitle,
          style: t.text(t.s.title, weight: FontWeight.w800),
        ),
      ],
    );
  }
}

/// `.mark`: the letter «ش» on the primary colour.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      padding: EdgeInsets.only(bottom: size * 0.1),
      decoration: ShapeDecoration(
        color: t.c.primary,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(size * Radii.markRatio),
        ),
      ),
      child: Text(
        ShikooL10n.of(context).brandMark,
        style: t.text(
          size * 0.56,
          weight: FontWeight.w800,
          color: t.c.onPrimary,
          height: 1,
        ),
      ),
    );
  }
}

/// `.icon` turning, for work in progress (`#i-spin`); still when animations are off.
class Spinner extends StatefulWidget {
  const Spinner({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _turns.stop();
    } else if (!_turns.isAnimating) {
      _turns.repeat();
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turns,
    child: SvgIcon(ShikooIcon.spin, size: widget.size, color: widget.color),
  );
}

/// `.btn-primary`, `.btn-danger` and `.btn-outline`, an icon before the label; [busy] spins it.
class ShikooButton extends StatelessWidget {
  const ShikooButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.danger = false,
    this.busy = false,
    this.autofocus = false,
    this.focusNode,
    this.telegram = false,
    this.height,
    this.dangerText = false,
    this.small = false,
  });

  final String label;
  final ShikooIcon? icon;

  /// An outline button whose label is red, as the revoked card's «حذف».
  final bool dangerText;

  /// Null greys the button out and the remote passes it by.
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final bool busy;
  final bool autofocus;
  final FocusNode? focusNode;

  /// `.btn-telegram`: Telegram's blue, taller, the label large and bold.
  final bool telegram;
  final double? height;

  /// `.btn-sm`, whose touch target still reaches [ShikooSizes.touch].
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final radius = BorderRadius.circular(Radii.md);
    final onPressed = this.onPressed;
    final enabled = onPressed != null;
    final fg = !enabled
        ? t.c.textMuted
        : telegram
        ? ShikooColors.onTelegram
        : primary
        ? t.c.onPrimary
        : (danger ? t.c.onDanger : (dangerText ? t.c.danger : t.c.text));
    final fill = !enabled
        ? null
        : telegram
        ? ShikooColors.telegram
        : primary
        ? t.c.primary
        : (danger ? t.c.danger : null);
    final icon = this.icon;
    // A foreground, as the mockup's inset box-shadow: a decoration border widens the button.
    Widget face(bool focused) => Container(
      height:
          height ??
          (telegram
              ? ShikooSizes.buttonLg
              : (small ? t.s.buttonSm : t.s.button)),
      padding: EdgeInsets.symmetric(horizontal: small ? Space.s3 : Space.s4),
      decoration: ShapeDecoration(
        color: fill ?? (focused ? t.c.focusBg : null),
        shadows: focused ? t.c.raisedShadow : null,
        shape: RoundedSuperellipseBorder(borderRadius: radius),
      ),
      foregroundDecoration: fill != null || focused
          ? null
          : ShapeDecoration(
              shape: RoundedSuperellipseBorder(
                borderRadius: radius,
                side: BorderSide(
                  color: enabled ? t.c.outline : t.c.border,
                  width: t.s.borderControl,
                ),
              ),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            Spinner(size: t.s.icon, color: fg)
          else if (icon != null)
            SvgIcon(
              icon,
              size: small ? t.s.iconSm : t.s.icon,
              color: enabled ? fg : t.c.iconDisabled,
            ),
          if (busy || icon != null) const SizedBox(width: Space.s2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text(
                telegram
                    ? ShikooSizes.buttonLgText
                    : (small ? t.s.bodySm : t.s.body),
                weight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
    if (!enabled) return face(false);
    return Pressable(
      shape: RoundedSuperellipseBorder(borderRadius: radius),
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      builder: (context, focused) => small
          ? Padding(
              padding: EdgeInsets.symmetric(
                vertical: (ShikooSizes.touch - t.s.buttonSm) / 2,
              ),
              child: face(focused),
            )
          : face(focused),
    );
  }
}

/// `.icon-btn`: an icon alone in a round touch target; [label] is what a screen reader says.
class ShikooIconButton extends StatelessWidget {
  const ShikooIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.busy = false,
    this.flipInLtr = false,
  });

  final ShikooIcon icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final bool busy;

  /// For an arrow drawn for Persian, as `.flip-ltr`.
  final bool flipInLtr;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final color = this.color ?? t.c.text;
    final ltr = Directionality.of(context) == TextDirection.ltr;
    return Pressable(
      shape: const CircleBorder(),
      onPressed: onPressed,
      builder: (context, _) => Semantics(
        button: true,
        label: label,
        child: SizedBox.square(
          dimension: ShikooSizes.touch,
          child: Center(
            child: busy
                ? Spinner(size: t.s.icon, color: color)
                : Transform.flip(
                    flipX: flipInLtr && ltr,
                    child: SvgIcon(icon, size: t.s.icon, color: color),
                  ),
          ),
        ),
      ),
    );
  }
}

/// `.notice.msg`: a bold first sentence and the rest; `.danger` in red.
class MessageBox extends StatelessWidget {
  const MessageBox({
    super.key,
    required this.icon,
    required this.strong,
    required this.rest,
    this.danger = false,
  });

  final ShikooIcon icon;
  final String strong;
  final String rest;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s3,
        vertical: Space.s2,
      ),
      decoration: ShapeDecoration(
        color: danger ? t.c.dangerSoft : t.c.surfaceSunken,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: (t.s.bodySm * Leading.body - t.s.iconSm) / 2,
            ),
            child: SvgIcon(
              icon,
              size: t.s.iconSm,
              color: danger ? t.c.danger : t.c.textMuted,
            ),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (strong.isNotEmpty)
                    TextSpan(
                      text: strong,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: danger ? t.c.danger : t.c.text,
                      ),
                    ),
                  if (rest.isNotEmpty)
                    TextSpan(text: strong.isEmpty ? rest : ' $rest'),
                ],
              ),
              style: t.text(t.s.bodySm, height: Leading.body),
            ),
          ),
        ],
      ),
    );
  }
}

/// Each part keeps its own direction and never breaks inside; a line breaks only before «·»,
/// which goes down with the tier.
String bidiName(String name) => name
    .split(' · ')
    .map((part) => '\u2068${part.replaceAll(' ', '\u00A0')}\u2069')
    .join(' ·\u00A0');

/// `.svc-name`: never cut at its end. A username too long for a line alone keeps its last five
/// characters (`7000…123_2`), which tell the services of one account apart.
class ServiceName extends StatelessWidget {
  const ServiceName(this.name, {super.key, this.style, this.textAlign});

  final String name;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final style =
        this.style ??
        t.text(t.s.title, weight: FontWeight.w700, height: Leading.snug);
    return LayoutBuilder(
      builder: (context, box) {
        final [user, ...rest] = name.split(' · ');
        bool fits(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width <= box.maxWidth;
        }

        var shown = user;
        if (user.length > 6 && !fits(user)) {
          final tail = user.substring(user.length - 5);
          var lo = 0;
          var hi = user.length - 6;
          while (lo < hi) {
            final mid = (lo + hi + 1) ~/ 2;
            fits('${user.substring(0, mid)}…$tail') ? lo = mid : hi = mid - 1;
          }
          shown = '${user.substring(0, lo)}…$tail';
        }
        final text = [shown, ...rest].join(' · ');
        return Text(
          rest.isEmpty ? text : bidiName(text),
          textAlign: textAlign,
          style: style,
        );
      },
    );
  }
}

String serviceTitle(BuildContext context, ShikooService service) =>
    service.name.isEmpty
    ? plainTitle(context, service)
    : bidiName(service.name);

String plainTitle(BuildContext context, ShikooService service) {
  if (service.name.isNotEmpty) return service.name;
  final l = ShikooL10n.of(context);
  return service.number > 1
      ? '${l.serviceUnnamed} ${localNumber(context, service.number)}'
      : l.serviceUnnamed;
}

String statusLabel(ShikooL10n l, ShikooServiceStatus status) =>
    switch (status) {
      ShikooServiceStatus.active => l.statusActive,
      ShikooServiceStatus.expired => l.chipExpired,
      ShikooServiceStatus.exhausted => l.stateExhausted,
      ShikooServiceStatus.revoked => l.chipRevoked,
    };

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
        statusLabel(l, status),
        style: t.text(
          t.s.caption,
          weight: FontWeight.w700,
          color: ok ? t.c.positive : t.c.danger,
        ),
      ),
    );
  }
}

/// `.power-ring` and `.power`: off, connecting, on and couldn't-connect; with no [onPressed],
/// `.is-disabled`, which the remote passes by.
class PowerButton extends StatefulWidget {
  const PowerButton({
    super.key,
    required this.connection,
    required this.connectedFor,
    required this.isTV,
    required this.onPressed,
    this.focusNode,
    this.restingLabel,
  });

  final ShikooConnection connection;
  final Duration connectedFor;
  final bool isTV;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  /// What a button with no [onPressed] says; "No service" unless given.
  final String? restingLabel;

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
    final onPressed = widget.onPressed;
    final enabled = onPressed != null;
    final label = switch (conn) {
      _ when !enabled => widget.restingLabel ?? l.powerNoService,
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
    Widget face(bool focused) => Container(
      width: s.power,
      height: s.power,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: !enabled ? c.surfaceSunken : (on ? c.positive : c.surface),
        boxShadow: !enabled ? null : (focused ? c.raisedShadow : c.cardShadow),
      ),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: ShikooSizes.roundTextScaleMax,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgIcon(
                error ? ShikooIcon.alert : ShikooIcon.power,
                size: conn == ShikooConnection.off && enabled
                    ? ShikooSizes.powerIcon
                    : ShikooSizes.powerIconOn,
                stroke: ShikooSizes.iconStrokeStrong,
                color: !enabled
                    ? c.iconDisabled
                    : (on ? fg : (error ? c.danger : c.textMuted)),
              ),
              const SizedBox(height: Space.s1),
              Text(
                label,
                textAlign: TextAlign.center,
                style: t.text(
                  s.body,
                  weight: FontWeight.w700,
                  color: !enabled ? c.textMuted : (error ? c.danger : fg),
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
    );
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
          if (enabled)
            Pressable(
              autofocus: true,
              focusNode: widget.focusNode,
              shape: const CircleBorder(),
              onPressed: onPressed,
              builder: (context, focused) => face(focused),
            )
          else
            face(false),
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
    if (server.testing) {
      return Semantics(
        label: l.measuring,
        child: Spinner(size: t.s.iconSm, color: t.c.textMuted),
      );
    }
    if (ping == null) return const SizedBox.shrink();
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

/// `.server`: flag, name, ping and tick; `.is-selected` adds the green start bar, [isNew]
/// the `.chip-outline` "new" after the name.
class ServerRow extends StatelessWidget {
  const ServerRow({
    super.key,
    required this.server,
    required this.selected,
    required this.onPressed,
    this.focusNode,
    this.isNew = false,
  });

  final ShikooServer server;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool isNew;

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
                    child: Row(
                      children: [
                        Flexible(
                          child: nameText(
                            context,
                            server.label,
                            t.text(
                              t.s.body,
                              weight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isNew) ...[
                          const SizedBox(width: Space.s2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.s3,
                              vertical: Space.s1,
                            ),
                            decoration: ShapeDecoration(
                              shape: StadiumBorder(
                                side: BorderSide(color: t.c.outline),
                              ),
                            ),
                            child: Text(
                              ShikooL10n.of(context).newBadge,
                              style: t.text(
                                t.s.caption,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
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

/// `.now`: the selected server under the power button; `.is-finding` while the app looks for
/// the best one, `.is-none` when none answered.
class NowPill extends StatelessWidget {
  const NowPill({super.key, required this.pick, this.server});

  final ShikooPick pick;
  final ShikooServer? server;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final server = this.server;
    Widget say(String text, Color color) => Flexible(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.text(t.s.body, weight: FontWeight.w500, color: color),
      ),
    );
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
        children: switch (pick) {
          ShikooPick.server when server != null => [
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
          ShikooPick.none => [
            SvgIcon(ShikooIcon.alert, size: t.s.iconSm, color: t.c.danger),
            const SizedBox(width: Space.s2),
            say(l.noServerAnswered, t.c.text),
          ],
          _ => [
            Spinner(size: t.s.iconSm, color: t.c.textMuted),
            const SizedBox(width: Space.s2),
            say(l.findingBest, t.c.textMuted),
          ],
        },
      ),
    );
  }
}
