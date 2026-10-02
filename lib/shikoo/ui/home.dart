import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/focus.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Home, laid out after `design/mockups/tv.html` (frames `tv-home-*`) and `phone.html`.
class ShikooHome extends ConsumerWidget {
  const ShikooHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shikooStateProvider);
    final controller = ref.watch(shikooControllerProvider);
    final t = ShikooTheme.of(context);
    final power = _PowerZone(state: state, controller: controller);
    final card = ServiceCard(state: state, controller: controller);
    return Scaffold(
      backgroundColor: t.c.bg,
      body: PageFocusScope(
        child: FocusTraversalGroup(
          policy: PageTraversalPolicy(),
          child: state.isTV
              ? _TvLayout(power: power, card: card)
              : _PhoneLayout(power: power, card: card),
        ),
      ),
    );
  }
}

/// `.tv`, `.tv-top` and `.tv-home`: the card column at the start, the power button beside it.
class _TvLayout extends StatelessWidget {
  const _TvLayout({required this.power, required this.card});

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
                // The settings screen comes in a later round.
                ShikooButton(
                  label: ShikooL10n.of(context).settings,
                  icon: ShikooIcon.gear,
                  onPressed: () {},
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

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return LayoutBuilder(
      builder: (context, box) => OverflowBox(
        maxWidth: box.maxWidth + 2 * Space.s2,
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
    );
  }
}

class _PhoneLayout extends StatelessWidget {
  const _PhoneLayout({required this.power, required this.card});

  final Widget power;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    return SafeArea(
      child: Column(
        children: [
          Container(
            height: s.appbar,
            padding: EdgeInsetsDirectional.only(start: s.safeX, end: Space.s1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Brand(),
                Pressable(
                  shape: const CircleBorder(),
                  onPressed: () {},
                  builder: (context, _) => Semantics(
                    button: true,
                    label: ShikooL10n.of(context).settings,
                    child: SizedBox.square(
                      dimension: ShikooSizes.touch,
                      child: Center(
                        child: SvgIcon(
                          ShikooIcon.gear,
                          size: s.icon,
                          color: t.c.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                s.safeX,
                Space.s2,
                s.safeX,
                Space.s6,
              ),
              child: Column(
                children: [
                  power,
                  const SizedBox(height: Space.s3),
                  card,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.tv-power` / `.power-zone`: the button, the selected server, and a hint or an error.
class _PowerZone extends StatelessWidget {
  const _PowerZone({required this.state, required this.controller});

  final ShikooState state;
  final ShikooController controller;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final selected = state.selectedServer;
    final gap = state.isTV ? Space.s4 : Space.s3;
    final message = switch (state.lastError) {
      ShikooError.connectTimeout => l.errorConnect(
        selected?.label ?? '',
        connectTimeout.inSeconds,
      ),
      ShikooError.serverChange => l.errorServer,
      ShikooError.addService => l.errorAdd,
      null =>
        state.isTV && state.connection == ShikooConnection.off
            ? l.tvHint
            : null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PowerButton(
          connection: state.connection,
          connectedFor: state.connectedFor,
          isTV: state.isTV,
          onPressed: () => unawaited(switch (state.connection) {
            ShikooConnection.off ||
            ShikooConnection.error => controller.connect(),
            ShikooConnection.connecting ||
            ShikooConnection.on => controller.disconnect(),
          }),
        ),
        if (selected != null) ...[
          SizedBox(height: gap),
          NowPill(server: selected),
        ],
        if (message != null) ...[
          SizedBox(height: gap),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: t.s.powerRing * 1.5),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: t.text(
                t.s.bodySm,
                color: state.lastError == null ? t.c.textMuted : t.c.danger,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
