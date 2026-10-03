import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/naming.dart';
import 'package:fl_clash/shikoo/engine/ping.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/jalali.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

const _gib = 1024 * 1024 * 1024;

/// The card nodes the remote is sent to by hand: one per server name, so a row is found
/// wherever it sits, and the two buttons that geometry alone would skip.
class CardFocus {
  final renew = FocusNode();
  final pingAll = FocusNode();
  // ponytail: a removed server's node lives until the page goes; prune if lists churn a lot.
  final _rows = <String, FocusNode>{};

  FocusNode row(String name) => _rows.putIfAbsent(name, FocusNode.new);

  void dispose() {
    renew.dispose();
    pingAll.dispose();
    for (final node in _rows.values) {
      node.dispose();
    }
  }
}

/// `.card.svc` with its servers, as in `tv-ping.html`: name, status and the last update, the
/// update's result, volume and validity, the panel's announcement, renew and support, then
/// the server list.
class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.state,
    required this.controller,
    required this.focus,
  });

  final ShikooState state;
  final ShikooController controller;
  final CardFocus focus;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final service = state.service;
    final notice = state.notice;
    const inset = EdgeInsets.symmetric(horizontal: Space.s4);
    return Container(
      padding: const EdgeInsets.only(top: Space.s4, bottom: Space.s2),
      decoration: ShapeDecoration(
        color: t.c.surface,
        shadows: t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: service == null
            ? [
                Padding(
                  padding: inset.copyWith(bottom: Space.s2),
                  child: Text(
                    l.noService,
                    style: t.text(t.s.body, color: t.c.textMuted),
                  ),
                ),
              ]
            : [
                Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  includeSemantics: false,
                  onFocusChange: (inside) {
                    if (inside) Scrollable.maybeOf(context)?.position.jumpTo(0);
                  },
                  child: Padding(
                    padding: inset,
                    child: _Head(
                      service: service,
                      refresh: state.refresh,
                      onRefresh: () => unawaited(controller.refreshService()),
                    ),
                  ),
                ),
                if (notice != null)
                  Padding(
                    padding: inset,
                    child: _Message(notice: notice, isTV: state.isTV),
                  ),
                Padding(
                  padding: inset,
                  child: _Usage(service: service),
                ),
                if (service.announce != null)
                  Padding(
                    padding: inset,
                    child: _Notice(text: service.announce!),
                  ),
                Padding(
                  padding: inset.copyWith(top: Space.s3),
                  child: Row(
                    children: [
                      Expanded(
                        child: ShikooButton(
                          label: l.renew,
                          icon: ShikooIcon.qr,
                          primary: true,
                          focusNode: focus.renew,
                          onPressed: () => openLink(
                            context,
                            isTV: state.isTV,
                            link: service.renewLink,
                            title: l.renewTitle,
                            help: l.renewHelp,
                            service: service.name,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.s2),
                      Expanded(
                        child: ShikooButton(
                          label: l.support,
                          icon: ShikooIcon.qr,
                          onPressed: () => openLink(
                            context,
                            isTV: state.isTV,
                            link: service.supportLink,
                            title: l.supportTitle,
                            help: l.supportHelp,
                            service: service.name,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _ServerList(state: state, controller: controller, focus: focus),
              ],
      ),
    );
  }
}

String agoText(ShikooL10n l, Duration ago) {
  if (ago.inMinutes < 1) return l.agoJustNow;
  if (ago.inHours < 1) return l.agoMinutes(ago.inMinutes);
  if (ago.inDays < 1) return l.agoHours(ago.inHours);
  return l.agoDays(ago.inDays);
}

/// `.svc-head`: `.svc-line` (name and status), `.svc-sub` (the last update) and the update
/// button beside both.
class _Head extends StatelessWidget {
  const _Head({
    required this.service,
    required this.refresh,
    required this.onRefresh,
  });

  final ShikooService service;
  final ShikooRefresh refresh;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final updatedAt = service.updatedAt;
    final since = updatedAt == null
        ? null
        : DateTime.now().difference(updatedAt);
    final ago = since == null ? null : agoText(l, since);
    final sub = switch (refresh) {
      ShikooRefresh.running => l.updating,
      ShikooRefresh.failed when since == null || since.inMinutes < 1 =>
        l.updateFailed,
      ShikooRefresh.failed => l.updateFailedAgo(ago!),
      _ when ago != null => l.updatedAgo(ago),
      _ => null,
    };
    final busy = refresh == ShikooRefresh.running;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: nameText(
                      context,
                      service.name,
                      t.text(
                        t.s.title,
                        weight: FontWeight.w700,
                        height: Leading.snug,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  StatusChip(status: service.statusAt(DateTime.now())),
                ],
              ),
              if (sub != null)
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text(t.s.bodySm, color: t.c.textMuted),
                ),
            ],
          ),
        ),
        const SizedBox(width: Space.s2),
        ShikooButton(
          label: l.refresh,
          icon: ShikooIcon.refresh,
          busy: busy,
          onPressed: busy ? () {} : onRefresh,
        ),
      ],
    );
  }
}

/// `.notice.msg`: what the last update did; `.danger` when an update the user asked for
/// failed.
class _Message extends StatelessWidget {
  const _Message({required this.notice, required this.isTV});

  final ShikooNotice notice;
  final bool isTV;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final danger = notice is RefreshFailed;
    final (strong, rest) = switch (notice) {
      RefreshFailed() => (
        l.updateFailedTitle,
        isTV ? l.updateFailedTv : l.updateFailedTouch,
      ),
      SelectedReplaced(
        :final removed,
        :final replacement,
        :final moved,
        :final fastest,
      ) =>
        (
          l.selectedRemoved(withoutFlags(removed)),
          !fastest
              ? l.selectedMovedFirst(withoutFlags(replacement))
              : moved
              ? l.selectedMoved(withoutFlags(replacement))
              : l.selectedReplaced(withoutFlags(replacement)),
        ),
      SilentReplaced(:final silent, :final replacement, :final moved) => (
        l.selectedNoAnswer(withoutFlags(silent)),
        moved
            ? l.selectedMoved(withoutFlags(replacement))
            : l.selectedReplaced(withoutFlags(replacement)),
      ),
      ServersChanged(:final added, :final removed) => (
        [
          if (added > 0) l.serversAdded(added),
          if (removed.length == 1) l.serverRemoved(withoutFlags(removed.first)),
          if (removed.length > 1) l.serversRemoved(removed.length),
        ].join(' '),
        '',
      ),
    };
    final ink = danger ? t.c.danger : t.c.text;
    final style = t.text(t.s.bodySm, height: Leading.body);
    return Container(
      margin: const EdgeInsets.only(top: Space.s3),
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
              danger ? ShikooIcon.alert : ShikooIcon.refresh,
              size: t.s.iconSm,
              color: danger ? t.c.danger : t.c.textMuted,
            ),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: strong,
                    style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                  ),
                  if (rest.isNotEmpty) TextSpan(text: ' $rest'),
                ],
              ),
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _Usage extends StatelessWidget {
  const _Usage({required this.service});

  final ShikooService service;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final muted = t.text(t.s.bodySm, color: t.c.textMuted);
    final strong = TextStyle(color: t.c.text, fontWeight: FontWeight.w700);
    String gb(int bytes) => localNumber(context, bytes / _gib, '#,##0.#');
    final total = service.totalBytes;
    final used = service.usedBytes;
    final ratio = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final expire = service.expire;
    Widget row(List<Widget> children) => Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: Space.s1,
      children: children,
    );
    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row([
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${l.usedLabel} '),
                  TextSpan(text: gb(used), style: strong),
                  if (total > 0) TextSpan(text: ' ${l.ofTotalGb(gb(total))}'),
                ],
              ),
              style: muted,
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${l.remainingLabel} '),
                  TextSpan(
                    text: total > 0
                        ? l.gb(gb(math.max(total - used, 0)))
                        : l.unlimited,
                    style: strong,
                  ),
                ],
              ),
              style: muted,
            ),
          ]),
          if (total > 0) ...[
            const SizedBox(height: Space.s2),
            _Bar(ratio: ratio),
          ],
          if (expire != null) ...[
            const SizedBox(height: Space.s2),
            row([
              Text(l.validUntil(_date(context, l, expire)), style: muted),
              Text(
                l.daysLeft(
                  math.max(
                    0,
                    (expire.difference(DateTime.now()).inHours / 24).ceil(),
                  ),
                ),
                style: muted,
              ),
            ]),
          ],
        ],
      ),
    );
  }

  /// Solar Hijri in Persian, Gregorian in every other language.
  static String _date(BuildContext context, ShikooL10n l, DateTime date) {
    final language = Localizations.localeOf(context).languageCode;
    if (language != 'fa') return DateFormat.yMMMd(language).format(date);
    final j = toJalali(date);
    return l.jalaliDate(
      localNumber(context, j.day),
      l.jalaliMonths.split('|')[j.month - 1],
      localNumber(context, j.year),
    );
  }
}

/// `.bar`: fills from the start edge; amber from 90%, red when used up.
class _Bar extends StatelessWidget {
  const _Bar({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final fill = ratio >= 1
        ? t.c.danger
        : (ratio >= 0.9 ? t.c.warning : t.c.primary);
    return Container(
      height: t.s.bar,
      decoration: ShapeDecoration(
        color: t.c.surfaceSunken,
        shape: const StadiumBorder(),
      ),
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: ratio,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: fill,
            shape: const StadiumBorder(),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// `.notice`: the panel's announcement, every line of it.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: Space.s3),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s3,
        vertical: Space.s2,
      ),
      decoration: ShapeDecoration(
        color: t.c.surfaceSunken,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: (t.s.bodySm * Leading.snug - t.s.iconSm) / 2,
            ),
            child: SvgIcon(
              ShikooIcon.bell,
              size: t.s.iconSm,
              color: t.c.textMuted,
            ),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: nameText(
              context,
              text,
              t.text(t.s.bodySm, height: Leading.snug),
              maxLines: null,
            ),
          ),
        ],
      ),
    );
  }
}

/// `.list-head` and `.servers`. While the remote is on a row the order stays as it was, so
/// the row under it never jumps; leaving the list lets the new order in.
class _ServerList extends StatefulWidget {
  const _ServerList({
    required this.state,
    required this.controller,
    required this.focus,
  });

  final ShikooState state;
  final ShikooController controller;
  final CardFocus focus;

  @override
  State<_ServerList> createState() => _ServerListState();
}

class _ServerListState extends State<_ServerList> {
  List<String>? _held;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final state = widget.state;
    final byName = {for (final server in state.servers) server.name: server};
    final order = [...byName.keys];
    final shown = _held == null ? order : keepOrder(_held!, order);
    final pinging = state.pinging;
    // tv-ping.html: with the remote on ping-all or a row, the list head goes to the top; a
    // row it would push out of view scrolls back in by itself (Pressable).
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (inside) {
        if (inside) Scrollable.ensureVisible(context);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s4,
              Space.s4,
              Space.s2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: l.serversTitle,
                          style: TextStyle(
                            fontSize: t.s.body,
                            fontWeight: FontWeight.w700,
                            color: t.c.text,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' · ${listEquals(shown, order) ? l.fastestFirst : l.sortsOnLeave}',
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text(t.s.bodySm, color: t.c.textMuted),
                  ),
                ),
                const SizedBox(width: Space.s2),
                ShikooButton(
                  label: pinging == null
                      ? l.pingAll
                      : l.pingProgress(pinging.done, pinging.total),
                  icon: ShikooIcon.gauge,
                  busy: pinging != null,
                  focusNode: widget.focus.pingAll,
                  onPressed: pinging == null
                      ? () => unawaited(widget.controller.pingAll())
                      : () {},
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s2),
            child: order.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(Space.s2),
                    child: Text(
                      l.loadingServers,
                      style: t.text(t.s.bodySm, color: t.c.textMuted),
                    ),
                  )
                : Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    includeSemantics: false,
                    onFocusChange: (inside) =>
                        setState(() => _held = inside ? shown : null),
                    child: Column(
                      children: [
                        for (final name in shown)
                          ServerRow(
                            key: ValueKey(name),
                            server: byName[name]!,
                            selected: name == state.selected,
                            focusNode: widget.focus.row(name),
                            onPressed: () =>
                                unawaited(widget.controller.selectServer(name)),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
