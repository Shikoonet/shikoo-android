import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/refresh_menu.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

String protocolLabel(ShikooL10n l, ShikooProtocol protocol) =>
    switch (protocol) {
      ShikooProtocol.vless => l.protocolVless,
      ShikooProtocol.wireguard => l.protocolWireguard,
      ShikooProtocol.openvpn => l.protocolOpenvpn,
      ShikooProtocol.ssh => l.protocolSsh,
      ShikooProtocol.other => '',
    };

String coreLabel(ShikooL10n l, ShikooCore core) => switch (core) {
  ShikooCore.mihomo => l.coreMihomo,
  ShikooCore.xray => l.coreXray,
  ShikooCore.singBox => l.coreSingBox,
  ShikooCore.wireguard => l.coreWireguard,
  ShikooCore.openvpn => l.coreOpenvpn,
};

/// The mockup's order in every list: the two engines that own the tunnel before sing-box.
const _order = [
  ShikooCore.mihomo,
  ShikooCore.xray,
  ShikooCore.wireguard,
  ShikooCore.openvpn,
  ShikooCore.singBox,
];

/// `.via`: the core a server really connects with, when it is not the one chosen for its kind.
String? viaLabel(ShikooL10n l, ShikooServer server, List<ShikooCoreRow> rows) {
  final chosen =
      rows.firstWhereOrNull((row) => row.protocol == server.protocol)?.chosen ??
      ShikooCore.mihomo;
  return server.core == chosen ? null : l.viaCore(coreLabel(l, server.core));
}

/// A core change's sentences, in the server switch's bar; a failure is only «وصل نشد».
List<String> coreNews(ShikooL10n l, ShikooCoreSwitch shift) =>
    switch (shift.stage) {
      ShikooSwitchStage.moving => [l.coreSwitching(coreLabel(l, shift.to))],
      ShikooSwitchStage.done => [l.coreSwitched(coreLabel(l, shift.to))],
      ShikooSwitchStage.failed => [l.powerFailed],
    };

/// Option «الف»: [row]'s cores in a bottom sheet on the phone, a dialog on the TV, and a menu
/// under the row on a computer, whose [context] is the row. A pick closes it and takes effect.
Future<void> pickCore(
  BuildContext context,
  WidgetRef ref,
  ShikooCoreRow row,
) async {
  final controller = ref.read(shikooControllerProvider);
  final ShikooCore? picked;
  if (ref.read(shikooStateProvider).isTV) {
    picked = await showShikooDialog<ShikooCore>(
      context,
      children: (dialog) => [
        ..._head(dialog, row, big: true),
        _CoreList(row: row, menu: false),
      ],
    );
  } else if (shikooDesktop) {
    final overlay =
        Navigator.of(
              context,
              rootNavigator: true,
            ).overlay!.context.findRenderObject()!
            as RenderBox;
    final box = context.findRenderObject()! as RenderBox;
    // The click's focus scrolls the row clear of the edge first (revealWithRing): one frame
    // scrolls, the next lays the row out where it now is.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted || !box.attached) return;
    picked = await showMenuBelow<ShikooCore>(
      context,
      anchor: MatrixUtils.transformRect(
        box.getTransformTo(overlay),
        Offset.zero & box.size,
      ),
      label: _title(context, row),
      isTV: false,
      width: ShikooSizes.coreMenu,
      child: _CoreList(row: row, menu: true),
    );
  } else {
    picked = await _sheet(
      context,
      (sheet) => [
        ..._head(sheet, row, big: false),
        _CoreList(row: row, menu: false),
      ],
    );
  }
  if (picked != null && picked != row.chosen) {
    await controller.setCore(row.protocol, picked);
  }
}

String _title(BuildContext context, ShikooCoreRow row) {
  final l = ShikooL10n.of(context);
  return l.corePickTitle(protocolLabel(l, row.protocol));
}

/// The sheet's and the dialog's title and lead; the menu has them as its head and foot.
List<Widget> _head(
  BuildContext context,
  ShikooCoreRow row, {
  required bool big,
}) {
  final t = ShikooTheme.of(context);
  final l = ShikooL10n.of(context);
  return [
    Text(
      _title(context, row),
      style: t.text(t.s.title, weight: FontWeight.w700),
    ),
    Text(
      '${l.corePickForAll(protocolLabel(l, row.protocol))} ${l.corePickAgain}',
      style: t.text(
        big ? t.s.dialogText : t.s.bodySm,
        color: t.c.textMuted,
        height: Leading.body,
      ),
    ),
  ];
}

/// `.scrim.is-sheet` and `.bottom-sheet` with its `.grab`; Back or a tap outside closes it.
Future<ShikooCore?> _sheet(
  BuildContext context,
  List<Widget> Function(BuildContext sheet) children,
) {
  final t = ShikooTheme.of(context);
  return showModalBottomSheet<ShikooCore>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    elevation: 0,
    backgroundColor: t.c.surface,
    barrierColor: t.c.scrim,
    shape: const RoundedSuperellipseBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
    ),
    builder: (sheet) {
      final t = ShikooTheme.of(sheet);
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Space.s6,
          Space.s3,
          Space.s6,
          Space.s6 + MediaQuery.paddingOf(sheet).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s3,
          children: [
            Center(
              child: Container(
                width: Space.s8,
                height: Space.s1,
                decoration: ShapeDecoration(
                  color: t.c.outline,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            ...children(sheet),
          ],
        ),
      );
    },
  );
}

/// `.pick-list`: every core that knows [row]'s kind. One this build lacks is greyed with
/// «به‌زودی»; in Windows' Proxy mode, so is one that owns the tunnel, the pick kept.
class _CoreList extends ConsumerWidget {
  const _CoreList({required this.row, required this.menu});

  final ShikooCoreRow row;

  /// The computer's menu: its own head and foot, and no hairlines.
  final bool menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final specs = ref.watch(shikooCoreSpecsProvider);
    final proxy = shikooDesktop && !ref.watch(shikooModeProvider).tun;
    bool tunnelOnly(ShikooCore core) =>
        proxy && specs[core]?.shape == ShikooShape.ownsTunnel;
    final options = row.options.sortedBy<num>((o) => _order.indexOf(o.core));
    final protocol = protocolLabel(l, row.protocol);
    final items = [
      for (final (:core, :ready) in options)
        _CoreOption(
          label: coreLabel(l, core),
          help: switch (core) {
            _ when tunnelOnly(core) => l.coreTunnelOnly(l.modeTunnel),
            _ when core == row.defaultCore => l.coreDefault,
            ShikooCore.singBox when row.protocol == ShikooProtocol.vless =>
              l.coreSingBoxVless,
            ShikooCore.wireguard => l.coreWireguardHelp,
            ShikooCore.openvpn => l.coreOpenvpnHelp,
            _ => null,
          },
          chosen: core == row.chosen,
          soon: !ready,
          menu: menu,
          onPressed: ready && !tunnelOnly(core)
              ? () => Navigator.pop(context, core)
              : null,
        ),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (menu)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s3,
                Space.s2,
                Space.s3,
                Space.s1,
              ),
              child: Text(
                _title(context, row),
                style: t.text(
                  t.s.bodySm,
                  weight: FontWeight.w700,
                  color: t.c.textMuted,
                ),
              ),
            ),
          for (final (i, item) in items.indexed) ...[
            if (i > 0 && !menu) Container(height: 1, color: t.c.border),
            item,
          ],
          if (menu) ...[
            Container(height: 1, color: t.c.border),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s3,
                vertical: Space.s2,
              ),
              child: Text(
                tunnelOnly(row.chosen)
                    ? l.coreProxyFallback(
                        l.modeProxy,
                        protocol,
                        l.modeTunnel,
                        coreLabel(l, row.chosen),
                      )
                    : options.any((o) => tunnelOnly(o.core))
                    ? '${l.coreProxyNow(l.modeProxy)} ${l.corePickForAll(protocol)}'
                    : '${l.corePickForAll(protocol)} ${l.corePickAgain}',
                style: t.text(t.s.caption, color: t.c.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.pick-list .row[role=radio]`: the radio, the core and its line, and «به‌زودی»; greyed and
/// inert with no [onPressed]. The remote starts on the chosen one.
class _CoreOption extends StatelessWidget {
  const _CoreOption({
    required this.label,
    required this.help,
    required this.chosen,
    required this.soon,
    required this.menu,
    required this.onPressed,
  });

  final String label;
  final String? help;
  final bool chosen;
  final bool soon;
  final bool menu;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    final on = onPressed != null;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(menu ? Radii.sm : Radii.md),
    );
    final ink = !on ? t.c.iconDisabled : (chosen ? t.c.primary : t.c.outline);
    final help = this.help;
    Widget face(bool focused) => Container(
      constraints: BoxConstraints(minHeight: menu ? s.buttonSm : s.row),
      padding: menu
          ? const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2)
          : const EdgeInsets.symmetric(
              horizontal: Space.s2,
              vertical: Space.s3,
            ),
      decoration: ShapeDecoration(
        color: focused ? t.c.focusBg : null,
        shadows: focused ? t.c.raisedShadow : null,
        shape: shape,
      ),
      child: Row(
        spacing: Space.s3,
        children: [
          Container(
            width: ShikooSizes.radio,
            height: ShikooSizes.radio,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              shape: CircleBorder(
                side: BorderSide(color: ink, width: ShikooSizes.borderRadio),
              ),
            ),
            child: chosen
                ? Container(
                    width: ShikooSizes.radio / 2,
                    height: ShikooSizes.radio / 2,
                    decoration: BoxDecoration(
                      color: ink,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: t.text(s.body, color: on ? t.c.text : t.c.textMuted),
                ),
                if (help != null)
                  Text(help, style: t.text(s.bodySm, color: t.c.textMuted)),
              ],
            ),
          ),
          if (soon)
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
                ShikooL10n.of(context).coreSoon,
                style: t.text(
                  s.caption,
                  weight: FontWeight.w700,
                  color: t.c.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
    Widget semantics(Widget child) => Semantics(
      inMutuallyExclusiveGroup: true,
      checked: chosen,
      enabled: on,
      button: true,
      child: child,
    );
    if (!on) return semantics(face(false));
    return Pressable(
      shape: shape,
      autofocus: chosen,
      onPressed: onPressed,
      builder: (context, focused) => semantics(face(focused)),
    );
  }
}
