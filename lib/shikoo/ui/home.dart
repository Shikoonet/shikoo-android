import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/focus.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const finishedMaxDays = 30;

/// A row of «سرویس‌های تمام‌شده»: a used-up or expired service of this device ([profileId]) or
/// one of the account with no link here ([linked]).
typedef Finished = ({
  String name,
  bool exhausted,
  DateTime? ended,
  int? renewId,
  int? profileId,
  LinkedService? linked,
});

/// The latest end first and those without a date last; one that ended over [finishedMaxDays]
/// ago, used up or not, is left out.
List<Finished> finishedOrder(Iterable<Finished> all, DateTime now) {
  final shown = [
    for (final row in all)
      if (row.ended == null ||
          now.difference(row.ended!) <= const Duration(days: finishedMaxDays))
        row,
  ];
  mergeSort(
    shown,
    compare: (a, b) => switch ((a.ended, b.ended)) {
      (final x?, final y?) => y.compareTo(x),
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
    },
  );
  return shown;
}

String finishedStatus(ShikooL10n l, Finished row, DateTime now) {
  final ended = row.ended;
  if (row.exhausted) return l.finishedData;
  if (ended == null) return l.finishedNoDate;
  final days = DateUtils.dateOnly(
    now,
  ).difference(DateUtils.dateOnly(ended)).inDays;
  return days < 1 ? l.finishedToday : l.finishedDaysAgo(days);
}

/// Home, laid out after `design/mockups/tv.html` (frames `tv-home-*`) and `phone.html`.
class ShikooHome extends ConsumerStatefulWidget {
  const ShikooHome({super.key});

  @override
  ConsumerState<ShikooHome> createState() => _ShikooHomeState();
}

class _ShikooHomeState extends ConsumerState<ShikooHome> {
  final _card = CardFocus();
  final _power = FocusNode();
  final _settings = FocusNode();
  final _linkless = FocusNode();
  final _scroll = ScrollController();
  (int?, bool, bool)? _shown;

  @override
  void dispose() {
    _card.dispose();
    _power.dispose();
    _settings.dispose();
    _linkless.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// phone-home-long: the chosen service opens at the top, under the power button.
  void _use(ShikooController controller, int service) {
    controller.selectService(service);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// So the remote never stays on a button that just went away or went dead.
  void _focusFirst(ShikooState state, {required bool linkless}) {
    final service = state.service;
    final shown = (service?.id, restingFor(state) != null, linkless);
    if (!state.isTV || shown == _shown) return;
    _shown = shown;
    final first = linkless
        ? _linkless
        : (service != null ? (shown.$2 ? _card.renew : _power) : _settings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (ModalRoute.isCurrentOf(context) ?? true)) {
        first.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shikooStateProvider);
    final controller = ref.watch(shikooControllerProvider);
    final account = ref.watch(shikooAccountProvider);
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final now = DateTime.now();
    final current = state.service;
    final unlinked = account.withoutLink;
    bool done(ShikooService service) => {
      ShikooServiceStatus.exhausted,
      ShikooServiceStatus.expired,
    }.contains(service.ended);
    final finished = finishedOrder([
      for (final service in [?current, ...state.others])
        if (done(service))
          (
            name: plainTitle(context, service),
            exhausted: service.ended == ShikooServiceStatus.exhausted,
            ended: service.expire,
            renewId: account.serviceOf(service.id),
            profileId: service.id,
            linked: null,
          ),
      for (final linked in unlinked)
        if (linked.renews)
          (
            name: linked.title,
            exhausted: linked.status == 'exhausted',
            ended: null,
            renewId: linked.id,
            profileId: null,
            linked: linked,
          ),
    ], now);
    final usable = [
      if (current != null && current.ended == null) current,
      ...state.others.where((other) => other.ended == null),
    ];
    final running = {
      ShikooConnection.on,
      ShikooConnection.connecting,
    }.contains(state.connection);
    // With nothing to connect, the latest finished service is the full card (5c4d88b).
    final linkedTop = usable.isEmpty && !running
        ? finished.firstOrNull?.linked
        : null;
    final hasService = current != null && linkedTop == null;
    final noLink = [
      for (final linked in unlinked)
        if (!linked.renews) linked,
    ];
    final first = linkedTop ?? (hasService ? null : noLink.firstOrNull);
    _focusFirst(state, linkless: first != null);
    final power = _PowerZone(
      state: state,
      controller: controller,
      focusNode: _power,
      restingLabel: switch (first?.status) {
        null => null,
        'expired' => l.powerExpired,
        'exhausted' => l.stateExhausted,
        _ => l.noLinkChip,
      },
      restingMessage: (first?.renews ?? false) ? l.renewToConnect : null,
    );
    FoldedServiceCard folded(ShikooService other) => FoldedServiceCard(
      key: ValueKey(other.id),
      service: other,
      refresh: other.refresh,
      isTV: state.isTV,
      onOpen: () => _use(controller, other.id),
      onRefresh: () => unawaited(controller.refreshOther(other.id)),
    );
    _LinklessCard linkless(LinkedService linked) => _LinklessCard(
      service: linked,
      bot: account.bot,
      isTV: state.isTV,
      focusNode: linked == first ? _linkless : null,
    );
    final rows = [
      for (final row in finished)
        if (row.linked == null
            ? row.profileId != current?.id || !hasService
            : row.linked != linkedTop)
          row,
    ];
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s3,
      children: [
        if (linkedTop != null) linkless(linkedTop),
        if (hasService || (unlinked.isEmpty && current == null))
          ServiceCard(
            key: ValueKey(current?.id),
            state: state,
            controller: controller,
            focus: _card,
            serviceId: account.serviceOf(current?.id),
            bot: account.bot,
          ),
        for (final other in state.others)
          if (other.ended == null) folded(other),
        for (final linked in noLink) linkless(linked),
        for (final other in [if (!hasService) ?current, ...state.others])
          if (other.ended == ShikooServiceStatus.revoked) folded(other),
        if (rows.isNotEmpty)
          _FinishedServices(rows: rows, bot: account.bot, isTV: state.isTV),
      ],
    );
    final towardCard = state.selected ?? state.servers.firstOrNull?.name;
    return Scaffold(
      backgroundColor: t.c.bg,
      body: PageFocusScope(
        child: FocusTraversalGroup(
          policy: PageTraversalPolicy(),
          child: state.isTV
              ? _TvLayout(
                  noService: current == null && unlinked.isEmpty,
                  settings: _settings,
                  power: _PowerKeys(
                    row: towardCard == null ? null : _card.row(towardCard),
                    child: power,
                  ),
                  card: _CardKeys(focus: _card, power: _power, child: card),
                )
              : _PhoneLayout(power: power, card: card, scroll: _scroll),
        ),
      ),
    );
  }
}

/// A node keeps the context of its widget after the widget is gone.
bool _onScreen(FocusNode? node) => node?.context?.mounted ?? false;

/// Toward the card is the selected server, or the first one while none is chosen.
class _PowerKeys extends StatelessWidget {
  const _PowerKeys({required this.row, required this.child});

  final FocusNode? row;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final towardCard = Directionality.of(context) == TextDirection.rtl
        ? TraversalDirection.right
        : TraversalDirection.left;
    return Actions(
      actions: {
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            final row = this.row;
            if (intent.direction == towardCard && _onScreen(row)) {
              row!.requestFocus();
            } else if (intent.direction != TraversalDirection.down) {
              primaryFocus?.focusInDirection(intent.direction);
            }
            return null;
          },
        ),
      },
      child: child,
    );
  }
}

/// Toward the power button every card item goes there, except renew, which steps to support
/// first; down from renew is ping-all, not the first full-width row (tv-ping.html notes).
class _CardKeys extends StatelessWidget {
  const _CardKeys({
    required this.focus,
    required this.power,
    required this.child,
  });

  final CardFocus focus;
  final FocusNode power;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final towardPower = Directionality.of(context) == TextDirection.rtl
        ? TraversalDirection.left
        : TraversalDirection.right;
    return Actions(
      actions: {
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            final from = primaryFocus;
            if (from == focus.renew &&
                intent.direction == TraversalDirection.down &&
                _onScreen(focus.pingAll)) {
              focus.pingAll.requestFocus();
              return null;
            }
            if (intent.direction == towardPower &&
                from != focus.renew &&
                _onScreen(power)) {
              power.requestFocus();
            } else {
              from?.focusInDirection(intent.direction);
            }
            return null;
          },
        ),
      },
      child: child,
    );
  }
}

/// `.tv`, `.tv-top` and `.tv-home`: the card column at the start, the power button beside it.
class _TvLayout extends StatelessWidget {
  const _TvLayout({
    required this.noService,
    required this.settings,
    required this.power,
    required this.card,
  });

  final bool noService;
  final FocusNode settings;
  final Widget power;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: s.safeX, vertical: s.safeY),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: s.appbar,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Brand(),
                ShikooButton(
                  label: ShikooL10n.of(context).settings,
                  icon: ShikooIcon.gear,
                  autofocus: noService,
                  focusNode: settings,
                  onPressed: () => openSettings(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s3),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: s.pane,
                  child: _TvColumn(child: card),
                ),
                const SizedBox(width: Space.s10),
                Expanded(child: Center(child: power)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `.tv-col`: scrolls as one; once scrolled, its top edge fades and a thumb shows. It reaches
/// 8dp past the pane on every side (`margin: -8; padding: 8`) so focus rings are not clipped.
class _TvColumn extends StatefulWidget {
  const _TvColumn({required this.child});

  final Widget child;

  @override
  State<_TvColumn> createState() => _TvColumnState();
}

class _TvColumnState extends State<_TvColumn> {
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final scrolled = _scroll.offset > 0;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onFocusInside(bool inside) {
    if (inside || !_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return LayoutBuilder(
      builder: (context, box) => OverflowBox(
        maxWidth: box.maxWidth + 2 * Space.s2,
        minHeight: box.maxHeight + 2 * Space.s2,
        maxHeight: box.maxHeight + 2 * Space.s2,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _scrolled ? Colors.transparent : Colors.black,
              Colors.black,
            ],
            stops: [0, ShikooSizes.fade / rect.height],
          ).createShader(rect),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: _onFocusInside,
            child: RawScrollbar(
              controller: _scroll,
              thumbVisibility: _scrolled,
              thickness: ShikooSizes.scrollThumb,
              radius: const Radius.circular(ShikooSizes.scrollThumb),
              thumbColor: t.c.outline,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(Space.s2),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.appbar` and `.home`, which scroll as one (`.scroll-view` in phone-ping.html).
class _PhoneLayout extends StatelessWidget {
  const _PhoneLayout({
    required this.power,
    required this.card,
    required this.scroll,
  });

  final Widget power;
  final Widget card;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final s = ShikooTheme.of(context).s;
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        controller: scroll,
        padding: EdgeInsets.only(
          bottom: Space.s6 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          children: [
            Container(
              height: s.appbar,
              padding: EdgeInsetsDirectional.only(
                start: s.safeX,
                end: Space.s1,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Brand(),
                  ShikooIconButton(
                    icon: ShikooIcon.gear,
                    label: ShikooL10n.of(context).settings,
                    onPressed: () => openSettings(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: s.safeX),
              child: Column(
                children: [
                  const SizedBox(height: Space.s2),
                  power,
                  const SizedBox(height: Space.s2 + Space.s3),
                  card,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.tv-power` / `.power-zone`: the button, a pill that is always there so it never moves, a hint.
class _PowerZone extends StatelessWidget {
  const _PowerZone({
    required this.state,
    required this.controller,
    required this.focusNode,
    this.restingLabel,
    this.restingMessage,
  });

  final ShikooState state;
  final ShikooController controller;
  final FocusNode focusNode;
  final String? restingLabel;
  final String? restingMessage;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final selected = state.selectedServer;
    final gap = state.isTV ? Space.s4 : Space.s3;
    final restingMessage = this.restingMessage;
    if (state.service == null) {
      return Padding(
        padding: EdgeInsets.only(bottom: state.isTV ? gap : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: gap,
          children: [
            PowerButton(
              connection: ShikooConnection.off,
              connectedFor: Duration.zero,
              isTV: state.isTV,
              onPressed: null,
              restingLabel: restingLabel,
            ),
            if (restingMessage != null)
              Text(
                restingMessage,
                textAlign: TextAlign.center,
                style: t.text(t.s.bodySm, color: t.c.textMuted),
              ),
          ],
        ),
      );
    }
    final resting = restingFor(state);
    final silent =
        state.connection == ShikooConnection.on && (selected?.ping ?? 0) < 0;
    final message = switch (state.lastError) {
      _ when resting == ShikooServiceStatus.revoked => null,
      _ when resting != null => l.renewToConnect,
      ShikooError.connectTimeout =>
        (state.isTV ? l.errorConnect : l.errorConnectTouch)(
          selected?.label ?? '',
          connectTimeout.inSeconds,
        ),
      ShikooError.noServer =>
        state.isTV ? l.noServerAnsweredHelpTv : l.noServerAnsweredHelpTouch,
      ShikooError.vpnRefused => l.vpnRefused,
      ShikooError.vpnMissing => l.vpnMissing,
      ShikooError.serverChange => l.errorServer,
      null when state.waiting => l.connectsToFirst,
      null when silent => l.selectedDown(selected!.label),
      null =>
        state.isTV && state.connection == ShikooConnection.off
            ? l.tvHint
            : null,
    };
    final slot = state.isTV ? _twoLines(context, t) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Balances the message slot below, so the TV centres the button and pill alone.
        if (slot != null) SizedBox(height: gap + slot),
        PowerButton(
          connection: state.connection,
          connectedFor: state.connectedFor,
          isTV: state.isTV,
          focusNode: focusNode,
          restingLabel: switch (resting) {
            ShikooServiceStatus.exhausted => l.stateExhausted,
            ShikooServiceStatus.revoked => l.chipRevoked,
            _ => l.powerExpired,
          },
          onPressed: resting != null
              ? null
              : () => unawaited(switch (state.connection) {
                  ShikooConnection.off ||
                  ShikooConnection.error => controller.connect(),
                  ShikooConnection.connecting ||
                  ShikooConnection.on => controller.disconnect(),
                }),
        ),
        if (resting == null) ...[
          SizedBox(height: gap),
          NowPill(pick: state.pick, server: selected),
        ],
        if (message != null || slot != null) ...[
          SizedBox(height: gap),
          SizedBox(
            width: t.s.powerRing * 1.5,
            height: slot,
            child: Text(
              message ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: t.text(
                t.s.bodySm,
                color: resting != null || (state.lastError == null && !silent)
                    ? t.c.textMuted
                    : t.c.danger,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static double _twoLines(BuildContext context, ShikooTheme t) =>
      2 * MediaQuery.textScalerOf(context).scale(t.s.bodySm) * Leading.tight;
}

/// `tv-home-no-link` and `phone-cards-other`: a service of the account with no link here, for
/// the bot to make or for «تمدید» to bring back.
class _LinklessCard extends ConsumerStatefulWidget {
  const _LinklessCard({
    required this.service,
    required this.bot,
    required this.isTV,
    this.focusNode,
  });

  final LinkedService service;
  final String? bot;
  final bool isTV;
  final FocusNode? focusNode;

  @override
  ConsumerState<_LinklessCard> createState() => _LinklessCardState();
}

class _LinklessCardState extends ConsumerState<_LinklessCard> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await ref.read(shikooSignInProvider).sync();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final _LinklessCard(:service, :bot, :isTV) = widget;
    final renews = service.renews;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: ShapeDecoration(
        color: t.c.surface,
        shadows: t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Space.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ServiceName(service.title),
              if (renews)
                StatusChip(
                  status: service.status == 'expired'
                      ? ShikooServiceStatus.expired
                      : ShikooServiceStatus.exhausted,
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s3,
                    vertical: Space.s1,
                  ),
                  decoration: ShapeDecoration(
                    color: t.c.surfaceSunken,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    l.noLinkChip,
                    style: t.text(
                      t.s.caption,
                      weight: FontWeight.w700,
                      color: t.c.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.s2),
          Text(
            switch ((service.status, isTV)) {
              ('expired', false) => l.summaryExpiredNoDate,
              ('expired', true) => l.summaryExpiredNoDateTv,
              ('exhausted', false) => l.summaryExhausted,
              ('exhausted', true) => l.summaryExhaustedTv,
              (_, false) => l.noLinkHelpTouch,
              (_, true) => l.noLinkHelpTv,
            },
            style: t.text(
              t.s.bodySm,
              color: t.c.textMuted,
              height: Leading.body,
            ),
          ),
          const SizedBox(height: Space.s3),
          Row(
            spacing: Space.s2,
            children: [
              Expanded(
                child: ShikooButton(
                  label: renews
                      ? l.renew
                      : (isTV ? l.openBotTv : l.openBotTouch),
                  icon: isTV
                      ? ShikooIcon.qr
                      : (renews ? null : ShikooIcon.plane),
                  primary: true,
                  focusNode: widget.focusNode,
                  onPressed: () => renews
                      ? openLink(
                          context,
                          isTV: isTV,
                          link: ShikooLinks.renewOne(service.id, bot),
                          title: l.renewTitle,
                          help: l.renewHelpDirect,
                        )
                      : openLink(
                          context,
                          isTV: isTV,
                          link: ShikooLinks.openBot(bot),
                          title: l.openBotTitleTv,
                          help: l.openBotHelpTv,
                        ),
                ),
              ),
              if (renews)
                Expanded(
                  child: ShikooButton(
                    label: l.support,
                    icon: isTV ? ShikooIcon.qr : null,
                    onPressed: () => openLink(
                      context,
                      isTV: isTV,
                      link: ShikooLinks.support,
                      title: l.supportTitle,
                      help: l.supportHelpTv,
                      below: bidiName(service.title),
                    ),
                  ),
                ),
              // The phone asks again by itself when it comes back from Telegram.
              if (isTV)
                Expanded(
                  child: ShikooButton(
                    label: l.retry,
                    icon: ShikooIcon.refresh,
                    busy: _busy,
                    onPressed: _busy ? () {} : () => unawaited(_retry()),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `.card.finished` (phone-small-home-finished, tv-home-finished): every used-up or expired
/// service in one row, folded on every start. Open, each has a line of its own with renew; on
/// the TV the line is the remote's stop and Back folds the row again.
class _FinishedServices extends StatefulWidget {
  const _FinishedServices({
    required this.rows,
    required this.bot,
    required this.isTV,
  });

  final List<Finished> rows;
  final String? bot;
  final bool isTV;

  @override
  State<_FinishedServices> createState() => _FinishedServicesState();
}

class _FinishedServicesState extends State<_FinishedServices> {
  final _head = FocusNode();
  final _first = FocusNode();
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _head.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _head.dispose();
    _first.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && widget.isTV) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _first.requestFocus(),
      );
    }
  }

  void _renew(Finished row) {
    final l = ShikooL10n.of(context);
    final id = row.renewId;
    final user = usernameOf(row.name);
    openLink(
      context,
      isTV: widget.isTV,
      link: id == null
          ? ShikooLinks.renew
          : ShikooLinks.renewOne(id, widget.bot),
      title: l.renewTitle,
      help: id == null ? l.renewHelpList : l.renewHelpDirect,
      below: id == null ? l.renewPickInList(bidiName(user)) : null,
      strong: id == null ? user : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final isTV = widget.isTV;
    final now = DateTime.now();
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.md),
    );
    final focused =
        isTV &&
        _head.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    Widget line(Finished row, bool focused) => Container(
      padding: EdgeInsets.symmetric(
        vertical: Space.s3,
        horizontal: isTV ? Space.s2 : 0,
      ),
      decoration: ShapeDecoration(
        color: focused ? t.c.focusBg : null,
        shape: shape,
      ),
      child: Row(
        spacing: Space.s3,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ServiceName(
                  row.name,
                  style: t.text(
                    t.s.body,
                    weight: FontWeight.w700,
                    height: Leading.snug,
                  ),
                ),
                Text(
                  finishedStatus(l, row, now),
                  style: t.text(t.s.bodySm, color: t.c.textMuted),
                ),
              ],
            ),
          ),
          if (isTV)
            ExcludeFocus(
              child: IgnorePointer(
                child: ShikooButton(
                  label: l.renew,
                  icon: ShikooIcon.qr,
                  small: true,
                  onPressed: () {},
                ),
              ),
            )
          else
            ShikooButton(
              label: l.renew,
              small: true,
              onPressed: () => _renew(row),
            ),
        ],
      ),
    );
    final card = Container(
      padding: EdgeInsets.symmetric(horizontal: isTV ? Space.s2 : Space.s4),
      decoration: ShapeDecoration(
        color: focused ? t.c.focusBg : t.c.surface,
        shadows: focused ? t.c.raisedShadow : t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            focusNode: _head,
            shape: shape,
            onPressed: _toggle,
            builder: (context, _) => Semantics(
              button: true,
              expanded: _open,
              child: Container(
                constraints: const BoxConstraints(minHeight: ShikooSizes.touch),
                padding: EdgeInsets.symmetric(
                  horizontal: isTV ? Space.s2 : 0,
                  vertical: Space.s2,
                ),
                child: Row(
                  spacing: Space.s2,
                  children: [
                    Expanded(
                      child: Text(
                        l.finishedServices(widget.rows.length),
                        style: t.text(
                          t.s.body,
                          weight: FontWeight.w700,
                          color: t.c.textMuted,
                        ),
                      ),
                    ),
                    SvgIcon(
                      _open ? ShikooIcon.chevronUp : ShikooIcon.chevronDown,
                      size: t.s.icon,
                      color: t.c.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            for (final (i, row) in widget.rows.indexed) ...[
              Container(height: 1, color: t.c.border),
              if (isTV)
                Pressable(
                  focusNode: i == 0 ? _first : null,
                  shape: shape,
                  onPressed: () => _renew(row),
                  builder: (context, focused) => line(row, focused),
                )
              else
                line(row, false),
            ],
        ],
      ),
    );
    if (!isTV) return card;
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_open) return;
        setState(() => _open = false);
        _head.requestFocus();
      },
      child: card,
    );
  }
}
