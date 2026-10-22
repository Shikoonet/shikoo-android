import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// Option «الف» of sub-refresh-modes: the update as today, and beside it «▾» with the two ways,
/// in one `.split` on the phone, two `.btn-outline` on the TV. A long press or a right-click on
/// the update opens the same menu. [server] is the name the second way goes through.
class RefreshControls extends StatefulWidget {
  const RefreshControls({
    super.key,
    required this.isTV,
    required this.busy,
    required this.enabled,
    required this.connected,
    required this.onRefresh,
    required this.onWay,
    this.server = '',
    this.refreshNode,
    this.caretNode,
    this.card,
  });

  final bool isTV;
  final bool busy;

  /// False while the servers are pinged: both grey, as the update was before.
  final bool enabled;
  final bool connected;
  final VoidCallback onRefresh;
  final void Function(ShikooRoute way) onWay;
  final String server;
  final FocusNode? refreshNode;
  final FocusNode? caretNode;

  /// The card it sits in: the menu reaches from «▾» to the card's far edge, no further, when it fits.
  final BuildContext? card;

  @override
  State<RefreshControls> createState() => _RefreshControlsState();
}

class _RefreshControlsState extends State<RefreshControls> {
  final _caret = GlobalKey();
  bool _open = false;

  Future<void> _menu() async {
    final box = _caret.currentContext?.findRenderObject();
    final overlay = Navigator.of(
      context,
      rootNavigator: true,
    ).overlay?.context.findRenderObject();
    if (_open || widget.busy || box is! RenderBox || overlay is! RenderBox) {
      return;
    }
    // In the menu's own layer: the TV canvas scales everything under it.
    Rect place(RenderBox of) => MatrixUtils.transformRect(
      of.getTransformTo(overlay),
      Offset.zero & of.size,
    );
    final card = widget.card?.findRenderObject();
    setState(() => _open = true);
    final way = await showRefreshMenu(
      context,
      anchor: place(box),
      within: card is RenderBox ? place(card) : null,
      connected: widget.connected,
      server: widget.server,
      isTV: widget.isTV,
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (way != null) widget.onWay(way);
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final busy = widget.busy;
    final onRefresh = !widget.enabled
        ? null
        : (busy ? () {} : widget.onRefresh);
    final onCaret = !widget.enabled ? null : () => unawaited(_menu());
    Widget menuGestures(Widget child) => GestureDetector(
      onLongPress: onCaret,
      onSecondaryTap: onCaret,
      child: child,
    );
    if (widget.isTV) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.s2,
        children: [
          ShikooButton(
            label: l.refresh,
            icon: ShikooIcon.refresh,
            busy: busy,
            focusNode: widget.refreshNode,
            onPressed: onRefresh,
          ),
          Semantics(
            label: l.refreshWays,
            child: ShikooButton(
              key: _caret,
              label: '',
              icon: ShikooIcon.chevronDown,
              selected: _open,
              focusNode: widget.caretNode,
              onPressed: onCaret,
            ),
          ),
        ],
      );
    }
    final height = t.s.button;
    return Container(
      height: height,
      decoration: ShapeDecoration(
        color: t.c.surfaceSunken,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          menuGestures(
            ShikooIconButton(
              icon: ShikooIcon.refresh,
              label: l.refreshServers,
              color: t.c.textMuted,
              busy: busy,
              height: height,
              onPressed: onRefresh,
            ),
          ),
          Container(
            width: t.s.borderControl,
            height: height - 2 * Space.s3,
            color: t.c.border,
          ),
          DecoratedBox(
            key: _caret,
            decoration: ShapeDecoration(
              color: _open ? t.c.border : null,
              shape: const StadiumBorder(),
            ),
            child: ShikooIconButton(
              icon: ShikooIcon.chevronDown,
              label: l.refreshWays,
              color: _open ? t.c.text : t.c.textMuted,
              height: height,
              iconSize: t.s.iconSm,
              onPressed: onCaret,
            ),
          ),
        ],
      ),
    );
  }
}

Future<ShikooRoute?> showRefreshMenu(
  BuildContext context, {
  required Rect anchor,
  Rect? within,
  required bool connected,
  required String server,
  required bool isTV,
}) => showMenuBelow<ShikooRoute>(
  context,
  anchor: anchor,
  within: within,
  label: ShikooL10n.of(context).refreshWays,
  isTV: isTV,
  child: _Menu(connected: connected, server: server, isTV: isTV),
);

/// `.rmenu` under [anchor], its end edge on the anchor's; Back, Esc or a tap outside closes it,
/// and the remote returns to what opened it. [anchor] and [within] are in the overlay's space.
/// Without a [width] the menu is as wide as its content, at least 248.
Future<T?> showMenuBelow<T>(
  BuildContext context, {
  required Rect anchor,
  Rect? within,
  required String label,
  required bool isTV,
  double? width,
  required Widget child,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: label,
  barrierColor: Colors.transparent,
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => CustomSingleChildLayout(
    delegate: _Below(anchor, within, Directionality.of(context)),
    child: ConstrainedBox(
      constraints: width == null
          ? const BoxConstraints(minWidth: _menuMinWidth)
          : BoxConstraints.tightFor(width: width),
      child: IntrinsicWidth(
        child: Builder(
          builder: (context) {
            final t = ShikooTheme.of(context);
            return Container(
              padding: EdgeInsets.all(isTV ? Space.s2 : Space.s1),
              decoration: ShapeDecoration(
                color: t.c.surface,
                shadows: t.c.raisedShadow,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(
                    shikooDesktop ? Radii.sm : Radii.md,
                  ),
                  side: BorderSide(color: t.c.border),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Semantics(
                  scopesRoute: true,
                  explicitChildNodes: true,
                  label: label,
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    ),
  ),
);

const _menuMinWidth = 248.0;

class _Below extends SingleChildLayoutDelegate {
  _Below(this.anchor, this.within, this.direction);

  final Rect anchor;
  final Rect? within;
  final TextDirection direction;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final room = direction == TextDirection.rtl
        ? math.min(within?.right ?? width, width - Space.s2) - anchor.left
        : anchor.right - math.max(within?.left ?? 0, Space.s2);
    // A card too narrow for the menu beside «▾»: the mockup's width, the clamp keeps it on screen.
    final most = room < _menuMinWidth ? width : room;
    return BoxConstraints(
      maxWidth: math.max(0.0, math.min(most, width - 2 * Space.s4)),
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = direction == TextDirection.rtl
        ? anchor.left
        : anchor.right - child.width;
    final below = anchor.bottom + Space.s1;
    final y = below + child.height <= size.height
        ? below
        : anchor.top - Space.s1 - child.height;
    return Offset(
      x.clamp(Space.s2, size.width - child.width - Space.s2),
      math.max(Space.s2, math.min(y, size.height - child.height - Space.s2)),
    );
  }

  @override
  bool shouldRelayout(_Below old) =>
      old.anchor != anchor ||
      old.within != within ||
      old.direction != direction;
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.connected,
    required this.server,
    required this.isTV,
  });

  final bool connected;
  final String server;
  final bool isTV;

  @override
  Widget build(BuildContext context) {
    final l = ShikooL10n.of(context);
    void choose(ShikooRoute way) => Navigator.of(context).pop(way);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: isTV ? Space.s1 : 0,
      children: [
        _Item(
          icon: ShikooIcon.wifi,
          title: l.refreshDirect,
          hint: shikooDesktop
              ? l.refreshDirectHintDesktop
              : l.refreshDirectHint,
          isTV: isTV,
          autofocus:
              !shikooDesktop ||
              FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional,
          onPressed: () => choose(ShikooRoute.direct),
        ),
        _Item(
          icon: ShikooIcon.shield,
          title: l.refreshViaServer,
          hint: connected
              ? l.refreshViaServerHint(server)
              : l.refreshConnectFirst,
          isTV: isTV,
          onPressed: connected ? () => choose(ShikooRoute.server) : null,
        ),
      ],
    );
  }
}

/// `.rm-item`: an icon, the way and its line; greyed and inert with no [onPressed].
class _Item extends StatefulWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.hint,
    required this.isTV,
    required this.onPressed,
    this.autofocus = false,
  });

  final ShikooIcon icon;
  final String title;
  final String hint;
  final bool isTV;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final onPressed = widget.onPressed;
    final on = onPressed != null;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.sm),
    );
    Widget face(BuildContext context, bool focused) => Container(
      constraints: BoxConstraints(
        minHeight: widget.isTV
            ? t.s.row + Space.s3
            : (shikooDesktop ? t.s.button : ShikooSizes.touch),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: widget.isTV ? Space.s4 : Space.s3,
        vertical: shikooDesktop ? Space.s1 : Space.s2,
      ),
      decoration: ShapeDecoration(
        color: focused
            ? t.c.focusBg
            : (_hover && on && !shikooDesktop ? t.c.selectedBg : null),
        shape: shape,
      ),
      child: Row(
        spacing: Space.s3,
        children: [
          SvgIcon(
            widget.icon,
            size: t.s.icon,
            color: on ? t.c.textMuted : t.c.iconDisabled,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: t.text(
                    t.s.body,
                    weight: on ? FontWeight.w500 : FontWeight.w400,
                    color: on ? t.c.text : t.c.textMuted,
                    height: Leading.tight,
                  ),
                ),
                Text(
                  widget.hint,
                  style: t.text(
                    t.s.bodySm,
                    color: t.c.textMuted,
                    height: Leading.tight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!on) {
      return Semantics(
        button: true,
        enabled: false,
        child: face(context, false),
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        shape: shape,
        autofocus: widget.autofocus,
        onPressed: onPressed,
        builder: (context, focused) =>
            Semantics(button: true, child: face(context, focused)),
      ),
    );
  }
}
