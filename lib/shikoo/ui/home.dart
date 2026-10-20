import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/focus.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/internet_check.dart';
import 'package:fl_clash/shikoo/ui/mode.dart';
import 'package:fl_clash/shikoo/ui/paste.dart';
import 'package:fl_clash/shikoo/ui/report.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/update.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

String finishedStatus(ShikooL10n l, Finished row, DateTime now) {
  final ended = row.ended;
  if (row.linked?.disabled ?? false) return l.finishedDisabled;
  if (row.exhausted) return l.finishedData;
  if (ended == null) return l.finishedNoDate;
  final days = DateUtils.dateOnly(
    now,
  ).difference(DateUtils.dateOnly(ended)).inDays;
  return days < 1 ? l.finishedToday : l.finishedDaysAgo(days);
}

/// A switch's sentences; a failure's first one is bold on the phone.
List<String> switchNews(ShikooL10n l, ShikooSwitch shift) =>
    switch (shift.stage) {
      ShikooSwitchStage.moving => [l.switchingTo(serverName(shift.to))],
      ShikooSwitchStage.done => [l.switchedTo(serverName(shift.to))],
      ShikooSwitchStage.failed => [
        l.selectedNoAnswer(serverName(shift.to)),
        l.switchKept(serverName(shift.from)),
      ],
    };

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
  final _crashSend = FocusNode();
  final _crashNo = FocusNode();
  final _check = FocusNode();
  final _inUse = FocusNode();
  final _scroll = ScrollController();
  final _cards = <int, GlobalKey>{};
  (int?, bool, bool, bool)? _shown;

  /// The only card, folded by its arrow; two cards or more fold and open as the controller says.
  bool _folded = false;

  ({int id, double? top})? _opening;
  final _news = ValueNotifier<ShikooSwitch?>(null);
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _bar;

  /// From the bar's top to the screen's bottom, so the list can end above it.
  double _room = 0;

  late final AppLifecycleListener _resume;

  @override
  void initState() {
    super.initState();
    _resume = AppLifecycleListener(onResume: _refocus);
  }

  /// Back from another app the box can hold no focus at all, and the next key then lands in
  /// the list: the remote starts again where it does on opening.
  void _refocus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final focused = FocusManager.instance.primaryFocus;
    if (!mounted || !ref.read(shikooStateProvider).isTV) return;
    if (focused is! FocusScopeNode && _onScreen(focused)) return;
    setState(() => _shown = null);
  });

  @override
  void dispose() {
    _resume.dispose();
    _card.dispose();
    _power.dispose();
    _settings.dispose();
    _linkless.dispose();
    _crashSend.dispose();
    _crashNo.dispose();
    _check.dispose();
    _inUse.dispose();
    _scroll.dispose();
    _news.dispose();
    super.dispose();
  }

  /// phone-switch-*: one bar from the tap to the end, its words following the switch.
  void _onSwitch(ShikooSwitch? next) {
    if (next == null) return _bar?.close();
    _news.value = next;
    if (_bar != null || ref.read(shikooStateProvider).isTV) return;
    final t = ShikooTheme.of(context);
    final bar = _bar = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _SwitchBar(news: _news, onTop: _barAt),
        persist: true,
        behavior: SnackBarBehavior.floating,
        padding: EdgeInsets.zero,
        margin: EdgeInsets.fromLTRB(t.s.safeX, 0, t.s.safeX, Space.s4),
        backgroundColor: t.c.text,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
    );
    unawaited(
      bar.closed.then((_) {
        if (_bar == bar) _bar = null;
        if (mounted) setState(() => _room = 0);
      }),
    );
  }

  void _barAt(double top) {
    final room = MediaQuery.sizeOf(context).height - top;
    if (_bar != null && (room - _room).abs() > 0.5) {
      setState(() => _room = room);
    }
  }

  /// phone-p4-added and phone-p4-duplicate: the bar says what the paste brought; home goes to it.
  Future<void> _add() async {
    final pasted = await Navigator.push<ShikooPasted>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddService(),
        settings: const RouteSettings(name: 'add'),
      ),
    );
    if (pasted == null || !mounted) return;
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final state = ref.read(shikooStateProvider);
    final service = [
      ?state.service,
      ...state.others,
    ].firstWhereOrNull((s) => s.id == pasted.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(t.s.safeX, 0, t.s.safeX, Space.s4),
        backgroundColor: t.c.text,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        content: Row(
          spacing: Space.s3,
          children: [
            SvgIcon(ShikooIcon.check, size: t.s.icon, color: t.c.bg),
            Expanded(
              child: Text(
                pasted.added && service != null
                    ? l.serviceAdded(serviceTitle(context, service))
                    : (shikooDesktop
                          ? l.serviceAlreadyHereDesktop
                          : l.serviceAlreadyHere),
                style: t.text(t.s.body, color: t.c.bg, height: Leading.body),
              ),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = _cards[pasted.id]?.currentContext;
      if (card != null && card.mounted) {
        unawaited(Scrollable.ensureVisible(card));
      }
    });
  }

  double? _edge(int? id, {bool bottom = false}) {
    final box = _cards[id]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset(0, bottom ? box.size.height : 0)).dy;
  }

  /// phone-p2-open-other: the page never scrolls by itself; [id]'s card edge goes back to [from].
  void _keepAt(int? id, double? from, {bool bottom = false}) {
    if (from == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final to = _edge(id, bottom: bottom);
      if (to == null || !_scroll.hasClients) return;
      final position = _scroll.position;
      position.jumpTo(
        clampDouble(
          position.pixels + to - from,
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  void _open(ShikooController controller, int id) {
    _opening = (id: id, top: _edge(id));
    setState(() => _folded = false);
    controller.openService(id);
  }

  /// tv-p2-open-other: the remote lands on the opened card's «پینگ»; the phone keeps its head still.
  void _onOpened(ShikooState state) {
    final opening = _opening;
    if (opening == null || state.open != opening.id) return;
    _opening = null;
    if (!state.isTV) return _keepAt(opening.id, opening.top);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final first = [
        _card.ping,
        _card.renew,
        _card.support,
      ].firstWhereOrNull((node) => _onScreen(node) && node.canRequestFocus);
      if (first != null) jumpFocus(first.context!, first);
    });
  }

  /// So the remote never stays on a button that just went away or went dead.
  void _focusFirst(
    ShikooState state, {
    required bool linkless,
    required bool renews,
  }) {
    final service = state.service;
    final shown = (service?.id, restingFor(state) != null, linkless, renews);
    if (!state.isTV || shown == _shown) return;
    final focused = FocusManager.instance.primaryFocus;
    // The open card became the one in use, by a server pressed there: the remote stays on it.
    final stays =
        _shown != null &&
        service?.id == state.open &&
        !shown.$2 &&
        focused is! FocusScopeNode &&
        _onScreen(focused);
    _shown = shown;
    if (stays) return;
    final resting = renews ? _card.renew : _card.support;
    final first = linkless
        ? _linkless
        : (service == null ? _settings : (shown.$2 ? resting : _power));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (ModalRoute.isCurrentOf(context) ?? true)) {
        first.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      shikooStateProvider.select((state) => state.switching),
      (_, next) => _onSwitch(next),
    );
    ref.listen(shikooStateProvider.select((state) => state.service?.id), (
      before,
      now,
    ) {
      final state = ref.read(shikooStateProvider);
      if (before != null && state.connection == ShikooConnection.on) {
        _keepAt(state.open, _edge(state.open, bottom: true), bottom: true);
      }
    });
    final state = ref.watch(shikooStateProvider);
    final controller = ref.watch(shikooControllerProvider);
    final account = ref.watch(shikooAccountProvider);
    final update = ref.watch(shikooUpdateOfferProvider);
    final crashed = ref.watch(shikooCrashProvider) != null;
    final check = ref.watch(shikooProbeProvider);
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final now = shikooNow();
    final current = state.service;
    final unlinked = account.withoutLink;
    final finished = finishedOrder([
      for (final service in [?current, ...state.others])
        if (service.finished)
          finishedOf(
            service,
            name: plainTitle(context, service),
            renewId: account.serviceOf(service.id),
          ),
      for (final linked in unlinked)
        if (linked.finished)
          (
            name: linked.title,
            exhausted: linked.status == 'exhausted',
            ended: linked.expiresAt,
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
        if (!linked.finished) linked,
    ];
    final first = linkedTop ?? (hasService ? null : noLink.firstOrNull);
    final renews = account.renewsOn(current?.id);
    _focusFirst(state, linkless: first != null, renews: renews);
    _onOpened(state);
    final wide =
        !state.isTV &&
        shikooDesktop &&
        MediaQuery.sizeOf(context).width >= ShikooSizes.twoColumns;
    final power = _PowerZone(
      state: state,
      centred: state.isTV || wide,
      controller: controller,
      focusNode: _power,
      renews: renews,
      restingLabel: switch (first) {
        null => null,
        LinkedService(status: 'exhausted') => l.stateExhausted,
        LinkedService(disabled: true) => l.finishedDisabled,
        LinkedService(finished: true) => l.powerExpired,
        LinkedService(loadFailed: true) => l.loadFailedChip,
        _ => l.noLinkChip,
      },
      restingMessage: (first?.renews ?? false) ? l.renewToConnect : null,
      checked: check != null,
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
    final listed = state.listed;
    final cards = [
      for (final service in listed)
        if (service.ended == null || (service.id == current?.id && hasService))
          service,
    ];
    final revoked = [
      for (final service in listed)
        if (service.ended == ShikooServiceStatus.revoked &&
            !cards.contains(service))
          service,
    ];
    final accordion = cards.length + revoked.length > 1;
    final inUseOpen = !accordion || state.open == current?.id;
    Widget serviceCard(ShikooService service) {
      final inUse = service.id == current?.id;
      final mark = accordion && inUse
          ? state.connection == ShikooConnection.on
          : null;
      final open = accordion ? state.open == service.id : !_folded;
      return KeyedSubtree(
        key: _cards.putIfAbsent(service.id, GlobalKey.new),
        child: open
            ? ServiceCard(
                state: inUse && state.opened?.id != service.id
                    ? state
                    : _openedState(state, service),
                controller: controller,
                focus: _card,
                serviceId: account.serviceOf(service.id),
                bot: account.bot,
                renews: account.renewsOn(service.id),
                other: !inUse,
                inUse: mark,
                onFold: state.isTV
                    ? null
                    : () => accordion
                          ? controller.openService(null)
                          : setState(() => _folded = true),
              )
            : FoldedServiceCard(
                service: service,
                isTV: state.isTV,
                renews: account.renewsOn(service.id),
                inUse: mark,
                focusNode: inUse ? _inUse : null,
                onOpen: () => _open(controller, service.id),
              ),
      );
    }

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s3,
      children: [
        if (crashed) CrashCard(send: _crashSend, no: _crashNo),
        if (check != null)
          InternetCheckCard(
            check: check,
            state: state,
            controller: controller,
            onReport: () => unawaited(openReport(context, 'connect')),
            firstFocus: _check,
          ),
        if (update != null) UpdateCard(offer: update, isTV: state.isTV),
        if (linkedTop != null) linkless(linkedTop),
        if (unlinked.isEmpty && current == null)
          ServiceCard(state: state, controller: controller, focus: _card),
        for (final service in cards) serviceCard(service),
        for (final linked in noLink) linkless(linked),
        for (final service in revoked) serviceCard(service),
        if (rows.isNotEmpty)
          _FinishedServices(rows: rows, account: account, isTV: state.isTV),
      ],
    );
    final towardCard = state.selected ?? state.servers.firstOrNull?.name;
    // A home with no service has its own paste button in its card.
    final onAdd = current == null && unlinked.isEmpty
        ? null
        : () => unawaited(_add());
    return PageWidth(
      child: Scaffold(
        backgroundColor: t.c.bg,
        body: PageFocusScope(
          child: FocusTraversalGroup(
            policy: PageTraversalPolicy(),
            child: state.isTV
                ? _TvLayout(
                    noService: current == null && unlinked.isEmpty,
                    settings: _settings,
                    power: _PowerKeys(
                      targets: [
                        _crashSend,
                        _check,
                        if (inUseOpen && towardCard != null)
                          _card.row(towardCard),
                        _inUse,
                      ],
                      child: power,
                    ),
                    card: _CardKeys(focus: _card, power: _power, child: card),
                  )
                : wide
                ? _WideLayout(
                    power: power,
                    card: card,
                    scroll: _scroll,
                    room: _room,
                    onAdd: onAdd,
                  )
                : _PhoneLayout(
                    power: power,
                    card: card,
                    scroll: _scroll,
                    room: _room,
                    onAdd: onAdd,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Another service's card: its own numbers from [ShikooState.opened], none until they come.
ShikooState _openedState(ShikooState state, ShikooService service) {
  final opened = state.opened?.id == service.id ? state.opened : null;
  return ShikooState(
    connection: state.connection,
    connectedFor: state.connectedFor,
    isTV: state.isTV,
    service: service,
    servers: opened?.servers ?? const [],
    pinging: opened?.pinging,
    sorted: opened?.sorted ?? false,
    refresh: service.id == state.service?.id ? state.refresh : service.refresh,
    open: state.open,
    landed: state.landed,
  );
}

/// A node keeps the context of its widget after the widget is gone.
bool _onScreen(FocusNode? node) => node?.context?.mounted ?? false;

/// Only the cards' own: a list scrolled up under the top bar shares a row with its Settings.
FocusNode? _beside(BuildContext cards, FocusNode from, {required bool rtl}) {
  final box = cards.findRenderObject();
  if (box is! RenderBox) return null;
  final column = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  final at = from.rect;
  FocusNode? nearest;
  var gap = double.infinity;
  for (final node in from.nearestScope?.traversalDescendants ?? <FocusNode>[]) {
    final r = node.rect;
    final apart = rtl ? at.left - r.right : r.left - at.right;
    if (apart >= 0 &&
        apart < gap &&
        r.top < at.bottom &&
        r.bottom > at.top &&
        column.contains(r.center)) {
      nearest = node;
      gap = apart;
    }
  }
  return nearest;
}

/// Toward the card: the crash card, the internet check, then the selected or first server.
class _PowerKeys extends StatelessWidget {
  const _PowerKeys({required this.targets, required this.child});

  final List<FocusNode> targets;
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
            final target = targets.firstWhereOrNull(_onScreen);
            if (intent.direction == towardCard && target != null) {
              target.requestFocus();
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

/// Toward the power button a card item goes there, or to the item beside it in its row
/// first; up and down around the card's head as tv-ping.html's notes say.
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
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final towardPower = rtl
        ? TraversalDirection.left
        : TraversalDirection.right;
    final away = rtl ? TraversalDirection.right : TraversalDirection.left;
    return Actions(
      actions: {
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            final from = primaryFocus;
            final head = from == focus.refresh || from == focus.ping;
            final next = switch (intent.direction) {
              TraversalDirection.down when head =>
                _onScreen(focus.report) ? focus.report : focus.support,
              TraversalDirection.up
                  when from == focus.renew || from == focus.support =>
                _onScreen(focus.report) ? focus.report : focus.ping,
              _ => null,
            };
            if (_onScreen(next)) {
              next!.requestFocus();
              return null;
            }
            // The head ends at «به‌روزرسانی»; geometry would drop to renew below it.
            if (from == focus.refresh && intent.direction == away) return null;
            if (intent.direction == towardPower &&
                from != null &&
                _onScreen(power)) {
              (_beside(context, from, rtl: rtl) ?? power).requestFocus();
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
          Container(
            height: s.appbar + 2 * ShikooSizes.ring,
            padding: const EdgeInsets.symmetric(horizontal: ShikooSizes.ring),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ShikooSizes.ring),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: s.pane,
                    child: TvScrollColumn(child: card),
                  ),
                  const SizedBox(width: Space.s10),
                  Expanded(child: Center(child: power)),
                ],
              ),
            ),
          ),
        ],
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
    required this.room,
    this.onAdd,
  });

  final Widget power;
  final Widget card;
  final ScrollController scroll;

  /// The switch bar's, which the last rows can rise above.
  final double room;

  /// The «+» beside Settings (phone-p4a-home); none without it.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final s = ShikooTheme.of(context).s;
    final padding = EdgeInsets.only(
      bottom: math.max(
        Space.s6 + MediaQuery.paddingOf(context).bottom,
        room + Space.s3,
      ),
    );
    final page = Column(
      children: [
        _AppBar(onAdd: onAdd),
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
    );
    return SafeArea(
      bottom: false,
      child: shikooDesktop
          ? EdgeScroll(controller: scroll, padding: padding, child: page)
          : SingleChildScrollView(
              controller: scroll,
              padding: padding,
              child: page,
            ),
    );
  }
}

class _AppBar extends StatelessWidget {
  const _AppBar({this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final s = ShikooTheme.of(context).s;
    return Container(
      height: s.appbar,
      padding: EdgeInsetsDirectional.only(start: s.safeX, end: Space.s1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Brand(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onAdd case final onAdd?)
                ShikooIconButton(
                  icon: ShikooIcon.plus,
                  label: ShikooL10n.of(context).addServiceTooltip,
                  onPressed: onAdd,
                ),
              ShikooIconButton(
                icon: ShikooIcon.gear,
                label: ShikooL10n.of(context).settings,
                onPressed: () => openSettings(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `.win-home` (win-modes.html, frame `win-w-b`): the TV's two columns at the phone's sizes.
class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.power,
    required this.card,
    required this.scroll,
    required this.room,
    this.onAdd,
  });

  final Widget power;
  final Widget card;
  final ScrollController scroll;
  final double room;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final s = ShikooTheme.of(context).s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppBar(onAdd: onAdd),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: s.safeX),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.s8,
              children: [
                // Each column a group of its own: a card scrolled up under the top bar would
                // otherwise come before the bar's buttons, and Tab would never reach them.
                FocusTraversalGroup(
                  child: SizedBox(
                    width: s.pane,
                    child: SingleChildScrollView(
                      controller: scroll,
                      padding: EdgeInsets.only(
                        bottom: math.max(Space.s4, room + Space.s3),
                      ),
                      child: card,
                    ),
                  ),
                ),
                Expanded(
                  child: FocusTraversalGroup(
                    // Space.s4 under it always, so a message that comes changes nothing.
                    child: LayoutBuilder(
                      builder: (context, box) => EdgeScroll(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ShikooSizes.scrollbar,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: box.maxHeight - Space.s4,
                              ),
                              child: power,
                            ),
                            const SizedBox(height: Space.s4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `.tv-power` / `.power-zone`: the button, a pill that is always there so it never moves, a hint.
class _PowerZone extends StatelessWidget {
  const _PowerZone({
    required this.state,
    required this.centred,
    required this.controller,
    required this.focusNode,
    required this.renews,
    this.restingLabel,
    this.restingMessage,
    this.checked = false,
  });

  final ShikooState state;

  /// Alone in its column, as on the TV and in the wide window: two lines are kept for the message.
  final bool centred;
  final ShikooController controller;
  final FocusNode focusNode;
  final bool renews;
  final String? restingLabel;
  final String? restingMessage;

  /// The internet check has its card; «check this phone's internet» would contradict it.
  final bool checked;

  bool get _silent =>
      state.connection == ShikooConnection.on &&
      (state.selectedServer?.ping ?? 0) < 0;

  // The phone's switch news is its bottom bar; the TV's is this slot, which never moves.
  ShikooSwitch? get _shift => state.isTV ? state.switching : null;

  String? message(ShikooL10n l) {
    if (state.service == null) return null;
    final resting = restingFor(state);
    final selected = state.selectedServer;
    final silent = _silent;
    final shift = _shift;
    return switch (state.lastError) {
      _ when resting == ShikooServiceStatus.revoked => null,
      _ when resting != null => renews ? l.renewToConnect : null,
      ShikooError.connectTimeout =>
        (state.isTV
            ? l.errorConnect
            : (shikooDesktop ? l.errorConnectDesktop : l.errorConnectTouch))(
          // A break may come after «·», never before it: no line opens with «· premium».
          serverName(selected?.name ?? '').replaceAll(' ·\u00a0', '\u00a0· '),
          connectTimeout.inSeconds,
        ),
      ShikooError.noServer when checked => null,
      ShikooError.noServer =>
        state.isTV
            ? l.noServerAnsweredHelpTv
            : (shikooDesktop
                  ? l.noServerAnsweredHelpDesktop
                  : l.noServerAnsweredHelpTouch),
      ShikooError.vpnRefused =>
        shikooDesktop ? l.vpnRefusedDesktop : l.vpnRefused,
      ShikooError.vpnMissing =>
        shikooDesktop ? l.vpnMissingDesktop : l.vpnMissing,
      ShikooError.serverChange => l.errorServer,
      ShikooError.coreDown => l.coreDownDesktop,
      ShikooError.coreStart => l.coreStartDesktop,
      null when state.busyPort != null => l.busyPortDesktop,
      null when state.helperFailed => l.helperFailedDesktop,
      null when state.waiting => l.connectsToFirst,
      null when shift?.stage == ShikooSwitchStage.failed => l.switchFailedTv(
        serverName(shift!.to),
      ),
      null when shift != null => switchNews(l, shift).join(' '),
      null when silent => l.selectedDown(serverName(selected!.name)),
      null =>
        state.isTV && state.connection == ShikooConnection.off
            ? l.tvHint
            : null,
    };
  }

  /// A computer keeps the tallest message's room, its narrow page too: one that comes moves nothing.
  double _room(BuildContext context, ShikooL10n l, double width) {
    final t = ShikooTheme.of(context);
    final style = t.text(t.s.bodySm);
    // ponytail: measured on each build; cache by names and text size if a long list shows up.
    final names = {
      ?state.selectedServer?.name,
      for (final server in state.servers) server.name,
    }.map(serverName);
    return [
      twoLines(context, style),
      for (final text in [
        l.vpnRefusedDesktop,
        l.vpnMissingDesktop,
        l.busyPortDesktop,
        l.helperFailedDesktop,
        l.noServerAnsweredHelpDesktop,
        l.coreDownDesktop,
        l.coreStartDesktop,
        l.errorServer,
        l.connectsToFirst,
        l.renewToConnect,
        for (final name in names) ...[
          l.selectedDown(name),
          l.errorConnectDesktop(
            name.replaceAll(' \u00b7\u00a0', '\u00a0\u00b7 '),
            connectTimeout.inSeconds,
          ),
        ],
      ])
        textHeight(context, text, style, width),
    ].reduce(math.max);
  }

  @override
  Widget build(BuildContext context) {
    final s = ShikooTheme.of(context).s;
    if (!shikooDesktop) return _column(context, s.powerRing * 1.5);
    return LayoutBuilder(
      builder: (context, box) =>
          _column(context, math.min(s.dialog, box.maxWidth)),
    );
  }

  Widget _column(BuildContext context, double width) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final selected = state.selectedServer;
    final gap = state.isTV ? Space.s4 : Space.s3;
    final restingMessage = this.restingMessage;
    final squeeze = centred && !state.isTV;
    if (state.service == null) {
      final items = [
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
      ];
      if (squeeze) return _Squeeze(gap: gap, keep: 0, children: items);
      return Padding(
        padding: EdgeInsets.only(bottom: state.isTV ? gap : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: gap,
          children: items,
        ),
      );
    }
    final resting = restingFor(state);
    final silent = _silent;
    final shift = _shift;
    final alarm = shift == null
        ? silent
        : shift.stage == ShikooSwitchStage.failed;
    final message = this.message(l);
    final slot = shikooDesktop
        ? _room(context, l, width)
        : (centred ? twoLines(context, t.text(t.s.bodySm)) : null);
    final failed =
        state.lastError != null || state.busyPort != null || state.helperFailed;
    final items = [
      PowerButton(
        connection: state.connection,
        connectedFor: state.connectedFor,
        isTV: state.isTV,
        focusNode: focusNode,
        switching: state.switching?.stage == ShikooSwitchStage.moving,
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
        NowPill(pick: state.pick, server: selected),
        if (shikooDesktop) ...[
          ModeSwitch(
            connecting: state.connection == ShikooConnection.connecting,
          ),
          const LocalProxy(),
        ],
      ],
      if (message != null || slot != null)
        _InView(
          key: ValueKey(message),
          message: message,
          // A computer's text can be set half as large again: the message grows, never cut.
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: width).copyWith(
              minHeight: slot ?? 0,
              maxHeight: shikooDesktop ? double.infinity : slot,
            ),
            child: Text(
              message ?? '',
              maxLines: shikooDesktop ? null : 2,
              overflow: shikooDesktop ? null : TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: t.text(
                t.s.bodySm,
                color: resting != null || (!failed && !alarm)
                    ? t.c.textMuted
                    : t.c.danger,
              ),
            ),
          ),
        ),
    ];
    if (squeeze) return _Squeeze(gap: gap, keep: slot!, children: items);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Balances the message slot below, so the TV centres the button and pill alone.
        if (slot != null && state.isTV) SizedBox(height: gap + slot),
        for (final (i, item) in items.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          item,
        ],
      ],
    );
  }
}

/// A computer's wide button column, centred in the least height asked: short of room, its gaps
/// give way evenly down to Space.s2. The last child is placed as if [keep] tall.
class _Squeeze extends MultiChildRenderObjectWidget {
  const _Squeeze({
    required this.gap,
    required this.keep,
    required super.children,
  });

  final double gap;
  final double keep;

  @override
  _RenderSqueeze createRenderObject(BuildContext context) =>
      _RenderSqueeze((gap: gap, keep: keep));

  @override
  void updateRenderObject(BuildContext context, _RenderSqueeze renderObject) =>
      renderObject.look = (gap: gap, keep: keep);
}

class _RenderSqueeze extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  _RenderSqueeze(this._look);

  ({double gap, double keep}) _look;

  set look(({double gap, double keep}) look) {
    if (look == _look) return;
    _look = look;
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
    final (:gap, :keep) = _look;
    final width = constraints.maxWidth;
    final children = getChildrenAsList();
    for (final child in children) {
      child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    }
    final heights = <double>[for (final child in children) child.size.height];
    final placed =
        heights.sum - heights.last + (keep > 0 ? keep : heights.last);
    final gaps = children.length - 1;
    final room = constraints.minHeight;
    final each = gaps == 0
        ? 0.0
        : clampDouble((room - placed) / gaps, Space.s2, gap);
    var y = math.max(0.0, (room - placed - gaps * each) / 2);
    for (final child in children) {
      (child.parentData! as MultiChildLayoutParentData).offset = Offset(
        (width - child.size.width) / 2,
        y,
      );
      y += child.size.height + each;
    }
    size = constraints.constrain(Size(width, y - each));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A computer's window can be too short to show the message under the mode switch: a new one
/// scrolls into view.
class _InView extends StatefulWidget {
  const _InView({super.key, required this.message, required this.child});

  final String? message;
  final Widget child;

  @override
  State<_InView> createState() => _InViewState();
}

class _InViewState extends State<_InView> {
  @override
  void initState() {
    super.initState();
    if (shikooDesktop && widget.message != null) _revealIfHidden();
  }

  /// Only a message out of view, or closer to the bottom than Space.s4, scrolls.
  void _revealIfHidden() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final box = context.mounted ? context.findRenderObject() : null;
    final port = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || port is! RenderBox) return;
    final seen = port.localToGlobal(Offset.zero) & port.size;
    final at = box.localToGlobal(Offset.zero) & box.size;
    if (seen.top <= at.top + 0.5 && at.bottom + Space.s4 <= seen.bottom + 0.5) {
      return;
    }
    box.showOnScreen(
      rect: Rect.fromLTRB(0, 0, box.size.width, box.size.height + Space.s4),
    );
  });

  @override
  Widget build(BuildContext context) => widget.child;
}

/// `.snackbar`: the bar's whole face, as its own padding is none, so [onTop] is the bar's top.
class _SwitchBar extends StatelessWidget {
  const _SwitchBar({required this.news, required this.onTop});

  final ValueNotifier<ShikooSwitch?> news;
  final ValueChanged<double> onTop;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final style = t.text(t.s.body, color: t.c.bg, height: Leading.body);
    return ValueListenableBuilder(
      valueListenable: news,
      builder: (context, shift, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final box = context.mounted ? context.findRenderObject() : null;
          if (box is RenderBox && box.attached) {
            onTop(box.localToGlobal(Offset.zero).dy);
          }
        });
        final [first, ...rest] = switchNews(l, shift!);
        final icon = switch (shift.stage) {
          ShikooSwitchStage.moving => null,
          ShikooSwitchStage.done => ShikooIcon.check,
          ShikooSwitchStage.failed => ShikooIcon.alert,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.s3,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  top:
                      (MediaQuery.textScalerOf(context).scale(t.s.body) *
                              Leading.body -
                          t.s.icon) /
                      2,
                ),
                child: switch (icon) {
                  null => Spinner(size: t.s.icon, color: t.c.bg),
                  _ => SvgIcon(icon, size: t.s.icon, color: t.c.bg),
                },
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: first,
                        style: rest.isEmpty
                            ? null
                            : const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      for (final sentence in rest) TextSpan(text: ' $sentence'),
                    ],
                  ),
                  style: style,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
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
    final finished = service.finished;
    final renews = service.renews;
    final supportOnly = finished && !renews;
    final failed = service.loadFailed && !finished;
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
              if (finished)
                StatusChip.linked(service)
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s3,
                    vertical: Space.s1,
                  ),
                  decoration: ShapeDecoration(
                    color: failed ? t.c.dangerSoft : t.c.surfaceSunken,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    failed ? l.loadFailedChip : l.noLinkChip,
                    style: t.text(
                      t.s.caption,
                      weight: FontWeight.w700,
                      color: failed ? t.c.danger : t.c.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.s2),
          Text(
            switch ((service.status, finished, isTV)) {
              _ when supportOnly && !service.disabled => l.summaryNotRenewable,
              _ when supportOnly => l.summaryRemoved,
              ('exhausted', _, false) => l.summaryExhausted,
              ('exhausted', _, true) => l.summaryExhaustedTv,
              ('disabled', _, false) => l.summaryDisabled,
              ('disabled', _, true) => l.summaryDisabledTv,
              (_, true, false) => l.summaryExpiredNoDate,
              (_, true, true) => l.summaryExpiredNoDateTv,
              _ when failed => l.loadFailedHelp,
              (_, _, false) => l.noLinkHelpTouch,
              (_, _, true) => l.noLinkHelpTv,
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
              if (failed)
                Expanded(
                  child: ShikooButton(
                    label: l.retry,
                    icon: ShikooIcon.refresh,
                    primary: true,
                    busy: _busy,
                    focusNode: widget.focusNode,
                    onPressed: _busy ? () {} : () => unawaited(_retry()),
                  ),
                )
              else if (!supportOnly)
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
              if (finished || failed)
                Expanded(
                  child: ShikooButton(
                    label: l.support,
                    icon: isTV ? ShikooIcon.qr : null,
                    primary: supportOnly,
                    focusNode: supportOnly ? widget.focusNode : null,
                    onPressed: () => unawaited(
                      openSupport(
                        context,
                        isTV: isTV,
                        below: bidiName(service.title),
                        trigger: 'support',
                      ),
                    ),
                  ),
                ),
              // The phone asks again by itself when it comes back from Telegram.
              if (isTV && !failed)
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
    required this.account,
    required this.isTV,
  });

  final List<Finished> rows;
  final ShikooAccount account;
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
    if (!_open) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(Scrollable.ensureVisible(context));
      if (widget.isTV) jumpFocus(context, _first);
    });
  }

  bool _renews(Finished row) =>
      row.linked?.renews ?? widget.account.renewsOn(row.profileId);

  void _renew(Finished row) {
    if (!_renews(row)) {
      unawaited(
        openSupport(
          context,
          isTV: widget.isTV,
          below: bidiName(row.name),
          trigger: 'support',
        ),
      );
      return;
    }
    final l = ShikooL10n.of(context);
    final id = row.renewId;
    final user = usernameOf(row.name);
    openLink(
      context,
      isTV: widget.isTV,
      link: id == null
          ? ShikooLinks.renew
          : ShikooLinks.renewOne(id, widget.account.bot),
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
    final now = shikooNow();
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
                  label: _renews(row) ? l.renew : l.support,
                  icon: ShikooIcon.qr,
                  small: true,
                  onPressed: () {},
                ),
              ),
            )
          else
            ShikooButton(
              label: _renews(row) ? l.renew : l.support,
              small: true,
              onPressed: () => _renew(row),
            ),
        ],
      ),
    );
    final card = Container(
      padding: EdgeInsets.symmetric(horizontal: isTV ? 0 : Space.s4),
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
            shape: isTV
                ? RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(Radii.lg),
                  )
                : shape,
            onPressed: _toggle,
            builder: (context, _) => Semantics(
              button: true,
              expanded: _open,
              child: Container(
                constraints: const BoxConstraints(minHeight: ShikooSizes.touch),
                padding: EdgeInsets.symmetric(
                  horizontal: isTV ? Space.s4 : 0,
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
              Container(
                height: 1,
                margin: EdgeInsets.symmetric(horizontal: isTV ? Space.s4 : 0),
                color: t.c.border,
              ),
              if (isTV)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s2),
                  child: Pressable(
                    focusNode: i == 0 ? _first : null,
                    shape: shape,
                    onPressed: () => _renew(row),
                    builder: (context, focused) => line(row, focused),
                  ),
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
        jumpFocus(context, _head);
      },
      child: card,
    );
  }
}
