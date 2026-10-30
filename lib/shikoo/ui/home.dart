import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/core_openvpn.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/ping.dart' show fastest, streamingOnly;
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/cores.dart';
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
  if (ended == null || (row.linked?.outsourced ?? false)) {
    return l.finishedNoDate;
  }
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

/// A service the home shows, in its order with the ended last, for the top bar's lists.
typedef _Shown = ({
  String name,
  String below,
  String link,
  String? chip,
  bool ok,
  int? renewId,
  bool renews,
});

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
  final _topRenew = FocusNode();
  final _topSupport = FocusNode();
  final _linkless = FocusNode();
  final _crashSend = FocusNode();
  final _crashNo = FocusNode();
  final _check = FocusNode();
  final _inUse = FocusNode();
  final _scroll = ScrollController();
  final _cards = <int, GlobalKey>{};
  (int?, bool, FocusNode?, bool)? _shown;

  /// The only card, folded by its arrow; two cards or more fold and open as the controller says.
  bool _folded = false;

  ({int id, double? top})? _opening;
  final _news = ValueNotifier<Record?>(null);
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
    _topRenew.dispose();
    _topSupport.dispose();
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
  void _onSwitch(Record? next) {
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

  /// The top bar's «پشتیبانی»: the one link every service shares, Shikoo's with none on the home,
  /// or a list of them. The list's pick is reported with the screen as it was at this tap.
  Future<void> _support(List<_Shown> services, {required bool isTV}) async {
    final links = {for (final service in services) service.link};
    if (links.length < 2) {
      return openSupport(
        context,
        isTV: isTV,
        link: links.firstOrNull ?? ShikooLinks.support,
        below: services.length == 1 ? services.single.below : null,
        trigger: 'support',
      );
    }
    final shots = await takeShots(context);
    if (!mounted) return;
    final l = ShikooL10n.of(context);
    await chooseService(
      context,
      isTV: isTV,
      title: l.supportPickTitle,
      help: isTV ? l.pickHelpTv : l.supportPickHelp,
      choices: [
        for (final service in services)
          (
            name: service.name,
            chip: service.chip,
            ok: service.ok,
            open: () => unawaited(
              openSupport(
                context,
                isTV: isTV,
                link: service.link,
                below: service.below,
                trigger: 'support',
                shots: shots,
              ),
            ),
          ),
      ],
    );
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

  /// b-warn «انتخاب سرور دیگر»: the list's fastest other server, the remote on it on the TV.
  void _toFastest(ShikooState state, ShikooController controller) {
    final others = {
      for (final server in state.servers)
        if (server.name != state.selected) server.name: server,
    };
    final name =
        fastest(
          [...others.keys],
          (name) => others[name]!.ping,
          handshake: (name) => others[name]!.core == ShikooCore.openvpn,
        ) ??
        others.keys.firstWhereOrNull((name) => !streamingOnly(name));
    final service = state.service;
    if (name == null || service == null) return;
    void show() {
      final row = _card.row(name);
      final at = row.context;
      if (at == null || !at.mounted) return;
      state.isTV
          ? jumpFocus(at, row)
          : unawaited(Scrollable.ensureVisible(at, alignment: 0.5));
    }

    if (_card.row(name).context?.mounted ?? false) return show();
    _open(controller, service.id);
    WidgetsBinding.instance.addPostFrameCallback((_) => show());
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
        _card.refresh,
      ].firstWhereOrNull((node) => _onScreen(node) && node.canRequestFocus);
      if (first != null) jumpFocus(first.context!, first);
    });
  }

  /// So the remote never stays on a button that just went away or went dead. [linkless]: the
  /// first card is one with no link here, and the remote starts on this.
  void _focusFirst(
    ShikooState state, {
    required FocusNode? linkless,
    required bool renews,
  }) {
    final service = state.service;
    final shown = (service?.id, restingFor(state) != null, linkless, renews);
    if (!state.isTV || shown == _shown) return;
    final focused = FocusManager.instance.primaryFocus;
    // The open card became the one in use, by a server pressed there: the remote stays on it.
    final stays =
        _shown != null &&
        service != null &&
        service.id == state.open &&
        !shown.$2 &&
        focused is! FocusScopeNode &&
        _onScreen(focused);
    _shown = shown;
    if (stays) return;
    // Not renewable, or revoked: the card has no renew, and support is the top bar's.
    final resting = renews && !(service?.revoked ?? false)
        ? _card.renew
        : _topSupport;
    final first =
        linkless ??
        (service == null ? _settings : (shown.$2 ? resting : _power));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (ModalRoute.isCurrentOf(context) ?? true)) {
        first.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // One bar for both: the end of one switch leaves the bar to the other, if it still runs.
    ref.listen(
      shikooStateProvider.select((state) => state.switching),
      (_, next) => _onSwitch(next ?? ref.read(shikooStateProvider).coreSwitch),
    );
    ref.listen(
      shikooStateProvider.select((state) => state.coreSwitch),
      (_, next) => _onSwitch(next ?? ref.read(shikooStateProvider).switching),
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
    final crashed =
        ref.watch(shikooCrashProvider) != null ||
        ref.watch(shikooCoreRevertedProvider) != null;
    final check = ref.watch(shikooProbeProvider);
    // Only a card that says the device itself is offline goes before WARP's line and offer.
    final offline =
        check?.value != null &&
        readProbes(check!.value, state.servers) == ProbeReading.offline;
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
    _focusFirst(
      state,
      linkless: first == null
          ? null
          : (first.finished && !first.renews && !first.outsourced
                ? _topSupport
                : _linkless),
      renews: renews,
    );
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
      bot: _card.bot,
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
      offline: offline,
      onOther: () => _toFastest(state, controller),
      onSupport: current == null
          ? null
          : () => unawaited(
              openSupport(
                context,
                isTV: state.isTV,
                link: current.supportLink,
                below: serviceTitle(context, current),
                trigger: 'support',
              ),
            ),
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
                tunnelServer: state.selected,
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
        if (update != null)
          UpdateCard(key: homeUpdateCard, offer: update, isTV: state.isTV),
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
    // A home with no service has its own paste and support buttons in its card.
    final noService = current == null && unlinked.isEmpty;
    final onAdd = noService ? null : () => unawaited(_add());
    _Shown onDevice(ShikooService service) => (
      name: plainTitle(context, service),
      below: serviceTitle(context, service),
      link: service.supportLink,
      chip: switch (service.ended) {
        null => l.statusActive,
        ShikooServiceStatus.revoked => l.chipRevoked,
        _ => l.chipFinished,
      },
      ok: service.ended == null,
      renewId: account.serviceOf(service.id),
      renews: !service.revoked && account.renewsOn(service.id),
    );
    // An account's service with no link here: the bot renews an active one by its own rule.
    _Shown ofAccount(LinkedService linked) => (
      name: linked.title,
      below: bidiName(linked.title),
      link: ShikooLinks.support,
      chip: linked.finished
          ? l.chipFinished
          : (linked.status == 'active' ? l.statusActive : null),
      ok: !linked.finished,
      renewId: linked.id,
      renews: linked.finished ? linked.renews : linked.botRenews,
    );
    final seen = [
      for (final service in cards) onDevice(service),
      for (final linked in noLink) ofAccount(linked),
      if (linkedTop != null) ofAccount(linkedTop),
      for (final service in revoked) onDevice(service),
      for (final row in rows)
        row.linked == null
            ? onDevice(listed.firstWhere((s) => s.id == row.profileId))
            : ofAccount(row.linked!),
    ];
    final shown = [
      ...seen.where((service) => service.ok),
      ...seen.where((service) => !service.ok),
    ];
    final renewable = <ServiceChoice>[
      for (final service in shown)
        if (service.renews)
          (
            name: service.name,
            chip: service.chip,
            ok: service.ok,
            open: () => openRenew(
              context,
              isTV: state.isTV,
              bot: account.bot,
              id: service.renewId,
              name: service.name,
            ),
          ),
    ];
    final onRenew = switch (renewable) {
      [] => null,
      [final only] => only.open,
      _ => () => unawaited(
        chooseService(
          context,
          isTV: state.isTV,
          title: l.renewPickTitle,
          help: state.isTV ? l.pickHelpTv : l.renewPickHelp,
          choices: renewable,
        ),
      ),
    };
    final top = [
      if (onRenew != null)
        ShikooButton(
          label: l.renew,
          icon: state.isTV ? ShikooIcon.qr : null,
          small: !state.isTV,
          primary: true,
          focusNode: _topRenew,
          onPressed: onRenew,
        ),
      if (!noService)
        ShikooButton(
          label: l.support,
          icon: state.isTV ? ShikooIcon.qr : null,
          small: !state.isTV,
          focusNode: _topSupport,
          onPressed: () => unawaited(_support(shown, isTV: state.isTV)),
        ),
    ];
    return PageWidth(
      child: Scaffold(
        backgroundColor: t.c.bg,
        body: PageFocusScope(
          child: FocusTraversalGroup(
            policy: PageTraversalPolicy(),
            child: state.isTV
                ? _BarKeys(
                    renew: _topRenew,
                    power: _power,
                    child: _TvLayout(
                      noService: noService,
                      settings: _settings,
                      actions: top,
                      power: _PowerKeys(
                        down:
                            offersWarp(state, offline: offline) ||
                            state.noInternet,
                        below:
                            state.noInternet && (current?.loginRefused ?? false)
                            ? _card.bot
                            : null,
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
                    ),
                  )
                : wide
                ? _WideLayout(
                    bar: _AppBar(actions: top, onAdd: onAdd),
                    power: power,
                    card: card,
                    scroll: _scroll,
                    room: _room,
                  )
                : _PhoneLayout(
                    bar: _AppBar(actions: top, onAdd: onAdd),
                    power: power,
                    card: card,
                    scroll: _scroll,
                    room: _room,
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
    refresh: service.refresh,
    open: state.open,
    landed: state.landed,
    cores: state.cores,
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

/// The card column's first row (an open card's head, a folded card), its item nearest [from].
FocusNode? _firstRow(FocusNode from) {
  final column = [
    for (final node in from.nearestScope?.traversalDescendants ?? <FocusNode>[])
      if (node.context?.findAncestorWidgetOfExactType<_CardKeys>() != null)
        node,
  ];
  final first = minBy(column, (node) => node.rect.top);
  if (first == null) return null;
  return minBy(
    column.where((node) => node.rect.top < first.rect.bottom),
    (node) => (node.rect.center.dx - from.rect.center.dx).abs(),
  );
}

/// Down from the top bar (the zones below answer their own keys): renew, over the gap where Flutter
/// picked the power button or a folded card under the list, to the cards; the rest to power.
class _BarKeys extends StatelessWidget {
  const _BarKeys({
    required this.renew,
    required this.power,
    required this.child,
  });

  final FocusNode renew;
  final FocusNode power;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            final from = primaryFocus;
            final next =
                from == null || intent.direction != TraversalDirection.down
                ? null
                : from == renew
                ? _firstRow(from)
                : power;
            if (_onScreen(next) && next!.canRequestFocus) {
              jumpFocus(context, next);
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

bool offersWarp(ShikooState state, {required bool offline}) =>
    !offline &&
    restingFor(state) == null &&
    state.lastError == ShikooError.noServer &&
    !state.bridge.on &&
    !(state.service?.loginRefused ?? false);

/// Toward the card: the crash card, the internet check, then the selected or first server.
class _PowerKeys extends StatelessWidget {
  const _PowerKeys({
    required this.targets,
    required this.child,
    this.down = false,
    this.below,
  });

  final List<FocusNode> targets;
  final Widget child;
  final bool down;
  final FocusNode? below;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final towardCard = rtl ? TraversalDirection.right : TraversalDirection.left;
    final stays = {
      rtl ? TraversalDirection.left : TraversalDirection.right,
      if (!down) TraversalDirection.down,
    };
    return Actions(
      actions: {
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            final target = targets.firstWhereOrNull(_onScreen);
            if (intent.direction == towardCard && target != null) {
              target.requestFocus();
            } else if (intent.direction == TraversalDirection.down &&
                _onScreen(below)) {
              below!.requestFocus();
            } else if (!stays.contains(intent.direction)) {
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
            final head = {
              focus.refresh,
              focus.caret,
              focus.ping,
            }.contains(from);
            final next = switch (intent.direction) {
              TraversalDirection.down when head => [
                focus.other,
                focus.report,
                focus.renew,
              ].firstWhereOrNull(_onScreen),
              TraversalDirection.up when from == focus.renew =>
                [focus.other, focus.report].firstWhereOrNull(_onScreen) ??
                    focus.ping,
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
    required this.actions,
    required this.power,
    required this.card,
  });

  final bool noService;
  final FocusNode settings;
  final List<Widget> actions;
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.s3,
                  children: [
                    ...actions,
                    ShikooButton(
                      label: ShikooL10n.of(context).settings,
                      icon: ShikooIcon.gear,
                      autofocus: noService,
                      focusNode: settings,
                      onPressed: () => openSettings(context),
                    ),
                  ],
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
    required this.bar,
    required this.power,
    required this.card,
    required this.scroll,
    required this.room,
  });

  final Widget bar;
  final Widget power;
  final Widget card;
  final ScrollController scroll;

  /// The switch bar's, which the last rows can rise above.
  final double room;

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
        bar,
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
  const _AppBar({required this.actions, this.onAdd});

  final List<Widget> actions;

  /// The «+» beside Settings (phone-p4a-home); none without it.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final s = ShikooTheme.of(context).s;
    final icons = (onAdd == null ? 1 : 2) * ShikooSizes.touch;
    return Container(
      height: s.appbar,
      padding: EdgeInsetsDirectional.only(start: s.safeX, end: Space.s1),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            const Expanded(child: Brand(fit: true)),
            if (actions.isNotEmpty) ...[
              // Text too large for even the mark alone beside them shrinks them, never overflows.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(
                    0.0,
                    box.maxWidth - icons - Space.s1 - s.mark - Space.s2,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.s2,
                    children: actions,
                  ),
                ),
              ),
              const SizedBox(width: Space.s1),
            ],
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
      ),
    );
  }
}

/// `.win-home` (win-modes.html, frame `win-w-b`): the TV's two columns at the phone's sizes.
class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.bar,
    required this.power,
    required this.card,
    required this.scroll,
    required this.room,
  });

  final Widget bar;
  final Widget power;
  final Widget card;
  final ScrollController scroll;
  final double room;

  @override
  Widget build(BuildContext context) {
    final s = ShikooTheme.of(context).s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
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
    this.offline = false,
    this.onOther,
    this.onSupport,
    this.bot,
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
  final bool offline;
  final VoidCallback? onOther;
  final VoidCallback? onSupport;

  /// The service card's bot button: a refused shelf account's one way, where the amber card would be.
  final FocusNode? bot;

  bool get _silent =>
      state.connection == ShikooConnection.on &&
      (state.selectedServer?.ping ?? 0) < 0;

  // The phone's switch news is its bottom bar; the TV's is this slot, which never moves.
  ShikooSwitch? get _shift => state.isTV ? state.switching : null;
  ShikooCoreSwitch? get _coreShift => state.isTV ? state.coreSwitch : null;

  /// c-*: WARP's own line, which a computer shows in the pills' place under the button (c-win-first).
  String? warpLine(ShikooL10n l) {
    if (state.service == null ||
        restingFor(state) != null ||
        state.busyPort != null ||
        state.helperFailed) {
      return null;
    }
    String here(String tv, String desktop, String touch) =>
        state.isTV ? tv : (shikooDesktop ? desktop : touch);
    final selected = state.selectedServer;
    if (state.lastError == ShikooError.noServer) {
      return switch (state.bridge) {
        _ when offline => null,
        (on: false, via: _, trying: _, failed: _, door: _) => here(
          l.warpOffTv,
          l.warpOffDesktop,
          l.warpOffTouch,
        ),
        (on: true, via: _, trying: _, failed: true, door: _) => here(
          l.warpFailBothTv,
          l.warpFailBothDesktop,
          l.warpFailBothTouch,
        ),
        _ => null,
      };
    }
    if (state.lastError != null ||
        state.connection != ShikooConnection.connecting) {
      return null;
    }
    final tried = (selected?.viaBridge ?? false)
        ? selected!.name
        : state.bridge.via.firstOrNull;
    if (state.bridge.trying && tried != null) {
      return l.warpFirst(serverName(tried));
    }
    return (selected?.viaBridge ?? false) ? l.warpAgain : null;
  }

  String? message(ShikooL10n l) {
    // A refused shelf account: its card says why; WARP or this phone's internet would not help.
    if (state.service?.loginRefused ?? true) return null;
    if (warpLine(l) case final warp?) return warp;
    final resting = restingFor(state);
    final selected = state.selectedServer;
    final silent = _silent;
    final shift = _shift;
    final coreShift = _coreShift;
    return switch (state.lastError) {
      _ when resting == ShikooServiceStatus.revoked => null,
      _ when resting != null => renews ? l.renewToConnect : null,
      ShikooError.connectTimeout =>
        (state.isTV
            ? l.errorConnect
            : (shikooDesktop ? l.errorConnectDesktop : l.errorConnectTouch))(
          // A break may come after «·», never before it: no line opens with «· premium».
          serverName(selected?.name ?? '').replaceAll(' ·\u00a0', '\u00a0· '),
          (selected?.core == ShikooCore.openvpn
                  ? openvpnConnectLimit
                  : connectTimeout)
              .inSeconds,
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
      null when coreShift != null => coreNews(l, coreShift).join(' '),
      null when silent && !state.noInternet => l.selectedDown(
        serverName(selected!.name),
      ),
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
    // shortcut: measured on each build; cache by names and text size if a long list shows up.
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
    if (!shikooDesktop && !state.isTV) {
      return _column(context, s.powerRing * 1.5);
    }
    return LayoutBuilder(
      builder: (context, box) => _column(
        context,
        math.min(shikooDesktop ? s.dialog : s.powerRing * 1.5, box.maxWidth),
      ),
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
    // Sam, 2026-10-31: on Windows a shelf account's button is dimmed and its pill hidden, in their usual places.
    final notHere = state.service?.notHere ?? false;
    final silent = _silent;
    final alarm = switch ((_shift, _coreShift)) {
      (final shift?, _) => shift.stage == ShikooSwitchStage.failed,
      (_, final core?) => core.stage == ShikooSwitchStage.failed,
      _ => silent,
    };
    final message = this.message(l);
    final room = shikooDesktop
        ? _room(context, l, width)
        : (centred ? twoLines(context, t.text(t.s.bodySm)) : null);
    final slot = room == null ? null : math.max(room, t.s.speedPill);
    final warp = warpLine(l);
    final under =
        slot != null &&
        (state.connection == ShikooConnection.on ||
            shikooDesktop && warp != null);
    final failed =
        state.lastError != null || state.busyPort != null || state.helperFailed;
    final offerWarp = offersWarp(state, offline: offline);
    // `.tv-power`'s padding-inline: the remote's ring around the card's button stays inside the column.
    final cardWidth = state.isTV
        ? width - 2 * ShikooSizes.ring
        : (shikooDesktop ? width : double.infinity);
    final card = message != null
        ? null
        : state.noInternet && !(state.service?.loginRefused ?? false)
        ? _NoInternet(
            name: serverName(selected!.name),
            isTV: state.isTV,
            width: cardWidth,
            onOther: onOther,
            onSupport:
                state.servers.any(
                  (server) =>
                      server.name != state.selected &&
                      !streamingOnly(server.name),
                )
                ? null
                : onSupport,
            power: focusNode,
          )
        : (state.connection == ShikooConnection.on && state.streaming
              ? _StreamingCard(width: cardWidth)
              : null);
    // WARP's first try and its failure: two lines wrapping to three on the TV too, where the room is two.
    final tall =
        offerWarp ||
        (state.isTV && (card != null || (warp?.contains('\n') ?? false)));
    final text = Text(
      message ?? '',
      // A phone's message may wrap a line: WARP's failure and first try are two lines, the second one long.
      maxLines: shikooDesktop ? null : (centred && !tall ? 2 : 3),
      overflow: shikooDesktop ? null : TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: t.text(
        t.s.bodySm,
        color: resting != null || (!failed && !alarm)
            ? t.c.textMuted
            : t.c.danger,
      ),
    );
    final say = message != null || slot != null
        ? _InView(
            key: ValueKey(message),
            message: message,
            // A computer's text can be set half as large again: the message grows, never cut.
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: width).copyWith(
                minHeight: slot ?? 0,
                maxHeight: shikooDesktop || tall ? double.infinity : slot,
              ),
              child: under ? Center(child: text) : text,
            ),
          )
        : null;
    final offer = _WarpOffer(
      isTV: state.isTV,
      onPressed: () => unawaited(controller.setBridge(true)),
    );
    final items = [
      PowerButton(
        connection: state.connection,
        connectedFor: state.connectedFor,
        isTV: state.isTV,
        focusNode: focusNode,
        switching: state.switching?.stage == ShikooSwitchStage.moving,
        warn: state.noInternet,
        restingLabel: switch (resting) {
          null when notHere => l.powerConnect,
          ShikooServiceStatus.exhausted => l.stateExhausted,
          ShikooServiceStatus.revoked => l.chipRevoked,
          _ => l.powerExpired,
        },
        onPressed: resting != null || notHere
            ? null
            : () => unawaited(switch (state.connection) {
                ShikooConnection.off ||
                ShikooConnection.error => controller.connect(),
                ShikooConnection.connecting ||
                ShikooConnection.on => controller.disconnect(),
              }),
      ),
      if (under)
        message == null
            ? Container(
                constraints: BoxConstraints(minHeight: slot),
                alignment: Alignment.center,
                child:
                    card ??
                    (!state.noInternet
                        ? const SpeedPills()
                        : state.isTV && bot != null
                        ? _FromPower(
                            power: focusNode,
                            node: bot!,
                            child: const SizedBox.shrink(),
                          )
                        : null),
              )
            : say!
      else if (state.connection == ShikooConnection.on && !state.noInternet)
        const SpeedPills(),
      if (resting == null) ...[
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: state.isTV ? cardWidth : double.infinity,
          ),
          child: Visibility(
            visible: !notHere,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: NowPill(
              pick: state.pick,
              server: selected,
              via: (selected?.viaBridge ?? false) ? l.warpVia : null,
              trying:
                  state.bridge.trying &&
                  (selected?.viaBridge ?? false) &&
                  (selected?.ping ?? -1) < 0,
            ),
          ),
        ),
        if (!under && card != null) card,
        // c-off-win: the offer keeps with its message, above the mode switch.
        if (shikooDesktop && offerWarp) offer,
        if (shikooDesktop) ...[
          ModeSwitch(
            connecting: state.connection == ShikooConnection.connecting,
          ),
          const LocalProxy(),
        ],
      ],
      if (!under && say != null) say,
      if (offerWarp && !shikooDesktop) offer,
    ];
    if (squeeze) {
      return _Squeeze(
        gap: gap,
        keep: under || offerWarp ? 0 : slot!,
        children: items,
      );
    }
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Balances the message's room, below or under the button, so the TV's button never moves.
        if (slot != null && state.isTV && !tall) SizedBox(height: gap + slot),
        for (final (i, item) in items.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          item,
        ],
      ],
    );
    // c-tv-off, a-tv-fail: the button moves up for WARP's lines; large text shrinks the column, never cuts it.
    return state.isTV && tall
        ? FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(width: width, child: column),
          )
        : column;
  }
}

/// b-warn: the card in the speed pills' room; on a computer one row, its button small; on the TV the remote moves
/// to the button as it comes, from the round button only, so the remote's OK no longer drops the connection.
class _NoInternet extends StatefulWidget {
  const _NoInternet({
    required this.name,
    required this.isTV,
    required this.width,
    required this.onOther,
    required this.power,
    this.onSupport,
  });

  final String name;
  final bool isTV;
  final double width;
  final VoidCallback? onOther;

  /// A service with one server: no other to choose, so its support instead.
  final VoidCallback? onSupport;
  final FocusNode power;

  @override
  State<_NoInternet> createState() => _NoInternetState();
}

class _NoInternetState extends State<_NoInternet> {
  final _node = FocusNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final title = widget.isTV
        ? l.noInternetTitleTv
        : l.noInternetTitle(widget.name);
    final support = widget.onSupport;
    final label = support == null ? l.noInternetOther : l.support;
    final onPressed = support ?? widget.onOther;
    if (shikooDesktop) {
      return SizedBox(
        width: widget.width,
        child: Row(
          spacing: Space.s2,
          children: [
            SvgIcon(ShikooIcon.warn, size: t.s.iconSm, color: t.c.warning),
            Expanded(
              child: Text(
                title,
                style: t.text(t.s.bodySm, weight: FontWeight.w700),
              ),
            ),
            // The message's room is two lines: the face fits it, the touch padding is left outside.
            SizedBox(
              height: t.s.buttonSm,
              child: OverflowBox(
                maxHeight: ShikooSizes.touch,
                fit: OverflowBoxFit.deferToChild,
                child: ShikooButton(
                  label: label,
                  small: true,
                  focusNode: _node,
                  onPressed: onPressed,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final gap = widget.isTV ? Space.s2 : Space.s3;
    final card = Container(
      width: widget.width,
      padding: EdgeInsets.all(widget.isTV ? Space.s3 : Space.s4),
      decoration: ShapeDecoration(
        color: t.c.surface,
        shadows: t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gap,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.s3,
            children: [
              SvgIcon(ShikooIcon.warn, size: t.s.icon, color: t.c.warning),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: t.text(
                        t.s.body,
                        weight: FontWeight.w700,
                        height: Leading.snug,
                      ),
                    ),
                    Text(
                      switch ((support, widget.isTV)) {
                        (null, _) => l.noInternetBody,
                        (_, true) => l.noInternetOneTv,
                        _ => l.noInternetOne,
                      },
                      style: t.text(
                        t.s.bodySm,
                        color: t.c.textMuted,
                        height: Leading.snug,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ShikooButton(
            label: label,
            icon: support == null
                ? ShikooIcon.lines
                : (widget.isTV ? ShikooIcon.qr : null),
            focusNode: _node,
            onPressed: onPressed,
          ),
        ],
      ),
    );
    return widget.isTV
        ? _FromPower(power: widget.power, node: _node, child: card)
        : card;
  }
}

/// On the TV the remote moves to [node] as it comes, from the round button only, so its OK keeps the connection.
class _FromPower extends StatefulWidget {
  const _FromPower({
    required this.power,
    required this.node,
    required this.child,
  });

  final FocusNode power;
  final FocusNode node;
  final Widget child;

  @override
  State<_FromPower> createState() => _FromPowerState();
}

class _FromPowerState extends State<_FromPower> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = FocusManager.instance.primaryFocus;
      if (mounted &&
          _onScreen(widget.node) &&
          (at == null || at == widget.power || at is FocusScopeNode)) {
        widget.node.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// b-special: what the free streaming server is for; never the no-internet card. Flat on a computer, two lines.
class _StreamingCard extends StatelessWidget {
  const _StreamingCard({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final lines = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.streamingTitle,
          textAlign: TextAlign.center,
          style: t.text(
            shikooDesktop ? t.s.bodySm : t.s.body,
            weight: FontWeight.w700,
            height: shikooDesktop ? Leading.tight : Leading.snug,
          ),
        ),
        Text(
          l.streamingBody,
          textAlign: TextAlign.center,
          style: t.text(
            t.s.bodySm,
            color: t.c.textMuted,
            height: shikooDesktop ? Leading.tight : Leading.snug,
          ),
        ),
      ],
    );
    if (shikooDesktop) return SizedBox(width: width, child: lines);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(
        vertical: Space.s3,
        horizontal: Space.s4,
      ),
      decoration: ShapeDecoration(
        color: t.c.surfaceSunken,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      child: lines,
    );
  }
}

/// «روشن کردن WARP» and what Cloudflare sees; c-tv-off: on the TV the remote moves to it as it comes.
class _WarpOffer extends StatefulWidget {
  const _WarpOffer({required this.isTV, required this.onPressed});

  final bool isTV;
  final VoidCallback onPressed;

  @override
  State<_WarpOffer> createState() => _WarpOfferState();
}

class _WarpOfferState extends State<_WarpOffer> {
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.isTV) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.s2,
      children: [
        ShikooButton(
          label: l.warpTurnOn,
          focusNode: _node,
          onPressed: widget.onPressed,
        ),
        Text(
          l.warpNote,
          textAlign: TextAlign.center,
          style: t.text(t.s.bodySm, color: t.c.textMuted),
        ),
      ],
    );
  }
}

/// A computer's wide button column, centred in the least height asked: short of room, its gaps
/// give way evenly down to Space.s2, then the button to [ShikooSizes.powerRingLeast]; the last as if [keep] tall.
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
    final gaps = children.length - 1;
    final room = constraints.minHeight;
    double tall() =>
        children.map((child) => child.size.height).sum -
        children.last.size.height +
        (keep > 0 ? keep : children.last.size.height);
    final over = tall() + gaps * Space.s2 - room;
    if (over > 0) {
      final button = children.first;
      button.layout(
        BoxConstraints(
          maxWidth: width,
          maxHeight: math.max(
            ShikooSizes.powerRingLeast,
            button.size.height - over,
          ),
        ),
        parentUsesSize: true,
      );
    }
    final placed = tall();
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

  final ValueNotifier<Record?> news;
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
        final (stage, [first, ...rest]) = switch (shift) {
          final ShikooCoreSwitch core => (core.stage, coreNews(l, core)),
          final ShikooSwitch server => (server.stage, switchNews(l, server)),
          _ => throw StateError('$shift'),
        };
        final icon = switch (stage) {
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
    // A closed shelf account is never renewed: the bot sells a new one.
    final ended = finished && service.outsourced;
    final supportOnly = finished && !renews && !ended;
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
              if (ended)
                StatusChip(
                  status: ShikooServiceStatus.expired,
                  label: l.chipFinished,
                )
              else if (finished)
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
              _ when ended => l.outsourcedEnded,
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
          // Not renewable, a phone's card is its text alone; support is the top bar's.
          if (!supportOnly || isTV) ...[
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
                          ? openRenew(
                              context,
                              isTV: isTV,
                              bot: bot,
                              id: service.id,
                              name: service.title,
                            )
                          : openBot(context, isTV: isTV, bot: bot),
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

  void _renew(Finished row) => openRenew(
    context,
    isTV: widget.isTV,
    bot: widget.account.bot,
    id: row.renewId,
    name: row.name,
  );

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
    (String, ShikooIcon?, VoidCallback)? actionOf(Finished row) =>
        switch (row) {
          _ when widget.account.renews(row) => (
            l.renew,
            isTV ? ShikooIcon.qr : null,
            () => _renew(row),
          ),
          _ when row.linked?.outsourced ?? false => (
            isTV ? l.openBotTv : l.openBotTouch,
            isTV ? ShikooIcon.qr : ShikooIcon.plane,
            () => openBot(context, isTV: isTV, bot: widget.account.bot),
          ),
          _ => null,
        };
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
          if (actionOf(row) case (final label, final icon, final act))
            isTV
                ? ExcludeFocus(
                    child: IgnorePointer(
                      child: ShikooButton(
                        label: label,
                        icon: icon,
                        small: true,
                        onPressed: () {},
                      ),
                    ),
                  )
                : ShikooButton(
                    label: label,
                    icon: icon,
                    small: true,
                    onPressed: act,
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
                    onPressed: actionOf(row)?.$3,
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
