import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/focus.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

void openSettings(BuildContext context) => unawaited(
  Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const ShikooSettings()),
  ),
);

/// Frames `tv-settings-pre-login` and `phone-settings-pasted`: on the TV two columns, so
/// nothing scrolls.
class ShikooSettings extends ConsumerWidget {
  const ShikooSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ShikooL10n.of(context);
    final look = ref.watch(shikooLookProvider);
    final setLook = ref.read(shikooLookProvider.notifier);
    final isTV = ref.watch(shikooStateProvider.select((state) => state.isTV));
    final groups = [
      _Group(
        title: l.appearance,
        child: Segmented(
          autofocus: true,
          selected: look.theme,
          options: {
            ThemeMode.light: l.themeLight,
            ThemeMode.dark: l.themeDark,
            ThemeMode.system: l.themeAuto,
          },
          onSelect: (theme) => unawaited(setLook.setTheme(theme)),
        ),
      ),
      _Group(
        title: l.language,
        child: Segmented(
          selected: look.language,
          options: {'fa': l.languageFa, 'en': l.languageEn},
          onSelect: (language) => unawaited(setLook.setLanguage(language)),
        ),
      ),
      _Group(
        title: l.account,
        child: _Card(
          rows: [
            _Row(
              icon: ShikooIcon.logout,
              danger: true,
              title: l.logout,
              subtitle: isTV ? l.logoutHelpTv : l.logoutHelpTouch,
              onPressed: () => unawaited(_logOut(context, ref, isTV)),
            ),
          ],
        ),
      ),
      _Group(
        title: l.appSection,
        child: _Card(
          rows: [
            _Row(
              title: l.version,
              value: _version(context, ref.watch(shikooVersionProvider)),
            ),
            _Row(
              title: l.about,
              subtitle: l.aboutSummary,
              forward: true,
              onPressed: () => unawaited(
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const ShikooAbout()),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
    return _Page(
      title: l.settings,
      isTV: isTV,
      child: isTV
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.s10,
              children: [
                for (final first in [0, 1])
                  Expanded(
                    child: _Column(
                      children: [
                        for (var i = first; i < groups.length; i += 2)
                          groups[i],
                      ],
                    ),
                  ),
              ],
            )
          : _Column(children: groups),
    );
  }

  /// Until sign-in with Telegram exists, leaving only forgets this device's services.
  static Future<void> _logOut(
    BuildContext context,
    WidgetRef ref,
    bool isTV,
  ) async {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final sure = await showShikooDialog<bool>(
      context,
      children: [
        Text(
          isTV ? l.logoutTitleTv : l.logoutTitleTouch,
          style: t.text(t.s.title, weight: FontWeight.w700),
        ),
        Text(
          isTV ? l.logoutBodyTv : l.logoutBodyTouch,
          style: t.text(
            t.s.dialogText,
            color: t.c.textMuted,
            height: Leading.body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: Space.s2,
            children: [
              ShikooButton(
                label: l.cancel,
                autofocus: true,
                onPressed: () => Navigator.pop(context, false),
              ),
              ShikooButton(
                label: l.removeButton,
                danger: true,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
      ],
    );
    if (sure != true || !context.mounted) return;
    await ref.read(shikooControllerProvider).forgetServices();
    if (context.mounted) Navigator.popUntil(context, (route) => route.isFirst);
  }
}

/// Frame `tv-about`: the licence, the credits and where the source comes from.
class ShikooAbout extends ConsumerWidget {
  const ShikooAbout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final body = t.text(t.s.body, height: Leading.body);
    final isTV = ref.watch(shikooStateProvider.select((state) => state.isTV));
    return _Page(
      title: l.about,
      isTV: isTV,
      child: Center(
        child: SizedBox(
          width: isTV ? t.s.pane : double.infinity,
          child: _Card(
            rows: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s6,
                  vertical: Space.s4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.s3,
                  children: [
                    Text(
                      '${l.appTitle} ${_version(context, ref.watch(shikooVersionProvider))}',
                      style: t.text(t.s.title, weight: FontWeight.w700),
                    ),
                    Text(l.aboutFree, style: body),
                    Text(l.aboutBasedOn, style: body),
                    Text(l.aboutSource, style: body),
                    Text(
                      l.aboutLicense,
                      style: body.copyWith(color: t.c.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _version(BuildContext context, String version) => version
    .split('.')
    .map((part) {
      final number = int.tryParse(part);
      return number == null ? part : localNumber(context, number);
    })
    .join('.');

/// `.tv-top` with `.tv-title` and `.tv-hint` over the page; the phone has no hint.
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.isTV, required this.child});

  final String title;
  final bool isTV;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    return Scaffold(
      backgroundColor: t.c.bg,
      body: SafeArea(
        child: PageFocusScope(
          child: FocusTraversalGroup(
            policy: PageTraversalPolicy(),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: s.safeX,
                vertical: s.safeY,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: s.appbar,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          style: t.text(s.title, weight: FontWeight.w700),
                        ),
                        if (isTV)
                          Text(
                            ShikooL10n.of(context).backHintTv,
                            style: t.text(s.bodySm, color: t.c.textMuted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.s3),
                  Expanded(
                    // Only for large text; the padding keeps the last focus ring in view.
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: Space.s2),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame's remote order: up and down stay in a column, left and right cross to the other.
class _Column extends StatelessWidget {
  const _Column({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FocusScope(
    child: FocusTraversalGroup(
      policy: _ColumnPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.s6,
        children: children,
      ),
    ),
  );
}

class _ColumnPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    currentNode.nearestScope!.directionalTraversalEdgeBehavior =
        switch (direction) {
          TraversalDirection.up ||
          TraversalDirection.down => TraversalEdgeBehavior.stop,
          _ => TraversalEdgeBehavior.parentScope,
        };
    return super.inDirection(currentNode, direction);
  }
}

/// `.group-title` over its control.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s2, 0, Space.s2, Space.s2),
          child: Text(
            title,
            style: t.text(
              t.s.bodySm,
              weight: FontWeight.w700,
              color: t.c.textMuted,
              height: Leading.body,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// `.segmented`: one choice of a few, the chosen one raised.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.autofocus = false,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelect;

  /// Lands the remote on the chosen option.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.sm),
    );
    return Container(
      padding: const EdgeInsets.all(Space.s1),
      decoration: ShapeDecoration(
        color: t.c.surfaceSunken,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      child: Row(
        spacing: Space.s1,
        children: [
          for (final MapEntry(key: value, value: label) in options.entries)
            Expanded(
              child: Pressable(
                autofocus: autofocus && value == selected,
                shape: shape,
                onPressed: () => onSelect(value),
                builder: (context, focused) {
                  final chosen = value == selected;
                  return Semantics(
                    selected: chosen,
                    button: true,
                    child: Container(
                      height: t.s.button,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: focused
                            ? t.c.focusBg
                            : (chosen ? t.c.surface : null),
                        shadows: focused
                            ? t.c.raisedShadow
                            : (chosen ? t.c.cardShadow : null),
                        shape: shape,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        style: t.text(
                          t.s.body,
                          weight: chosen ? FontWeight.w700 : FontWeight.w500,
                          color: chosen ? t.c.text : t.c.textMuted,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// `.card` holding `.row`s, a hairline between each two.
class _Card extends StatelessWidget {
  const _Card({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    return DecoratedBox(
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
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Container(height: 1, color: t.c.border),
            row,
          ],
        ],
      ),
    );
  }
}

/// `.row`: an icon, a title over a line of help, then a value or a forward chevron.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.forward = false,
    this.danger = false,
    this.onPressed,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final ShikooIcon? icon;
  final bool forward;
  final bool danger;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.md),
    );
    final ink = danger ? t.c.danger : t.c.text;
    // The icons are drawn for Persian; English mirrors them, as `.flip-ltr`.
    final ltr = Directionality.of(context) == TextDirection.ltr;
    final icon = this.icon;
    final subtitle = this.subtitle;
    final value = this.value;
    Widget row(bool focused) => Container(
      constraints: BoxConstraints(minHeight: s.row),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
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
          if (icon != null)
            Transform.flip(
              flipX: ltr,
              child: SvgIcon(
                icon,
                size: s.icon,
                color: danger ? ink : t.c.textMuted,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.text(s.body, color: ink)),
                if (subtitle != null)
                  Text(subtitle, style: t.text(s.bodySm, color: t.c.textMuted)),
              ],
            ),
          ),
          if (value != null)
            Text(
              value,
              style: t.text(s.body, color: t.c.textMuted, height: Leading.body),
            ),
          if (forward)
            Transform.flip(
              flipX: ltr,
              child: SvgIcon(
                ShikooIcon.chevronFwd,
                size: s.icon,
                color: t.c.textMuted,
              ),
            ),
        ],
      ),
    );
    final onPressed = this.onPressed;
    if (onPressed == null) return row(false);
    return Pressable(
      shape: shape,
      onPressed: onPressed,
      builder: (context, focused) => row(focused),
    );
  }
}
