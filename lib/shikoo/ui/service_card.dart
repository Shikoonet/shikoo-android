import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/ping.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/clock.dart';
import 'package:fl_clash/shikoo/ui/cores.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/jalali.dart';
import 'package:fl_clash/shikoo/ui/paste.dart';
import 'package:fl_clash/shikoo/ui/refresh_menu.dart';
import 'package:fl_clash/shikoo/ui/report.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/foundation.dart' show clampDouble, listEquals;
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

const _gib = 1024 * mebibyte;

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

/// The card nodes the remote is sent to by hand; a row by its server's name, wherever it sits.
class CardFocus {
  final renew = FocusNode();
  final ping = FocusNode();
  final refresh = FocusNode();
  final caret = FocusNode();
  final report = FocusNode();

  /// The failure message's other way.
  final other = FocusNode();
  // ponytail: a removed server's node lives until the page goes; prune if lists churn a lot.
  final _rows = <String, FocusNode>{};

  FocusNode row(String name) => _rows.putIfAbsent(name, FocusNode.new);

  void dispose() {
    renew.dispose();
    ping.dispose();
    refresh.dispose();
    caret.dispose();
    report.dispose();
    other.dispose();
    for (final node in _rows.values) {
      node.dispose();
    }
  }
}

/// `.card.svc` with its servers, as in `tv-ping.html`: name, status and the last update, the
/// update's result, volume and validity, the panel's announcement, renew once it has ended
/// (support is the top bar's), then the server list.
class ServiceCard extends StatefulWidget {
  const ServiceCard({
    super.key,
    required this.state,
    required this.controller,
    required this.focus,
    this.serviceId,
    this.bot,
    this.renews = true,
    this.other = false,
    this.inUse,
    this.onFold,
    this.tunnelServer,
  });

  final ShikooState state;
  final ShikooController controller;
  final CardFocus focus;

  /// The bot's id for the service, once sign-in brought it: renew opens that service alone.
  final int? serviceId;
  final String? bot;
  final bool renews;

  /// [state] is another service's, opened while the connection is on the one in use.
  final bool other;

  /// The in-use mark: none, green (connected) or grey.
  final bool? inUse;

  /// The phone's arrow; the TV folds an open card only by opening another.
  final VoidCallback? onFold;

  /// The server an update through the tunnel takes, when [state] selects none (another card).
  final String? tunnelServer;

  @override
  State<ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<ServiceCard> {
  /// A message leaving from above the list moves the remote's row up, under the top bar.
  @override
  void didUpdateWidget(ServiceCard old) {
    super.didUpdateWidget(old);
    final focused = FocusManager.instance.primaryFocus?.context;
    if (widget.state.isTV &&
        old.state.notice != null &&
        widget.state.notice == null &&
        focused != null) {
      revealWithRing(focused);
    }
  }

  /// The column brings the card's top under its top edge, as far as it can scroll.
  void _toTop() {
    final box = context.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (box is! RenderBox || position == null) return;
    final to =
        RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset -
        Space.s2;
    position.jumpTo(
      clampDouble(to, position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final ServiceCard(:state, :controller, :focus, :other, :inUse) = widget;
    final service = state.service;
    final notice = state.notice;
    final revoked = service?.revoked ?? false;
    final renews = !revoked && service?.ended != null && widget.renews;
    final busy = {
      ShikooConnection.on,
      ShikooConnection.connecting,
    }.contains(state.connection);
    final landed = state.landed?.id == service?.id ? state.landed : null;
    const inset = EdgeInsets.symmetric(horizontal: Space.s4);
    final onPing = service?.ended != null
        ? null
        : other
        ? () => controller.openService(service!.id)
        : () => unawaited(controller.pingAll());
    final connected = state.connection == ShikooConnection.on;
    final server = serverName(state.selected ?? widget.tunnelServer ?? '');
    void refresh([ShikooRoute? via]) => unawaited(
      other
          ? controller.refreshOther(service!.id, via: via)
          : controller.refreshService(via: via),
    );
    final head = service == null
        ? null
        : _Head(
            service: service,
            refreshNode: focus.refresh,
            caretNode: focus.caret,
            pingNode: focus.ping,
            refresh: state.refresh,
            onRefresh: refresh,
            onWay: refresh,
            connected: connected,
            server: server,
            onPing: onPing,
            pinging: state.pinging,
            isTV: state.isTV,
            onFold: widget.onFold,
            inUse: widget.onFold == null ? null : inUse,
            card: context,
          );
    return Container(
      padding: EdgeInsets.only(
        top: head != null && widget.onFold != null ? 0 : Space.s4,
        bottom: Space.s2,
      ),
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
                    state.isTV
                        ? l.noServiceTitleTv
                        : (shikooDesktop
                              ? l.noServiceTitleDesktop
                              : l.noServiceTitleTouch),
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
                    state.isTV
                        ? l.noServiceHelp
                        : (shikooDesktop
                              ? l.noServiceHelpPasteDesktop
                              : l.noServiceHelpPaste),
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
                    if (inside) _toTop();
                  },
                  child: Padding(
                    padding: state.isTV
                        ? inset
                        : const EdgeInsetsDirectional.only(start: Space.s4),
                    child: widget.onFold == null
                        ? InUseMark(live: inUse, child: head!)
                        : head!,
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
                      otherNode: focus.other,
                      connected: connected,
                      server: server,
                      onWay: refresh,
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
                // Unkeyed, a message appearing above rebuilt Renew and the remote fell off it.
                if (revoked || renews)
                  Padding(
                    key: const ValueKey('actions'),
                    padding: inset.copyWith(top: Space.s3),
                    child: revoked
                        ? ShikooButton(
                            label: l.removeService,
                            dangerText: true,
                            onPressed: () => unawaited(
                              confirmRemove(
                                context,
                                controller: controller,
                                service: service,
                                connected: busy,
                              ),
                            ),
                          )
                        : ShikooButton(
                            label: l.renew,
                            icon: state.isTV ? ShikooIcon.qr : null,
                            primary: true,
                            autofocus: state.isTV && restingFor(state) != null,
                            focusNode: focus.renew,
                            onPressed: () => openRenew(
                              context,
                              isTV: state.isTV,
                              bot: widget.bot,
                              id: widget.serviceId,
                              name: service.name,
                            ),
                          ),
                  ),
                if (service.ended == null &&
                    !state.isTV &&
                    (landed != null || (other && busy)))
                  Padding(
                    padding: inset.copyWith(top: Space.s3),
                    child: _Hint(now: landed?.arrived ?? false),
                  ),
                if (service.ended == null)
                  _ServerList(
                    state: state,
                    controller: controller,
                    focus: focus,
                    other: other,
                  )
                else if (!revoked)
                  Padding(
                    padding: inset.copyWith(top: Space.s3, bottom: Space.s2),
                    child: Text(
                      widget.renews
                          ? l.serversAfterRenew
                          : l.summaryNotRenewable,
                      style: t.text(t.s.bodySm, color: t.c.textMuted),
                    ),
                  ),
              ],
      ),
    );
  }
}

/// `.svc.is-in-use` (phone-p2b-home): «در حال استفاده» over the name and a bar on the card's
/// start edge beside the head, green while connected, grey otherwise (`.is-idle`), or [color].
/// Without a mark [child] keeps its place in the tree, so the remote on it stays when the mark comes.
class InUseMark extends StatelessWidget {
  const InUseMark({
    super.key,
    required this.live,
    this.color,
    required this.child,
  });

  final bool? live;
  final Color? color;
  final Widget child;

  static Widget label(BuildContext context, bool live, [Color? color]) {
    final t = ShikooTheme.of(context);
    return Text(
      ShikooL10n.of(context).inUseLabel,
      style: t.text(
        t.s.caption,
        weight: FontWeight.w700,
        color: color ?? (live ? t.c.inUse : t.c.textMuted),
        height: Leading.tight,
      ),
    );
  }

  /// On the card's start edge, from [top] down.
  static Widget bar(
    BuildContext context,
    bool live, {
    Color? color,
    double top = 0,
  }) {
    final t = ShikooTheme.of(context);
    return PositionedDirectional(
      start: -Space.s4,
      top: top,
      bottom: 0,
      child: Container(
        width: ShikooSizes.selectedBar,
        decoration: ShapeDecoration(
          color: color ?? (live ? t.c.inUse : t.c.inUseIdle),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = this.live;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [?live == null ? null : label(context, live, color), child],
        ),
        if (live != null) bar(context, live, color: color),
      ],
    );
  }
}

/// The phone's fold arrow, folded or open in the same place: an icon, as the whole head is the button.
Widget _foldArrow(ShikooTheme t, {required bool open}) => Padding(
  padding: const EdgeInsetsDirectional.only(start: Space.s2, end: Space.s4),
  child: SvgIcon(
    open ? ShikooIcon.chevronUp : ShikooIcon.chevronDown,
    size: t.s.icon,
    color: t.c.textMuted,
  ),
);

/// `.notice.msg.hint` above another service's list: what a tap there does, then, once one did,
/// `.positive` that it did. One box as tall as the taller text, so no row under it moves.
class _Hint extends StatelessWidget {
  const _Hint({required this.now});

  final bool now;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final color = now ? t.c.positive : t.c.textMuted;
    final style = t.text(
      t.s.bodySm,
      color: now ? t.c.positive : null,
      height: Leading.body,
    );
    final hint = shikooDesktop ? l.otherServiceHintDesktop : l.otherServiceHint;
    final [shown, hidden] = now
        ? [l.otherServiceNow, hint]
        : [hint, l.otherServiceNow];
    return Container(
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
        spacing: Space.s2,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top:
                  (MediaQuery.textScalerOf(context).scale(t.s.bodySm) *
                          Leading.body -
                      t.s.iconSm) /
                  2,
            ),
            child: SvgIcon(
              now ? ShikooIcon.check : ShikooIcon.power,
              size: t.s.iconSm,
              color: color,
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ExcludeSemantics(
                  child: Visibility.maintain(
                    visible: false,
                    child: Text(hidden, style: style),
                  ),
                ),
                Text(shown, style: style),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A folded `.card.svc` (phone-p2b-home, tv-p2b-home): the name and `.svc-summary`, nothing to
/// press but the card itself, which opens it; on the TV one remote stop.
class FoldedServiceCard extends StatelessWidget {
  const FoldedServiceCard({
    super.key,
    required this.service,
    required this.isTV,
    required this.onOpen,
    this.renews = true,
    this.inUse,
    this.focusNode,
  });

  final ShikooService service;
  final bool isTV;
  final VoidCallback onOpen;
  final bool renews;

  /// The in-use mark: none, green (connected) or grey.
  final bool? inUse;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
    );
    final arrow = SvgIcon(
      ShikooIcon.chevronDown,
      size: t.s.icon,
      color: t.c.textMuted,
    );
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NameLine(
          service: service,
          arrow: isTV ? arrow : _foldArrow(t, open: false),
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(
            top: Space.s1,
            bottom: Space.s2,
            end: isTV ? 0 : Space.s4,
          ),
          child: _Summary(service: service, renews: renews),
        ),
      ],
    );
    Widget card(bool focused) => Semantics(
      button: true,
      expanded: false,
      child: Container(
        padding: const EdgeInsets.only(top: Space.s4, bottom: Space.s2),
        decoration: ShapeDecoration(
          color: focused ? t.c.focusBg : t.c.surface,
          shadows: focused ? t.c.raisedShadow : t.c.cardShadow,
          shape: shape,
        ),
        child: Padding(
          padding: isTV
              ? const EdgeInsets.symmetric(horizontal: Space.s4)
              : const EdgeInsetsDirectional.only(start: Space.s4),
          child: InUseMark(live: inUse, child: head),
        ),
      ),
    );
    if (!isTV) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: card(false),
      );
    }
    return Pressable(
      shape: shape,
      focusNode: focusNode,
      onPressed: onOpen,
      builder: (context, focused) => card(focused),
    );
  }
}

/// `.svc-line` in `.svc-head.is-stacked`: the name has the row to itself but the fold arrow.
class _NameLine extends StatelessWidget {
  const _NameLine({required this.service, this.arrow});

  final ShikooService service;
  final Widget? arrow;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ServiceName(plainTitle(context, service), twoLines: true),
      ),
      ?arrow,
    ],
  );
}

/// `.svc-row`: the status, [text] and [end]'s buttons on one line; [text] goes alone onto the next
/// line, full width, when it does not fit between them (`.is-narrow`).
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.service, required this.end, this.text});

  final ShikooService service;
  final List<Widget> end;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final text = this.text;
    return _RowOrUnder(
      children: [
        if (service.usageKnown)
          StatusChip(status: service.statusAt(shikooNow()))
        else
          const SizedBox.shrink(),
        if (text != null)
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.text(t.s.bodySm, color: t.c.textMuted),
          )
        else
          const SizedBox.shrink(),
        Row(mainAxisSize: MainAxisSize.min, spacing: Space.s2, children: end),
      ],
    );
  }
}

/// Lead and end on a line, centred on the taller; the middle child between them when its widest
/// fits, else under them. Rows and Wraps cannot give the middle the full width only when it moves.
class _RowOrUnder extends MultiChildRenderObjectWidget {
  const _RowOrUnder({required super.children}) : assert(children.length == 3);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRowOrUnder(Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderRowOrUnder row) =>
      row.direction = Directionality.of(context);
}

class _RenderRowOrUnder extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  _RenderRowOrUnder(this._direction);

  TextDirection _direction;

  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  @override
  void performLayout() {
    final [lead, middle, end] = getChildrenAsList();
    final width = constraints.maxWidth;
    lead.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    end.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    double gap(RenderBox box) => box.size.width > 0 ? Space.s2 : 0;
    final room =
        width - lead.size.width - gap(lead) - end.size.width - gap(end);
    final inline = middle.getMaxIntrinsicWidth(double.infinity) <= room;
    middle.layout(
      BoxConstraints(maxWidth: inline ? room : width),
      parentUsesSize: true,
    );
    final line = [
      lead.size.height,
      end.size.height,
      if (inline) middle.size.height,
    ].reduce(math.max);
    void place(RenderBox box, double x, double y) =>
        (box.parentData! as MultiChildLayoutParentData).offset = Offset(
          _direction == TextDirection.rtl ? width - x - box.size.width : x,
          y,
        );
    place(lead, 0, (line - lead.size.height) / 2);
    place(end, width - end.size.width, (line - end.size.height) / 2);
    if (inline) {
      place(
        middle,
        lead.size.width + gap(lead),
        (line - middle.size.height) / 2,
      );
    } else {
      place(middle, 0, line);
    }
    size = constraints.constrain(
      Size(width, inline ? line : line + middle.size.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

String agoText(ShikooL10n l, Duration ago) {
  if (ago.inMinutes < 1) return l.agoJustNow;
  if (ago.inHours < 1) return l.agoMinutes(ago.inMinutes);
  if (ago.inDays < 1) return l.agoHours(ago.inHours);
  return l.agoDays(ago.inDays);
}

/// `.svc-head.is-stacked`: `.svc-line` with the fold arrow on the phone, then `.svc-row`: the
/// status, `.svc-sub` (the last update or the ping's count), update and ping, one at a time; on
/// the phone each an icon alone.
class _Head extends StatelessWidget {
  const _Head({
    required this.service,
    this.refreshNode,
    this.caretNode,
    this.pingNode,
    required this.refresh,
    required this.onRefresh,
    required this.onWay,
    required this.connected,
    required this.server,
    this.onPing,
    this.pinging,
    required this.isTV,
    this.onFold,
    this.inUse,
    this.card,
  });

  final ShikooService service;
  final FocusNode? refreshNode;
  final FocusNode? caretNode;
  final FocusNode? pingNode;
  final ShikooRefresh refresh;
  final VoidCallback onRefresh;
  final void Function(ShikooRoute way) onWay;
  final bool connected;
  final String server;
  final VoidCallback? onPing;
  final ({int done, int total})? pinging;
  final bool isTV;

  /// The phone's: from the card's top edge to under the name folds the card.
  final VoidCallback? onFold;

  /// The phone's in-use mark, inside the fold button; the TV's is [InUseMark] around the head.
  final bool? inUse;
  final BuildContext? card;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final updatedAt = service.updatedAt;
    final since = updatedAt == null
        ? null
        : DateTime.now().difference(updatedAt);
    final ago = since == null ? null : agoText(l, since);
    final pinging = this.pinging;
    final sub = switch (refresh) {
      _ when pinging != null => l.pingProgress(pinging.done, pinging.total),
      _ when service.revoked => l.updateFailed,
      ShikooRefresh.running when service.bridgeLeg => l.updatingWarp,
      ShikooRefresh.running => switch (service.leg) {
        ShikooLeg.server => l.updatingViaServer,
        ShikooLeg.fallback => l.updatingFallback,
        ShikooLeg.direct || ShikooLeg.directOff => l.updatingDirect,
        null => l.updating,
      },
      ShikooRefresh.failed when since == null || since.inMinutes < 1 =>
        l.updateFailed,
      ShikooRefresh.failed => l.updateFailedAgo(ago!),
      _ when ago != null => l.updatedAgo(ago),
      _ => null,
    };
    final busy = refresh == ShikooRefresh.running;
    final measuring = pinging != null;
    final onPing = this.onPing;
    final ping = onPing == null || busy ? null : (measuring ? () {} : onPing);
    final controls = RefreshControls(
      isTV: isTV,
      busy: busy,
      enabled: !measuring,
      connected: connected,
      server: server,
      refreshNode: refreshNode,
      caretNode: caretNode,
      onRefresh: onRefresh,
      onWay: onWay,
      card: card,
    );
    final buttons = isTV
        ? [
            controls,
            if (onPing != null)
              ShikooButton(
                label: l.ping,
                icon: ShikooIcon.gauge,
                busy: measuring,
                focusNode: pingNode,
                onPressed: ping,
              ),
          ]
        : [
            controls,
            if (onPing != null)
              ShikooIconButton(
                icon: ShikooIcon.gauge,
                label: l.pingServers,
                color: t.c.textMuted,
                busy: measuring,
                onPressed: ping,
              ),
          ];
    final status = Padding(
      padding: EdgeInsetsDirectional.only(end: isTV ? 0 : Space.s4),
      child: _StatusRow(service: service, text: sub, end: buttons),
    );
    final onFold = this.onFold;
    if (onFold == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NameLine(service: service),
          status,
        ],
      );
    }
    final live = inUse;
    final title = serviceTitle(context, service);
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: true,
          label: live == null ? title : '${l.inUseLabel}\n$title',
          excludeSemantics: true,
          onTap: onFold,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onFold,
            child: Container(
              constraints: const BoxConstraints(minHeight: ShikooSizes.touch),
              padding: const EdgeInsets.only(top: Space.s4),
              alignment: AlignmentDirectional.topStart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?live == null ? null : InUseMark.label(context, live),
                  _NameLine(service: service, arrow: _foldArrow(t, open: true)),
                ],
              ),
            ),
          ),
        ),
        status,
      ],
    );
    if (live == null) return head;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        head,
        InUseMark.bar(context, live, top: Space.s4),
      ],
    );
  }
}

/// `.svc-row` with `.svc-summary`: the status, then volume and validity, which breaks only
/// before «·», as a name does ([bidiName]).
class _Summary extends StatelessWidget {
  const _Summary({required this.service, required this.renews});

  final ShikooService service;
  final bool renews;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    if (!service.usageKnown && !service.revoked) return const SizedBox.shrink();
    String whole(String text) => text.replaceAll(' ', '\u00A0');
    String gb(int bytes) => localNumber(context, bytes / _gib, '#,##0.#');
    final total = service.totalBytes;
    final used = service.usedBytes;
    final expire = service.expire;
    final List<InlineSpan> text = switch (service.ended) {
      ShikooServiceStatus.revoked => [TextSpan(text: l.revokedHelp)],
      ShikooServiceStatus.expired || ShikooServiceStatus.exhausted
          when !renews =>
        [TextSpan(text: l.summaryNotRenewable)],
      ShikooServiceStatus.expired => [
        TextSpan(text: l.summaryExpired(_date(context, l, expire!))),
      ],
      ShikooServiceStatus.exhausted => [TextSpan(text: l.summaryExhausted)],
      _ => [
        TextSpan(text: whole('${l.usedLabel} ')),
        TextSpan(
          text: whole(
            total > 0
                ? '${gb(used)} ${l.ofTotalGb(gb(total))}'
                : l.gb(gb(used)),
          ),
          style: total > 0 && used / total >= _nearlyUsed
              ? TextStyle(color: t.c.warning, fontWeight: FontWeight.w700)
              : null,
        ),
        if (expire != null)
          TextSpan(
            text: ' ${whole('· ${l.validUntil(_date(context, l, expire))}')}',
          ),
      ],
    };
    return Row(
      spacing: Space.s2,
      children: [
        if (service.usageKnown)
          StatusChip(status: service.statusAt(shikooNow())),
        Expanded(
          child: Text.rich(
            TextSpan(children: text),
            style: t.text(
              t.s.bodySm,
              color: t.c.textMuted,
              height: Leading.tight,
            ),
          ),
        ),
      ],
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
    required this.otherNode,
    required this.connected,
    required this.server,
    required this.onWay,
  });

  final ShikooNotice notice;
  final bool isTV;
  final FocusNode reportNode;
  final FocusNode otherNode;
  final bool connected;
  final String server;
  final void Function(ShikooRoute way) onWay;

  @override
  Widget build(BuildContext context) {
    final l = ShikooL10n.of(context);
    final danger = notice is RefreshFailed;
    final clock = notice is RefreshFailed && (notice as RefreshFailed).clock;
    final name = switch (notice) {
      RefreshFailed(server: final server?) => serverName(server),
      _ => server,
    };
    final otherWay = switch (notice) {
      RefreshFailed(clock: false, way: ShikooFailedWay.direct) when connected =>
        ShikooRoute.server,
      RefreshFailed(clock: false, way: ShikooFailedWay.server) =>
        ShikooRoute.direct,
      _ => null,
    };
    final (strong, rest) = switch (notice) {
      RefreshFailed(clock: true) => (l.clockWrongTitle, l.clockWrongHelp),
      RefreshFailed(bridge: true) => (l.updateFailedTitle, l.updateFailedWarp),
      RefreshFailed(:final way) => (
        l.updateFailedTitle,
        switch (way) {
          ShikooFailedWay.directOff =>
            shikooDesktop
                ? l.updateFailedDirectOffDesktop
                : l.updateFailedDirectOff,
          ShikooFailedWay.direct =>
            shikooDesktop ? l.updateFailedDirectDesktop : l.updateFailedDirect,
          ShikooFailedWay.server => l.updateFailedViaServer(name),
          ShikooFailedWay.both => l.updateFailedBoth(name),
          ShikooFailedWay.panel =>
            shikooDesktop ? l.updateFailedPanelDesktop : l.updateFailedPanel,
          ShikooFailedWay.notConnected => l.updateFailedConnectFirst,
        },
      ),
      SelectedReplaced(
        :final removed,
        :final replacement,
        :final moved,
        :final fastest,
      ) =>
        (
          l.selectedRemoved(serverName(removed)),
          !fastest
              ? l.selectedMovedFirst(serverName(replacement))
              : moved
              ? l.selectedMoved(serverName(replacement))
              : l.selectedReplaced(serverName(replacement)),
        ),
      SilentReplaced(:final silent, :final replacement, :final moved) => (
        l.selectedNoAnswer(serverName(silent)),
        moved
            ? l.selectedMoved(serverName(replacement))
            : l.selectedReplaced(serverName(replacement)),
      ),
      ServersChanged(:final added, :final removed) => (
        [
          if (added > 0) l.serversAdded(added),
          if (removed.length == 1) l.serverRemoved(serverName(removed.first)),
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
    final other = otherWay == null
        ? null
        : ShikooButton(
            label: otherWay == ShikooRoute.direct
                ? l.refreshDirect
                : l.refreshViaServer,
            icon: otherWay == ShikooRoute.direct
                ? ShikooIcon.wifi
                : ShikooIcon.shield,
            small: !isTV,
            focusNode: otherNode,
            onPressed: () => onWay(otherWay),
          );
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
            Wrap(
              spacing: Space.s3,
              runSpacing: Space.s2,
              children: [
                ?other,
                ShikooButton(
                  label: l.reportSendToSupport,
                  icon: ShikooIcon.report,
                  focusNode: reportNode,
                  onPressed: report,
                ),
              ],
            )
          else if (danger && other != null)
            Wrap(
              spacing: Space.s3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                other,
                IntrinsicWidth(
                  child: LinkButton(
                    label: l.reportSendToSupport,
                    onPressed: report,
                  ),
                ),
              ],
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
              prose: true,
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
    required this.other,
  });

  final ShikooState state;
  final ShikooController controller;
  final CardFocus focus;
  final bool other;

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
    final muted = t.text(t.s.bodySm, color: t.c.textMuted);
    final busy = {
      ShikooConnection.on,
      ShikooConnection.connecting,
    }.contains(state.connection);
    final caption = widget.other && busy
        ? l.otherServiceCaptionTv
        : !state.sorted && state.pinging == null
        ? l.sortsOnPing
        : (listEquals(kept, order) ? l.fastestFirst : l.sortsOnLeave);
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
                        TextSpan(text: ' · $caption'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  )
                : _SearchField(controller: _search),
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
                                  via: byName[name]!.viaBridge
                                      ? l.warpVia
                                      : viaLabel(l, byName[name]!, state.cores),
                                  trying:
                                      state.bridge.trying &&
                                      byName[name]!.viaBridge &&
                                      (byName[name]!.ping ?? -1) < 0,
                                  focusNode: widget.focus.row(name),
                                  onPressed: () => unawaited(
                                    widget.controller.selectServer(
                                      name,
                                      service: widget.other
                                          ? state.service?.id
                                          : null,
                                    ),
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
