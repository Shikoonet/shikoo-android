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

  @override
  void dispose() {
    _card.dispose();
    _power.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shikooStateProvider);
    final controller = ref.watch(shikooControllerProvider);
    final account = ref.watch(shikooAccountProvider);
    final t = ShikooTheme.of(context);
    final power = _PowerZone(
      state: state,
      controller: controller,
      focusNode: _power,
    );
    final waiting = account.waitingForBot.isEmpty
        ? null
        : _WaitingForBot(services: account.waitingForBot, bot: account.bot);
    final service = ServiceCard(
      state: state,
      controller: controller,
      focus: _card,
      serviceId: account.serviceOf(state.service?.profileId),
      bot: account.bot,
    );
    Widget card(Widget service) => waiting == null
        ? service
        : state.service == null
        ? waiting
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s3,
            children: [waiting, service],
          );
    final towardCard = state.selected ?? state.servers.firstOrNull?.name;
    return Scaffold(
      backgroundColor: t.c.bg,
      body: PageFocusScope(
        child: FocusTraversalGroup(
          policy: PageTraversalPolicy(),
          child: state.isTV
              ? _TvLayout(
                  noService: state.service == null,
                  power: _PowerKeys(
                    row: towardCard == null ? null : _card.row(towardCard),
                    child: power,
                  ),
                  card: card(
                    _CardKeys(focus: _card, power: _power, child: service),
                  ),
                )
              : _PhoneLayout(power: power, card: card(service)),
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
                intent.direction == TraversalDirection.down) {
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
    required this.power,
    required this.card,
  });

  final bool noService;
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
  const _PhoneLayout({required this.power, required this.card});

  final Widget power;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final s = ShikooTheme.of(context).s;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.s6),
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
  });

  final ShikooState state;
  final ShikooController controller;
  final FocusNode focusNode;

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
        ),
      );
    }
    final silent =
        state.connection == ShikooConnection.on && (selected?.ping ?? 0) < 0;
    final message = switch (state.lastError) {
      ShikooError.connectTimeout => l.errorConnect(
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
          onPressed: () => unawaited(switch (state.connection) {
            ShikooConnection.off ||
            ShikooConnection.error => controller.connect(),
            ShikooConnection.connecting ||
            ShikooConnection.on => controller.disconnect(),
          }),
        ),
        SizedBox(height: gap),
        NowPill(pick: state.pick, server: selected),
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
                color: state.lastError == null && !silent
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

/// Services of the account whose link the bot makes the first time it opens them there.
class _WaitingForBot extends ConsumerWidget {
  const _WaitingForBot({required this.services, required this.bot});

  final List<LinkedService> services;
  final String? bot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final isTV = ref.watch(shikooStateProvider.select((s) => s.isTV));
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
        spacing: Space.s2,
        children: [
          for (final service in services)
            Text(
              l.waitingForBot(service.title),
              style: t.text(t.s.title, weight: FontWeight.w700),
            ),
          Text(
            l.waitingForBotHelp,
            style: t.text(
              t.s.bodySm,
              color: t.c.textMuted,
              height: Leading.body,
            ),
          ),
          Row(
            spacing: Space.s2,
            children: [
              Expanded(
                child: ShikooButton(
                  label: l.openBot,
                  icon: isTV ? ShikooIcon.qr : ShikooIcon.plane,
                  primary: true,
                  onPressed: () => openLink(
                    context,
                    isTV: isTV,
                    link: ShikooLinks.openBot(bot),
                    title: l.openBotTitle,
                    help: l.openBotHelp,
                  ),
                ),
              ),
              Expanded(
                child: ShikooButton(
                  label: l.retry,
                  icon: ShikooIcon.refresh,
                  onPressed: () =>
                      unawaited(ref.read(shikooSignInProvider).sync()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
