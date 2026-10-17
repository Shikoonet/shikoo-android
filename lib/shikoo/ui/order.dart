import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/order.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// phone-p5b-order and tv-p5-order: the services that still run, folded, in card order. On the
/// phone ≡ drags a card; on the TV OK picks one up, up and down carry it, OK puts it down and
/// Back puts it back. Every drop is saved at once.
class ServiceOrder extends ConsumerStatefulWidget {
  const ServiceOrder({super.key});

  @override
  ConsumerState<ServiceOrder> createState() => _ServiceOrderState();
}

class _ServiceOrderState extends ConsumerState<ServiceOrder> {
  final _nodes = <int, FocusNode>{};
  int? _picked;

  /// The TV's order while a card is picked up, saved only when it is put down.
  List<int>? _moving;

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _save(List<int> ids) =>
      unawaited(ref.read(savedOrderProvider.notifier).save(ids));

  void _press(List<int> shown, int id) {
    final moving = _moving;
    if (moving != null) _save(moving);
    setState(() {
      _picked = moving == null ? id : null;
      _moving = moving == null ? shown : null;
    });
  }

  void _move(TraversalDirection direction) {
    final picked = _picked!;
    final moving = [..._moving!];
    final from = moving.indexOf(picked);
    final to = from + (direction == TraversalDirection.up ? -1 : 1);
    if (to < 0 || to >= moving.length) return;
    moving[from] = moving[to];
    moving[to] = picked;
    setState(() => _moving = moving);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_nodes[picked]?.context case final card? when card.mounted) {
        revealWithRing(card);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final state = ref.watch(shikooStateProvider);
    final saved = ref.watch(serviceOrderProvider);
    final byId = {
      for (final s in [?state.service, ...state.others]) s.id: s,
    };
    final shown = [
      for (final id in _moving ?? saved)
        if (byId[id] case final service? when !service.finished) service,
    ];
    final live = state.connection == ShikooConnection.on;
    _OrderCard card(
      ShikooService service, {
      Widget? handle,
      bool focused = false,
      bool raised = false,
    }) => _OrderCard(
      service: service,
      inUse: service.id == state.service?.id,
      live: live,
      handle: handle,
      focused: focused,
      raised: raised,
      picked: service.id == _picked,
    );
    if (!state.isTV) {
      final grip = SizedBox.square(
        dimension: ShikooSizes.touch,
        child: Center(
          child: SvgIcon(
            ShikooIcon.handle,
            size: t.s.icon,
            color: t.c.textMuted,
          ),
        ),
      );
      return SubPage(
        title: l.orderServices,
        isTV: false,
        scrolls: false,
        child: ReorderableListView(
          buildDefaultDragHandles: false,
          padding: EdgeInsets.fromLTRB(
            t.s.safeX,
            0,
            t.s.safeX,
            Space.s6 + MediaQuery.paddingOf(context).bottom,
          ),
          header: Padding(
            padding: const EdgeInsets.only(bottom: Space.s4),
            child: Text(
              (shikooDesktop ? l.orderScreenHelpDesktop : l.orderScreenHelp),
              style: t.text(
                t.s.bodySm,
                color: t.c.textMuted,
                height: Leading.body,
              ),
            ),
          ),
          onReorderItem: (from, to) {
            final ids = [for (final service in shown) service.id];
            ids.insert(to, ids.removeAt(from));
            _save(ids);
          },
          proxyDecorator: (_, index, _) => Material(
            type: MaterialType.transparency,
            child: card(shown[index], raised: true, handle: grip),
          ),
          children: [
            for (final (i, service) in shown.indexed)
              Padding(
                key: ValueKey(service.id),
                padding: const EdgeInsets.only(bottom: Space.s3),
                child: card(
                  service,
                  handle: ReorderableDragStartListener(
                    index: i,
                    child: Semantics(
                      button: true,
                      label: l.orderHandleLabel(plainTitle(context, service)),
                      excludeSemantics: true,
                      child: grip,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    final ids = [for (final service in shown) service.id];
    return PopScope(
      canPop: _picked == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          _picked = null;
          _moving = null;
        });
      },
      child: SubPage(
        title: l.orderServices,
        isTV: true,
        scrolls: false,
        hint: _picked == null ? l.orderTvHintRest : l.orderTvHintMoving,
        child: Center(
          child: SizedBox(
            width: t.s.pane,
            child: TvScrollColumn(
              child: Actions(
                actions: {
                  DirectionalFocusIntent:
                      CallbackAction<DirectionalFocusIntent>(
                        onInvoke: (intent) {
                          final vertical = {
                            TraversalDirection.up,
                            TraversalDirection.down,
                          }.contains(intent.direction);
                          if (_picked == null) {
                            primaryFocus?.focusInDirection(intent.direction);
                          } else if (vertical) {
                            _move(intent.direction);
                          }
                          return null;
                        },
                      ),
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s3,
                  children: [
                    for (final (i, service) in shown.indexed)
                      Pressable(
                        key: ValueKey(service.id),
                        focusNode: _nodes.putIfAbsent(
                          service.id,
                          FocusNode.new,
                        ),
                        autofocus: i == 0,
                        shape: RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(Radii.lg),
                        ),
                        onPressed: () => _press(ids, service.id),
                        builder: (context, focused) =>
                            card(service, focused: focused),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.order-list .svc`: «در حال استفاده» and its bar on the service in use, the name, the status;
/// `.is-dragging` [raised] and `.is-picked` filled with the primary colour, with ▲▼.
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.service,
    required this.inUse,
    required this.live,
    this.handle,
    this.focused = false,
    this.raised = false,
    this.picked = false,
  });

  final ShikooService service;
  final bool inUse;

  /// Connected: the in-use mark is green, else grey.
  final bool live;
  final Widget? handle;
  final bool focused;
  final bool raised;
  final bool picked;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final ink = picked ? t.c.onPicked : t.c.text;
    final handle = this.handle;
    return Container(
      decoration: ShapeDecoration(
        color: picked
            ? t.c.picked
            : (focused || raised ? t.c.focusBg : t.c.surface),
        shadows: picked || focused || raised
            ? t.c.raisedShadow
            : t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: Space.s4,
          end: handle == null ? Space.s4 : Space.s1,
          top: Space.s3,
          bottom: Space.s3,
        ),
        child: Row(
          children: [
            Expanded(
              child: InUseMark(
                live: inUse ? live : null,
                color: picked ? ink : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.s2,
                  children: [
                    ServiceName(
                      plainTitle(context, service),
                      twoLines: true,
                      style: t.text(
                        t.s.title,
                        weight: FontWeight.w700,
                        height: Leading.snug,
                        color: ink,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        StatusChip(
                          status: service.ended ?? ShikooServiceStatus.active,
                        ),
                        if (picked)
                          Text(
                            l.orderTvPicked,
                            style: t.text(
                              t.s.bodySm,
                              weight: FontWeight.w700,
                              height: Leading.tight,
                              color: ink,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (picked)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mark in [
                    ShikooIcon.chevronUp,
                    ShikooIcon.chevronDown,
                  ])
                    SvgIcon(
                      mark,
                      size: t.s.icon,
                      color: ink,
                      stroke: ShikooSizes.iconStrokeStrong,
                    ),
                ],
              )
            else
              ?handle,
          ],
        ),
      ),
    );
  }
}
