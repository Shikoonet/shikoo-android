import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/jalali.dart';
import 'package:fl_clash/shikoo/ui/report.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

/// Beside Settings' row on a computer; [LogsShortcut] answers them.
const logsKeys = ['Ctrl', 'R'];

void openLogs(BuildContext context) {
  final navigator = Navigator.maybeOf(context);
  if (navigator == null || ModalRoute.of(context)?.settings.name == 'logs') {
    return;
  }
  unawaited(
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const ShikooLogs(),
        settings: const RouteSettings(name: 'logs'),
      ),
    ),
  );
}

/// Ctrl+R on a computer opens the Logs page from wherever the focus is.
class LogsShortcut extends StatelessWidget {
  const LogsShortcut({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => !shikooDesktop
      ? child
      : CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
              if (FocusManager.instance.primaryFocus?.context
                  case final focused?) {
                openLogs(focused);
              }
            },
          },
          child: child,
        );
}

/// A day's heading, [day] and [today] in local time: Solar Hijri in Persian, Gregorian otherwise.
String logDay(BuildContext context, DateTime day, DateTime today) {
  final l = ShikooL10n.of(context);
  final language = Localizations.localeOf(context).languageCode;
  final j = toJalali(day);
  final date = language == 'fa'
      ? l.logsJalaliDay(
          DateFormat.EEEE('fa').format(day),
          localNumber(context, j.day),
          l.jalaliMonths.split('|')[j.month - 1],
        )
      : DateFormat.MMMEd(language).format(day);
  if (DateUtils.isSameDay(day, today)) return l.logsToday(date);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  return DateUtils.isSameDay(day, yesterday) ? l.logsYesterday(date) : date;
}

/// Frames `a-*` of happ-sections, variant الف: one tab of the record, newest at the bottom, over
/// two buttons stuck to the page's bottom.
class ShikooLogs extends ConsumerStatefulWidget {
  const ShikooLogs({super.key});

  @override
  ConsumerState<ShikooLogs> createState() => _ShikooLogsState();
}

class _ShikooLogsState extends ConsumerState<ShikooLogs> {
  // shortcut: read once on open, so a line written meanwhile shows on the next visit; follow the file if support asks.
  late final _entries = ref.read(shikooDiagProvider).logEntries();
  final _scroll = ScrollController();
  var _tab = LogTab.connection;
  Timer? _copied;
  double _fade = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _copied?.cancel();
    super.dispose();
  }

  Future<void> _copy(List<LogEntry> lines) async {
    await Clipboard.setData(
      ClipboardData(text: lines.map((e) => e.line).join('\n')),
    );
    if (!mounted) return;
    _copied?.cancel();
    setState(
      () => _copied = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() {});
      }),
    );
  }

  /// The list is reversed: what is left above is its extent after.
  bool _measure(Notification notification) {
    if (notification
        case ScrollMetricsNotification(depth: 0, :final metrics) ||
            ScrollUpdateNotification(depth: 0, :final metrics)) {
      final fade = metrics.extentAfter.clamp(0.0, ShikooSizes.fade);
      if (fade != _fade) setState(() => _fade = fade);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    final shown = [
      for (final entry in _entries)
        if (entry.tab == _tab) entry,
    ];
    return SubPage(
      title: l.logsTitle,
      isTV: false,
      scrolls: false,
      wide: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(s.safeX, 0, s.safeX, Space.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s2,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: shikooDesktop
                        ? ShikooSizes.tabs
                        : double.infinity,
                  ),
                  child: Segmented(
                    wraps: true,
                    selected: _tab,
                    counts: {
                      LogTab.errors: _entries
                          .where((e) => e.tab == LogTab.errors)
                          .length,
                    },
                    options: {
                      LogTab.connection: l.logsConnection,
                      LogTab.subscription: l.logsSubscription,
                      LogTab.core: l.logsCore,
                      LogTab.errors: l.logsErrors,
                    },
                    onSelect: (tab) => setState(() {
                      _tab = tab;
                      _copied?.cancel();
                    }),
                  ),
                ),
                Text(
                  l.logsCaption,
                  style: t.text(s.bodySm, color: t.c.textMuted),
                ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty ? const _Empty() : _list(context, shown),
          ),
          _foot(context, shown),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, List<LogEntry> shown) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    final today = DateTime.now();
    return NotificationListener<Notification>(
      onNotification: _measure,
      child: Stack(
        children: [
          // Shrink-wrapped and reversed: a short tab sits at the top, a long one opens on its newest line.
          Align(
            alignment: Alignment.topCenter,
            child: RawScrollbar(
              controller: _scroll,
              thumbVisibility: true,
              thickness: ShikooSizes.scrollThumb,
              radius: const Radius.circular(ShikooSizes.scrollThumb),
              thumbColor: t.c.outline,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: CustomScrollView(
                  key: ValueKey(_tab),
                  controller: _scroll,
                  reverse: true,
                  shrinkWrap: true,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        s.safeX,
                        0,
                        s.safeX,
                        Space.s3,
                      ),
                      sliver: DecoratedSliver(
                        decoration: ShapeDecoration(
                          color: t.c.surface,
                          shadows: t.c.cardShadow,
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(Radii.lg),
                          ),
                        ),
                        sliver: SliverPadding(
                          padding: const EdgeInsets.only(
                            top: Space.s1,
                            bottom: Space.s2,
                          ),
                          sliver: SliverList.builder(
                            itemCount: shown.length,
                            itemBuilder: (context, i) {
                              final at = shown.length - 1 - i;
                              final local = shown[at].at.toLocal();
                              final newDay =
                                  at == 0 ||
                                  !DateUtils.isSameDay(
                                    shown[at - 1].at.toLocal(),
                                    local,
                                  );
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (newDay)
                                    Padding(
                                      padding:
                                          const EdgeInsetsDirectional.fromSTEB(
                                            Space.s4,
                                            Space.s3,
                                            Space.s4,
                                            Space.s1,
                                          ),
                                      child: Text(
                                        logDay(context, local, today),
                                        style: t.text(
                                          s.caption,
                                          weight: FontWeight.w700,
                                          color: t.c.textMuted,
                                        ),
                                      ),
                                    )
                                  else
                                    Container(height: 1, color: t.c.border),
                                  _Line(shown[at]),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_fade > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _fade,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [t.c.bg, t.c.bg.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// `.logs-foot`: side by side while both labels fit whole, else one under the other.
  Widget _foot(BuildContext context, List<LogEntry> shown) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    final copied = _copied?.isActive ?? false;
    final words = [l.localProxyCopy, l.localProxyCopied];
    final send = ShikooButton(
      label: l.reportSendToSupport,
      icon: shikooDesktop ? ShikooIcon.report : null,
      primary: true,
      height: ShikooSizes.touch,
      onPressed: () => unawaited(openReport(context, 'logs')),
    );
    final copy = ShikooButton(
      label: words[copied ? 1 : 0],
      roomFor: words,
      icon: copied ? ShikooIcon.check : ShikooIcon.copy,
      positiveText: copied,
      height: ShikooSizes.touch,
      onPressed: shown.isEmpty ? null : () => unawaited(_copy(shown)),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.c.bg,
        border: Border(top: BorderSide(color: t.c.border)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          s.safeX,
          Space.s3,
          s.safeX,
          shikooDesktop
              ? Space.s4
              : Space.s6 + MediaQuery.paddingOf(context).bottom,
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            // ShikooButton's face: its label, Space.s4 each side, and an icon with Space.s2 after it.
            double width(String label, {bool icon = true}) {
              final painter = TextPainter(
                text: TextSpan(
                  text: label,
                  style: t.text(s.body, weight: FontWeight.w700),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final width = painter.width;
              painter.dispose();
              return width + 2 * Space.s4 + (icon ? s.icon + Space.s2 : 0);
            }

            final both =
                width(l.reportSendToSupport, icon: shikooDesktop) +
                Space.s2 +
                words.map(width).reduce(math.max);
            if (both > box.maxWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.s2,
                children: [send, copy],
              );
            }
            return Row(
              spacing: Space.s2,
              children: [
                if (shikooDesktop) send else Expanded(child: send),
                copy,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// `.la`: the mark, the local time and the line as written, left to right like the copied text.
class _Line extends StatelessWidget {
  const _Line(this.entry);

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    final local = entry.at.toLocal();
    final color = switch (entry.mark) {
      LogMark.error => t.c.danger,
      LogMark.warning => t.c.warning,
      LogMark.none => null,
    };
    final lead = entry.kind == 'C' && color != null
        ? entry.text.split(' ').first
        : '';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s1,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s2,
          children: [
            SizedBox(
              width: ShikooSizes.dot,
              height:
                  MediaQuery.textScalerOf(context).scale(s.bodySm) *
                  Leading.snug,
              child: color == null
                  ? null
                  : Center(
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: color,
                          shape: const CircleBorder(),
                        ),
                        child: const SizedBox.square(
                          dimension: ShikooSizes.dot,
                        ),
                      ),
                    ),
            ),
            Text(
              clockOf(
                Localizations.localeOf(context).languageCode,
                Duration(
                  hours: local.hour,
                  minutes: local.minute,
                  seconds: local.second,
                ),
              ),
              style: t.text(
                s.bodySm,
                color: t.c.textMuted,
                height: Leading.snug,
                tabular: true,
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (lead.isNotEmpty)
                      TextSpan(
                        text: lead,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    TextSpan(text: entry.text.substring(lead.length)),
                    if (entry.repeats > 1) ...[
                      const TextSpan(text: ' '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: t.c.surfaceSunken,
                            shape: const StadiumBorder(),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.s2,
                            ),
                            child: Text(
                              '×${localNumber(context, entry.repeats)}',
                              style: t.text(
                                s.caption,
                                weight: FontWeight.w700,
                                color: t.c.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                style: t.text(s.bodySm, height: Leading.snug),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.empty`: centred, scrolling only when a short window with large text cannot hold it.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s6,
                vertical: Space.s8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.s2,
                children: [
                  Container(
                    width: s.heroIcon,
                    height: s.heroIcon,
                    margin: const EdgeInsets.only(bottom: Space.s2),
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: t.c.surfaceSunken,
                      shape: const CircleBorder(),
                    ),
                    child: SvgIcon(
                      ShikooIcon.check,
                      size: s.heroIcon / 2,
                      stroke: ShikooSizes.iconStrokeStrong,
                      color: t.c.textMuted,
                    ),
                  ),
                  Text(
                    l.logsEmptyTitle,
                    textAlign: TextAlign.center,
                    style: t.text(s.title, weight: FontWeight.w700),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ShikooSizes.emptyText,
                    ),
                    child: Text(
                      l.logsEmptyHelp(ShikooDiag.keep.inDays),
                      textAlign: TextAlign.center,
                      style: t.text(
                        s.bodySm,
                        color: t.c.textMuted,
                        height: Leading.body,
                      ),
                    ),
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
