import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/naming.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
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

const _nearlyUsed = 0.9;

/// Solar Hijri in Persian, Gregorian in every other language.
String _date(BuildContext context, ShikooL10n l, DateTime date) {
  final language = Localizations.localeOf(context).languageCode;
  if (language != 'fa') return DateFormat.yMMMd(language).format(date);
  final j = toJalali(date);
  return l.jalaliDate(
    localNumber(context, j.day),
    l.jalaliMonths.split('|')[j.month - 1],
    localNumber(context, j.year),
  );
}

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
class ServiceCard extends StatefulWidget {
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
  State<ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<ServiceCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final ServiceCard(:state, :controller, :focus) = widget;
    final service = state.service;
    final notice = state.notice;
    final open = _open || state.isTV;
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
                  padding: inset,
                  child: Text(
                    state.isTV ? l.noServiceTitleTv : l.noServiceTitleTouch,
                    style: t.text(
                      t.s.title,
                      weight: FontWeight.w700,
                      height: Leading.snug,
                    ),
                  ),
                ),
                Padding(
                  padding: inset.copyWith(top: Space.s2),
                  child: Text(
                    l.noServiceHelp,
                    style: t.text(
                      t.s.bodySm,
                      color: t.c.textMuted,
                      height: Leading.body,
                    ),
                  ),
                ),
                Padding(
                  padding: inset.copyWith(top: Space.s3, bottom: Space.s2),
                  child: ShikooButton(
                    label: l.support,
                    icon: state.isTV ? ShikooIcon.qr : null,
                    onPressed: () => openLink(
                      context,
                      isTV: state.isTV,
                      link: ShikooLinks.support,
                      title: l.supportTitle,
                      help: l.supportHelp,
                    ),
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
                    padding: state.isTV
                        ? inset
                        : const EdgeInsetsDirectional.only(start: Space.s4),
                    child: _Head(
                      service: service,
                      refresh: state.refresh,
                      onRefresh: () => unawaited(controller.refreshService()),
                      isTV: state.isTV,
                      open: open,
                      onFold: () => setState(() => _open = !_open),
                    ),
                  ),
                ),
                if (!open)
                  Padding(
                    padding: inset,
                    child: _Summary(service: service),
                  )
                else ...[
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
                            icon: state.isTV ? ShikooIcon.qr : null,
                            primary: true,
                            focusNode: focus.renew,
                            onPressed: () => openLink(
                              context,
                              isTV: state.isTV,
                              link: ShikooLinks.renew,
                              title: l.renewTitle,
                              help: l.renewHelp,
                              below: l.renewPickInList(service.username),
                              strong: service.username,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.s2),
                        Expanded(
                          child: ShikooButton(
                            label: l.support,
                            icon: state.isTV ? ShikooIcon.qr : null,
                            onPressed: () => openLink(
                              context,
                              isTV: state.isTV,
                              link: service.supportLink,
                              title: l.supportTitle,
                              help: l.supportHelp,
                              below: service.name,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ServerList(
                    state: state,
                    controller: controller,
                    focus: focus,
                  ),
                ],
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
/// button beside both; on the phone that button is an icon alone, then the fold arrow.
class _Head extends StatelessWidget {
  const _Head({
    required this.service,
    required this.refresh,
    required this.onRefresh,
    required this.isTV,
    required this.open,
    required this.onFold,
  });

  final ShikooService service;
  final ShikooRefresh refresh;
  final VoidCallback onRefresh;
  final bool isTV;
  final bool open;
  final VoidCallback onFold;

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
        if (isTV)
          ShikooButton(
            label: l.refresh,
            icon: ShikooIcon.refresh,
            busy: busy,
            onPressed: busy ? () {} : onRefresh,
          )
        else ...[
          ShikooIconButton(
            icon: ShikooIcon.refresh,
            label: l.refreshServers,
            color: t.c.textMuted,
            busy: busy,
            onPressed: busy ? () {} : onRefresh,
          ),
          // A bare icon in the mockup; its touch target reaches into the card's end inset.
          Pressable(
            shape: const StadiumBorder(),
            onPressed: onFold,
            builder: (context, _) => Semantics(
              button: true,
              expanded: open,
              label: service.name,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: Space.s2,
                  end: Space.s4,
                ),
                child: SizedBox(
                  height: ShikooSizes.touch,
                  child: SvgIcon(
                    open ? ShikooIcon.chevronUp : ShikooIcon.chevronDown,
                    size: t.s.icon,
                    color: t.c.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// `.svc-summary`: a folded card's volume and validity on one line.
class _Summary extends StatelessWidget {
  const _Summary({required this.service});

  final ShikooService service;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    String gb(int bytes) => localNumber(context, bytes / _gib, '#,##0.#');
    final total = service.totalBytes;
    final used = service.usedBytes;
    final expire = service.expire;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s1, bottom: Space.s2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${l.usedLabel} '),
            TextSpan(
              text: total > 0
                  ? '${gb(used)} ${l.ofTotalGb(gb(total))}'
                  : l.gb(gb(used)),
              style: total > 0 && used / total >= _nearlyUsed
                  ? TextStyle(color: t.c.warning, fontWeight: FontWeight.w700)
                  : null,
            ),
            if (expire != null)
              TextSpan(text: ' · ${l.validUntil(_date(context, l, expire))}'),
          ],
        ),
        style: t.text(t.s.bodySm, color: t.c.textMuted),
      ),
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
        : (ratio >= _nearlyUsed ? t.c.warning : t.c.primary);
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

/// `.list-head` and `.servers`. While the remote or a finger is on a row the order stays, so
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
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final state = widget.state;
    final byName = {for (final server in state.servers) server.name: server};
    final order = [...byName.keys];
    final kept = _held == null ? order : keepOrder(_held!, order);
    void hold(bool on) => setState(() => _held = on ? kept : null);
    final shown = [
      for (final name in kept)
        if (serverMatches(byName[name]!.label, _search.text)) name,
    ];
    final pinging = state.pinging;
    final muted = t.text(t.s.bodySm, color: t.c.textMuted);
    Widget line(String text) => Padding(
      padding: const EdgeInsets.all(Space.s2),
      child: Text(text, style: muted),
    );
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
                  child: state.isTV
                      ? Text.rich(
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
                                    ' · ${listEquals(kept, order) ? l.fastestFirst : l.sortsOnLeave}',
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        )
                      : _SearchField(controller: _search),
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
                ? line(l.loadingServers)
                : shown.isEmpty
                ? line(l.searchNoMatch)
                : Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    includeSemantics: false,
                    onFocusChange: hold,
                    child: Listener(
                      onPointerDown: (_) => hold(true),
                      onPointerUp: (_) => hold(false),
                      onPointerCancel: (_) => hold(false),
                      child: Column(
                        children: [
                          for (final name in shown)
                            ServerRow(
                              key: ValueKey(name),
                              server: byName[name]!,
                              selected: name == state.selected,
                              isNew: byName[name]!.fresh && !state.isTV,
                              focusNode: widget.focus.row(name),
                              onPressed: () => unawaited(
                                widget.controller.selectServer(name),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Persian and Arabic forms of a letter or digit, and Latin digits, find the same server.
String _fold(String text) => text
    .toLowerCase()
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('آ', 'ا')
    .replaceAllMapped(
      RegExp('[۰-۹٠-٩]'),
      (digit) => '${digit[0]!.codeUnitAt(0) & 0xF}',
    );

bool serverMatches(String label, String query) =>
    _fold(label).contains(_fold(query.trim()));

/// `.search`, phone only: the list narrows with every letter and keeps its ping order.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final active = controller.text.isNotEmpty;
    return Container(
      height: t.s.button,
      padding: EdgeInsetsDirectional.only(
        start: Space.s3,
        end: active ? 0 : Space.s3,
      ),
      decoration: ShapeDecoration(
        color: t.c.surfaceSunken,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: active
              ? BorderSide(color: t.c.outline, width: t.s.borderControl)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          SvgIcon(
            ShikooIcon.search,
            size: t.s.iconSm,
            color: active ? t.c.text : t.c.textMuted,
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              cursorColor: t.c.text,
              style: t.text(t.s.body),
              decoration: InputDecoration.collapsed(
                hintText: l.searchServers,
                hintStyle: t.text(t.s.bodySm, color: t.c.textMuted),
              ),
            ),
          ),
          if (active)
            Pressable(
              shape: const CircleBorder(),
              onPressed: controller.clear,
              builder: (context, _) => Semantics(
                button: true,
                label: l.clearSearch,
                child: SizedBox(
                  width: t.s.iconSm + 2 * Space.s3,
                  height: t.s.button,
                  child: Center(
                    child: SvgIcon(
                      ShikooIcon.x,
                      size: t.s.iconSm,
                      color: t.c.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
