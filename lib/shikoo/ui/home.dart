import 'dart:async';

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
    final first = service != null
        ? (shown.$2 ? _card.renew : _power)
        : (linkless ? _linkless : _settings);
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
    final hasService = state.service != null;
    final unlinked = account.withoutLink;
    _focusFirst(state, linkless: !hasService && unlinked.isNotEmpty);
    final power = _PowerZone(
      state: state,
      controller: controller,
      focusNode: _power,
      restingLabel: switch (unlinked.firstOrNull?.status) {
        null => null,
        'expired' => l.chipExpired,
        'exhausted' => l.stateExhausted,
        _ => l.noLinkChip,
      },
    );
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.s3,
      children: [
        for (final (i, linked) in unlinked.indexed)
          _LinklessCard(
            service: linked,
            bot: account.bot,
            isTV: state.isTV,
            focusNode: i == 0 && !hasService ? _linkless : null,
          ),
        if (hasService || unlinked.isEmpty)
          ServiceCard(
            key: ValueKey(state.service?.id),
            state: state,
            controller: controller,
            focus: _card,
            serviceId: account.serviceOf(state.service?.id),
            bot: account.bot,
          ),
        for (final other in state.others)
          FoldedServiceCard(
            key: ValueKey(other.id),
            service: other,
            refresh: other.refresh,
            isTV: state.isTV,
            onOpen: () => _use(controller, other.id),
            onRefresh: () => unawaited(controller.refreshOther(other.id)),
          ),
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
                  noService: !hasService && unlinked.isEmpty,
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
  });

  final ShikooState state;
  final ShikooController controller;
  final FocusNode focusNode;
  final String? restingLabel;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final selected = state.selectedServer;
    final gap = state.isTV ? Space.s4 : Space.s3;
    if (state.service == null) {
      return Padding(
        padding: EdgeInsets.only(bottom: state.isTV ? gap : 0),
        child: PowerButton(
          connection: ShikooConnection.off,
          connectedFor: Duration.zero,
          isTV: state.isTV,
          onPressed: null,
          restingLabel: restingLabel,
        ),
      );
    }
    final resting = restingFor(state);
    final silent =
        state.connection == ShikooConnection.on && (selected?.ping ?? 0) < 0;
    final message = switch (state.lastError) {
      _ when resting != null =>
        state.others.any((other) => other.ended == null)
            ? l.renewOrSwitch
            : l.renewToConnect,
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
          restingLabel: resting == ShikooServiceStatus.exhausted
              ? l.stateExhausted
              : l.powerExpired,
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
          Row(
            children: [
              Expanded(
                child: nameText(
                  context,
                  service.title,
                  t.text(
                    t.s.title,
                    weight: FontWeight.w700,
                    height: Leading.snug,
                  ),
                ),
              ),
              const SizedBox(width: Space.s2),
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
            renews ? l.renewToUse : (isTV ? l.noLinkHelpTv : l.noLinkHelpTouch),
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
