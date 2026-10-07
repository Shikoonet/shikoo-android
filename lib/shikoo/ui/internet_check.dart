import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

typedef _Action = (
  String label,
  ShikooIcon? icon,
  VoidCallback onPressed,
  bool busy,
);

/// `.card.update.check` (phone-cards-check, phone-home-error, tv-home-error): one sentence and
/// only the buttons that help with it. [onReport] shows only once the door answered, since a
/// report goes to that same door.
class InternetCheckCard extends StatefulWidget {
  const InternetCheckCard({
    super.key,
    required this.check,
    required this.state,
    required this.controller,
    this.onReport,
    this.firstFocus,
  });

  final AsyncValue<ProbeChecks> check;
  final ShikooState state;
  final ShikooController controller;
  final VoidCallback? onReport;

  /// The first button's node, for the remote coming from the power button.
  final FocusNode? firstFocus;

  @override
  State<InternetCheckCard> createState() => _InternetCheckCardState();
}

class _InternetCheckCardState extends State<InternetCheckCard> {
  final _own = [FocusNode(), FocusNode(), FocusNode()];

  List<FocusNode> get _nodes => [widget.firstFocus ?? _own[0], ..._own.skip(1)];

  @override
  void dispose() {
    for (final node in _own) {
      node.dispose();
    }
    super.dispose();
  }

  List<_Action> _actions(ShikooL10n l, ProbeReading reading) {
    final InternetCheckCard(:state, :controller, :onReport) = widget;
    final service = state.service;
    final busy = state.refresh == ShikooRefresh.running;
    final report = onReport == null
        ? null
        : (l.reportSendShort, ShikooIcon.report, onReport, false);
    final support = (
      l.support,
      state.isTV ? ShikooIcon.qr : null,
      () => openLink(
        context,
        isTV: state.isTV,
        link: service?.supportLink ?? ShikooLinks.support,
        title: l.supportTitle,
        help: l.supportHelpTv,
        below: service == null ? null : serviceTitle(context, service),
      ),
      false,
    );
    return switch (reading) {
      ProbeReading.checking => const [],
      ProbeReading.ok || ProbeReading.noAbroad => [?report],
      ProbeReading.offline => [
        (
          l.probeNetSettings,
          ShikooIcon.gear,
          () => unawaited(openNetworkSettings()),
          false,
        ),
      ],
      ProbeReading.noDoor => [support],
      ProbeReading.noServer => [
        ?report,
        support,
        (
          l.refreshServers,
          ShikooIcon.refresh,
          busy ? () {} : () => unawaited(controller.refreshService()),
          busy,
        ),
      ],
    };
  }

  /// Left and right step along the buttons; past the last, the page's own rule decides.
  Object? _step(DirectionalFocusIntent intent, int count) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final forward = switch (intent.direction) {
      TraversalDirection.left => rtl,
      TraversalDirection.right => !rtl,
      _ => null,
    };
    final at = _nodes.indexOf(primaryFocus!);
    final next = forward == null || at < 0 ? -1 : at + (forward ? 1 : -1);
    if (next >= 0 && next < count) {
      _nodes[next].requestFocus();
      return null;
    }
    return Actions.maybeInvoke(context, intent);
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final state = widget.state;
    final reading = readProbes(widget.check.value, state.servers);
    final actions = _actions(l, reading);
    final (sentence, color) = switch (reading) {
      ProbeReading.checking => (l.probeChecking, t.c.textMuted),
      ProbeReading.ok => (l.probeOk, t.c.positive),
      ProbeReading.offline => (l.probeOffline, t.c.danger),
      ProbeReading.noAbroad => (l.probeNoAbroad, t.c.warning),
      ProbeReading.noDoor => (l.probeNoDoor, t.c.danger),
      ProbeReading.noServer => (l.probeNoServer, t.c.danger),
    };
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (inside) {
        if (inside) revealWithRing(context);
      },
      child: Container(
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
          spacing: Space.s3,
          children: [
            Row(
              spacing: Space.s3,
              children: [
                if (reading == ProbeReading.checking)
                  Spinner(size: t.s.icon, color: color)
                else
                  SvgIcon(
                    reading == ProbeReading.ok
                        ? ShikooIcon.check
                        : ShikooIcon.alert,
                    size: t.s.icon,
                    color: color,
                  ),
                Expanded(
                  child: Text(
                    sentence,
                    style: t.text(
                      t.s.body,
                      weight: FontWeight.w700,
                      height: Leading.tight,
                    ),
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty)
              Actions(
                actions: {
                  DirectionalFocusIntent:
                      CallbackAction<DirectionalFocusIntent>(
                        onInvoke: (intent) => _step(intent, actions.length),
                      ),
                },
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  children: [
                    for (final (i, (label, icon, onPressed, busy))
                        in actions.indexed)
                      ShikooButton(
                        label: label,
                        icon: icon,
                        focusNode: _nodes[i],
                        busy: busy,
                        onPressed: onPressed,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
