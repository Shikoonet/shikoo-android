import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/focus.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Home, laid out after `phone-home-*` and `tv-home-*`. The service card is not built yet.
class ShikooHome extends ConsumerWidget {
  const ShikooHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shikooStateProvider);
    final controller = ref.watch(shikooControllerProvider);
    final t = ShikooTheme.of(context);
    final power = _PowerZone(state: state, controller: controller);
    final servers = _ServersCard(state: state, controller: controller);
    return Scaffold(
      backgroundColor: t.c.bg,
      body: PageFocusScope(
        child: FocusTraversalGroup(
          policy: PageTraversalPolicy(),
          child: state.isTV
              ? _TvLayout(power: power, servers: servers)
              : _PhoneLayout(power: power, servers: servers),
        ),
      ),
    );
  }
}

class _TvLayout extends StatelessWidget {
  const _TvLayout({required this.power, required this.servers});

  final Widget power;
  final Widget servers;

  @override
  Widget build(BuildContext context) {
    final s = ShikooTheme.of(context).s;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: s.safeX, vertical: s.safeY),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: s.appbar,
            child: const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Brand(),
            ),
          ),
          const SizedBox(height: Space.s3),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: s.pane, child: servers),
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

class _PhoneLayout extends StatelessWidget {
  const _PhoneLayout({required this.power, required this.servers});

  final Widget power;
  final Widget servers;

  @override
  Widget build(BuildContext context) {
    final s = ShikooTheme.of(context).s;
    return SafeArea(
      child: Column(
        children: [
          Container(
            height: s.appbar,
            padding: EdgeInsets.symmetric(horizontal: s.safeX),
            alignment: AlignmentDirectional.centerStart,
            child: const Brand(),
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
                  servers,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PowerZone extends StatelessWidget {
  const _PowerZone({required this.state, required this.controller});

  final ShikooState state;
  final ShikooController controller;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final selected = state.selectedServer;
    final message = switch (state.lastError) {
      ShikooError.connectTimeout => l.errorConnect(
        selected?.name ?? '',
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
          const SizedBox(height: Space.s4),
          NowPill(server: selected),
        ],
        if (message != null) ...[
          const SizedBox(height: Space.s4),
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

class _ServersCard extends StatelessWidget {
  const _ServersCard({required this.state, required this.controller});

  final ShikooState state;
  final ShikooController controller;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final name = state.serviceName;
    final rows = [
      for (final server in state.servers)
        Padding(
          padding: EdgeInsets.only(bottom: t.s.rowGap),
          child: ServerRow(
            server: server,
            selected: server.name == state.selected,
            onPressed: () => unawaited(controller.selectServer(server.name)),
          ),
        ),
    ];
    final empty = Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: Text(
        name == null ? l.noService : l.loadingServers,
        style: t.text(t.s.body, color: t.c.textMuted),
      ),
    );
    final list = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s2,
        vertical: Space.s2,
      ),
      child: Column(children: rows.isEmpty ? [empty] : rows),
    );
    return Container(
      decoration: ShapeDecoration(
        color: t.c.surface,
        shadows: t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (name != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.s4,
                Space.s4,
                Space.s4,
                0,
              ),
              child: nameText(
                context,
                name,
                t.text(t.s.title, weight: FontWeight.w700, height: 1.6),
              ),
            ),
          if (state.isTV)
            Expanded(child: SingleChildScrollView(child: list))
          else
            list,
        ],
      ),
    );
  }
}
