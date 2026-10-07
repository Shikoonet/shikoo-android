import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/naming.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/ping.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/clock.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/jalali.dart';
import 'package:fl_clash/shikoo/ui/paste.dart';
import 'package:fl_clash/shikoo/ui/report.dart';
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

/// Used up or past its date, and not connected: the power button rests until renewal.
ShikooServiceStatus? restingFor(ShikooState state) {
  final status = state.service?.ended;
  final busy = {ShikooConnection.on, ShikooConnection.connecting};
  return busy.contains(state.connection) ? null : status;
}

/// The card nodes the remote is sent to by hand: one per server name, so a row is found
/// wherever it sits, and the two buttons that geometry alone would skip.
class CardFocus {
  final renew = FocusNode();
  final pingAll = FocusNode();
  final refresh = FocusNode();
  final report = FocusNode();
  // ponytail: a removed server's node lives until the page goes; prune if lists churn a lot.
  final _rows = <String, FocusNode>{};

  FocusNode row(String name) => _rows.putIfAbsent(name, FocusNode.new);

  void dispose() {
    renew.dispose();
    pingAll.dispose();
    refresh.dispose();
    report.dispose();
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
    this.serviceId,
    this.bot,
  });

  final ShikooState state;
  final ShikooController controller;
  final CardFocus focus;

  /// The bot's id for the service, once sign-in brought it: renew opens that service alone.
  final int? serviceId;
  final String? bot;

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
    final revoked = service?.revoked ?? false;
    const inset = EdgeInsets.symmetric(horizontal: Space.s4);
    if (service != null && !_open && !state.isTV) {
      return FoldedServiceCard(
        service: service,
        refresh: state.refresh,
        isTV: false,
        onOpen: () => setState(() => _open = true),
        onRefresh: () => unawaited(controller.refreshService()),
      );
    }
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
                    state.isTV ? l.noServiceHelp : l.noServiceHelpPaste,
                    style: t.text(
                      t.s.bodySm,
                      color: t.c.textMuted,
                      height: Leading.body,
                    ),
                  ),
                ),
                Padding(
                  padding: inset.copyWith(top: Space.s3, bottom: Space.s2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.s3,
                    children: [
                      if (!state.isTV)
                        PasteLink(
                          builder: (context, busy, paste) => ShikooButton(
                            label: busy ? l.pasteChecking : l.pasteLink,
                            icon: ShikooIcon.paste,
                            primary: true,
                            busy: busy,
                            onPressed: paste,
                          ),
                        ),
                      ShikooButton(
                        label: l.support,
                        icon: state.isTV ? ShikooIcon.qr : null,
                        onPressed: () => unawaited(
                          openSupport(
                            context,
                            isTV: state.isTV,
                            trigger: 'support',
                          ),
                        ),
                      ),
                    ],
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
                      refreshNode: focus.refresh,
                      refresh: state.refresh,
                      onRefresh: () => unawaited(controller.refreshService()),
                      isTV: state.isTV,
                      open: true,
                      onFold: () => setState(() => _open = false),
                    ),
                  ),
                ),
                if (revoked)
                  Padding(
                    padding: inset.copyWith(top: Space.s3),
                    child: MessageBox(
                      icon: ShikooIcon.alert,
                      strong: l.revokedTitle,
                      rest: l.revokedHelp,
                      danger: true,
                    ),
                  ),
                if (notice != null && !revoked)
                  Padding(
                    padding: inset,
                    child: _Message(
                      notice: notice,
                      isTV: state.isTV,
                      reportNode: focus.report,
                    ),
                  ),
                if (service.usageKnown && !revoked)
                  Padding(
                    padding: inset,
                    child: _Usage(service: service),
                  ),
                if (service.announce != null && !revoked)
                  Padding(
                    padding: inset,
                    child: _Notice(text: service.announce!),
                  ),
                Padding(
                  padding: inset.copyWith(top: Space.s3),
                  child: Row(
                    children: [
                      if (revoked)
                        Expanded(
                          child: ShikooButton(
                            label: l.removeService,
                            dangerText: true,
                            onPressed: () => unawaited(
                              confirmRemove(
                                context,
                                controller: controller,
                                service: service,
                                connected: {
                                  ShikooConnection.on,
                                  ShikooConnection.connecting,
                                }.contains(state.connection),
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ShikooButton(
                            label: l.renew,
                            icon: state.isTV ? ShikooIcon.qr : null,
                            primary: true,
                            autofocus: state.isTV && restingFor(state) != null,
                            focusNode: focus.renew,
                            onPressed: () => switch (widget.serviceId) {
                              final id? => openLink(
                                context,
                                isTV: state.isTV,
                                link: ShikooLinks.renewOne(id, widget.bot),
                                title: l.renewTitle,
                                help: l.renewHelpDirect,
                              ),
                              null => openLink(
                                context,
                                isTV: state.isTV,
                                link: ShikooLinks.renew,
                                title: l.renewTitle,
                                help: l.renewHelpList,
                                below: l.renewPickInList(
                                  bidiName(service.username),
                                ),
                                strong: service.username,
                              ),
                            },
                          ),
                        ),
                      const SizedBox(width: Space.s2),
                      Expanded(
                        child: ShikooButton(
                          label: l.support,
                          icon: state.isTV ? ShikooIcon.qr : null,
                          onPressed: () => unawaited(
                            openSupport(
                              context,
                              isTV: state.isTV,
                              link: service.supportLink,
                              below: serviceTitle(context, service),
                              trigger: 'support',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (service.ended == null)
                  _ServerList(
                    state: state,
                    controller: controller,
                    focus: focus,
                  )
                else if (!revoked)
                  Padding(
                    padding: inset.copyWith(top: Space.s3, bottom: Space.s2),
                    child: Text(
                      l.serversAfterRenew,
                      style: t.text(t.s.bodySm, color: t.c.textMuted),
                    ),
                  ),
              ],
      ),
    );
  }
}

/// A folded `.card.svc` (phone-home-long, tv-home-long): the head and `.svc-summary`. On the
/// phone a tap anywhere but the update button opens it; on the TV the whole card is one item.
class FoldedServiceCard extends StatelessWidget {
  const FoldedServiceCard({
    super.key,
    required this.service,
    required this.refresh,
    required this.isTV,
    required this.onOpen,
    this.onRefresh,
  });

  final ShikooService service;
  final ShikooRefresh refresh;
  final bool isTV;
  final VoidCallback onOpen;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    const inset = EdgeInsets.symmetric(horizontal: Space.s4);
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
    );
    final head = isTV
        ? Row(
            spacing: Space.s2,
            children: [
              Expanded(child: _NameLine(service: service)),
              SvgIcon(
                ShikooIcon.chevronDown,
                size: t.s.icon,
                color: t.c.textMuted,
              ),
            ],
          )
        : _Head(
            service: service,
            refresh: refresh,
            onRefresh: onRefresh ?? () {},
            isTV: false,
            open: false,
            onFold: onOpen,
          );
    Widget card(bool focused) => Container(
      padding: const EdgeInsets.only(top: Space.s4, bottom: Space.s2),
      decoration: ShapeDecoration(
        color: focused ? t.c.focusBg : t.c.surface,
        shadows: focused ? t.c.raisedShadow : t.c.cardShadow,
        shape: shape,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: isTV
                ? inset
                : const EdgeInsetsDirectional.only(start: Space.s4),
            child: head,
          ),
          Padding(
            padding: inset,
            child: _Summary(service: service),
          ),
        ],
      ),
    );
    return isTV
        ? Pressable(
            shape: shape,
            onPressed: onOpen,
            builder: (context, focused) => card(focused),
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: card(false),
          );
  }
}

/// `.svc-line`: the name, then the status; what does not fit goes down, the status first.
class _NameLine extends StatelessWidget {
  const _NameLine({required this.service});

  final ShikooService service;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.s2,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ServiceName(plainTitle(context, service)),
      if (service.usageKnown) StatusChip(status: service.statusAt(shikooNow())),
    ],
  );
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
    this.refreshNode,
    required this.refresh,
    required this.onRefresh,
    required this.isTV,
    required this.open,
    required this.onFold,
  });

  final ShikooService service;
  final FocusNode? refreshNode;
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
      _ when service.revoked => l.updateFailed,
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
              _NameLine(service: service),
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
            focusNode: refreshNode,
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
              label: serviceTitle(context, service),
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
    if (!service.usageKnown && !service.revoked) {
      return const SizedBox(height: Space.s2);
    }
    final ended = service.ended;
    if (ended != null) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.s1, bottom: Space.s2),
        child: Text(switch (ended) {
          ShikooServiceStatus.revoked => l.revokedHelp,
          ShikooServiceStatus.expired => l.summaryExpired(
            _date(context, l, service.expire!),
          ),
          _ => l.summaryExhausted,
        }, style: t.text(t.s.bodySm, color: t.c.textMuted)),
      );
    }
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
  const _Message({
    required this.notice,
    required this.isTV,
    required this.reportNode,
  });

  final ShikooNotice notice;
  final bool isTV;
  final FocusNode reportNode;

  @override
  Widget build(BuildContext context) {
    final l = ShikooL10n.of(context);
    final danger = notice is RefreshFailed;
    final clock = notice is RefreshFailed && (notice as RefreshFailed).clock;
    final (strong, rest) = switch (notice) {
      RefreshFailed(clock: true) => (l.clockWrongTitle, l.clockWrongHelp),
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
    final box = MessageBox(
      icon: danger ? ShikooIcon.alert : ShikooIcon.refresh,
      strong: strong,
      rest: rest,
      danger: danger,
    );
    void report() => unawaited(openReport(context, 'refresh'));
    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.s2,
        children: [
          box,
          if (clock)
            const DateSettingsButton()
          else if (danger && isTV)
            ShikooButton(
              label: l.reportSendToSupport,
              icon: ShikooIcon.report,
              focusNode: reportNode,
              onPressed: report,
            )
          else if (danger)
            LinkButton(
              label: l.reportSendToSupport,
              alignment: AlignmentDirectional.centerStart,
              onPressed: report,
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
    final danger = TextStyle(color: t.c.danger, fontWeight: FontWeight.w700);
    final warning = TextStyle(color: t.c.warning, fontWeight: FontWeight.w700);
    final ended = service.ended;
    final expired = ended == ShikooServiceStatus.expired;
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
                        ? l
                              .gb(gb(math.max(total - used, 0)))
                              .replaceAll(' ', '\u00A0')
                        : l.unlimited,
                    style: ended == ShikooServiceStatus.exhausted
                        ? danger
                        : (ratio >= _nearlyUsed ? warning : strong),
                  ),
                ],
              ),
              style: muted,
            ),
          ]),
          if (total > 0) ...[
            const SizedBox(height: Space.s2),
            MeterBar(ratio: ratio),
          ],
          if (expire != null) ...[
            const SizedBox(height: Space.s2),
            row([
              Text(
                l.validUntil(_date(context, l, expire)),
                style: expired ? muted.merge(danger) : muted,
              ),
              Text(
                expired
                    ? l.expiredEnded
                    : l.daysLeft(
                        math.max(
                          0,
                          (expire.difference(shikooNow()).inHours / 24).ceil(),
                        ),
                      ),
                style: expired ? muted.merge(danger) : muted,
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// `.bar`: fills from the start edge; for usage, amber from 90% and red when used up.
class MeterBar extends StatelessWidget {
  const MeterBar({super.key, required this.ratio, this.usage = true});

  final double ratio;
  final bool usage;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final fill = !usage
        ? t.c.primary
        : ratio >= 1
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
    // Rows slide to a new order, so each takes one height: the row's, or its text's at a large size.
    final extent = math.max(
      t.s.row,
      2 * Space.s2 +
          math.max(
            t.s.icon,
            MediaQuery.textScalerOf(context).scale(t.s.body) * Leading.tight,
          ),
    );
    final move = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
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
            child: _ListHead(
              search: state.isTV
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
              wrap: !state.isTV,
              pingAll: ShikooButton(
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
                      child: SizedBox(
                        height: extent * shown.length,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final (i, name) in shown.indexed)
                              AnimatedPositioned(
                                key: ValueKey(name),
                                duration: move,
                                curve: Curves.easeOut,
                                top: i * extent,
                                left: 0,
                                right: 0,
                                height: extent,
                                child: ServerRow(
                                  server: byName[name]!,
                                  selected: name == state.selected,
                                  isNew: byName[name]!.fresh && !state.isTV,
                                  focusNode: widget.focus.row(name),
                                  onPressed: () => unawaited(
                                    widget.controller.selectServer(name),
                                  ),
                                ),
                              ),
                          ],
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

/// `.list-head`: at a large text size the phone's search takes its own line, as `flex: 1 1 10em`,
/// and ping-all goes under it.
class _ListHead extends StatelessWidget {
  const _ListHead({
    required this.search,
    required this.pingAll,
    required this.wrap,
  });

  final Widget search;
  final Widget pingAll;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final label = TextPainter(
          text: TextSpan(
            text: ShikooL10n.of(context).pingAll,
            style: t.text(t.s.body, weight: FontWeight.w700),
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        final ping = label.width + t.s.icon + 3 * Space.s4;
        label.dispose();
        if (!wrap || box.maxWidth - ping >= 10 * scaler.scale(t.s.bodySm)) {
          return Row(
            spacing: Space.s2,
            children: [
              Expanded(child: search),
              pingAll,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.s2,
          children: [search, pingAll],
        );
      },
    );
  }
}

/// Arabic and Persian forms of a letter or digit, Latin digits, and any spacing find the
/// same server.
String _fold(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[\u064A\u0649]'), '\u06CC')
    .replaceAll('\u0643', '\u06A9')
    .replaceAll(RegExp('[\u0622\u0623\u0625]'), '\u0627')
    .replaceAll('\u0629', '\u0647')
    .replaceAll(RegExp(r'[\s\u200C]'), '')
    .replaceAllMapped(
      RegExp('[\u06F0-\u06F9\u0660-\u0669]'),
      (digit) => '${digit[0]!.codeUnitAt(0) & 0xF}',
    );

bool serverMatches(String label, String query) =>
    _fold(label).contains(_fold(query.trim()));

/// `.search`, phone only: the list narrows with every letter and keeps its ping order.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField>
    with WidgetsBindingObserver {
  final _focus = FocusNode();
  bool _keyboard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Scaffold hides the keyboard from its body's MediaQuery; the view still sees it.
  @override
  void didChangeMetrics() {
    final keyboard = View.of(context).viewInsets.bottom > 0;
    if (_keyboard && !keyboard) _focus.unfocus();
    _keyboard = keyboard;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final controller = widget.controller;
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
              focusNode: _focus,
              onTapOutside: (_) => _focus.unfocus(),
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
