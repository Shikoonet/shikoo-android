import 'dart:async';

import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/clock.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/focus.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/report.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The states of `phone-cards-update`, the forced page's too.
enum _Step { offered, downloading, ready, failed, badFile, noSpace, clock }

_Step _stepOf(UpdateOffer offer) => switch (offer) {
  UpdateOffer(error: UpdateError.checksum) => _Step.badFile,
  UpdateOffer(error: UpdateError.network) => _Step.failed,
  UpdateOffer(error: UpdateError.noSpace) => _Step.noSpace,
  UpdateOffer(error: UpdateError.clock) => _Step.clock,
  UpdateOffer(phase: UpdatePhase.downloading) => _Step.downloading,
  UpdateOffer(phase: UpdatePhase.ready) => _Step.ready,
  _ => _Step.offered,
};

int _mb(int bytes) => (bytes / 1e6).round();

String _version(BuildContext context, UpdateOffer offer) =>
    offer.release.versionName.replaceAllMapped(
      RegExp('[0-9]'),
      (digit) => localNumber(context, int.parse(digit[0]!)),
    );

String _progress(ShikooL10n l, UpdateOffer offer) => l.updateProgress(
  offer.percent,
  (offer.received / 1e6).floor(),
  _mb(offer.release.size),
);

/// The title and help of a download that did not end well.
(String, String)? _problem(ShikooL10n l, _Step step) => switch (step) {
  _Step.failed => (l.updateDownloadFailedTitle, l.updateDownloadFailedHelp),
  _Step.badFile => (l.updateBadFileTitle, l.updateBadFileHelp),
  _Step.noSpace => (l.updateNoSpaceTitle, l.updateNoSpaceHelp),
  _Step.clock => (l.clockWrongTitle, l.clockWrongHelp),
  _ => null,
};

/// `.update-msg`: the installer did not open; the next «نصب» clears it.
Widget? _installFailed(
  ShikooTheme t,
  ShikooL10n l,
  UpdateOffer offer, {
  TextAlign align = TextAlign.start,
}) => offer.error == UpdateError.install
    ? Text(
        l.updateInstallFailed,
        textAlign: align,
        style: t.text(t.s.bodySm, color: t.c.danger),
      )
    : null;

/// `phone-update-permission`, `tv-update-permission`: only once «نصب» found Android's permission
/// missing; «ادامه» has the remote and opens Android's page, Back is «انصراف».
Future<void> _install(
  BuildContext context,
  ShikooUpdate update, {
  required bool isTV,
}) async {
  final ask = await update.install();
  if (ask == InstallAsk.nothing || !context.mounted) return;
  final go = await showShikooDialog<bool>(
    context,
    children: (context) {
      final t = ShikooTheme.of(context);
      final l = ShikooL10n.of(context);
      final paragraph = t.text(
        t.s.dialogText,
        color: t.c.textMuted,
        height: Leading.body,
      );
      return [
        Text(
          l.installPermissionTitle,
          style: t.text(t.s.title, weight: FontWeight.w700),
        ),
        Text(switch ((ask, isTV)) {
          (InstallAsk.unknownSources, true) => l.installPermissionLegacyTv,
          (InstallAsk.unknownSources, false) => l.installPermissionLegacy,
          (_, true) => l.installPermissionTv,
          _ => l.installPermissionTouch,
        }, style: paragraph),
        Text(
          (shikooDesktop ? l.updateClosesAppDesktop : l.updateClosesApp),
          style: paragraph,
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: Space.s2,
            children: [
              ShikooButton(
                label: l.cancelButton,
                onPressed: () => Navigator.pop(context, false),
              ),
              ShikooButton(
                label: l.continueButton,
                primary: true,
                autofocus: true,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ),
      ];
    },
  );
  if (go ?? false) await update.allow();
}

/// Home's card, which the menu beside the clock and Windows' message bring into view.
final homeUpdateCard = GlobalKey();

/// `.card.update`: heads the home's cards, under the power button, which keeps the first focus;
/// in Settings it takes the place of «بررسی به‌روزرسانی».
class UpdateCard extends ConsumerStatefulWidget {
  const UpdateCard({
    super.key,
    required this.offer,
    required this.isTV,
    this.focusNode,
  });

  final UpdateOffer offer;
  final bool isTV;
  final FocusNode? focusNode;

  @override
  ConsumerState<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends ConsumerState<UpdateCard> {
  /// Every state's button is one widget, so the remote stays on it when a download ends by
  /// itself (tv-home-update-ready) and when large text moves it under the text.
  final _button = GlobalKey();
  bool _pressed = false;

  /// A card the customer pressed stays in view as its state grows it (the bar, the red line).
  @override
  void didUpdateWidget(UpdateCard old) {
    super.didUpdateWidget(old);
    if (_pressed &&
        (_stepOf(old.offer) != _stepOf(widget.offer) ||
            old.offer.error != widget.offer.error)) {
      revealWithRing(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final update = ref.read(shikooUpdateProvider);
    final UpdateCard(:offer, :isTV) = widget;
    final step = _stepOf(offer);
    final problem = _problem(l, step);
    final (title, sub) =
        problem ??
        switch (step) {
          _Step.offered => (
            l.updateTitle,
            l.updateVersionSize(
              _version(context, offer),
              _mb(offer.release.size),
            ),
          ),
          _Step.downloading => (l.updateDownloading, _progress(l, offer)),
          _ => (
            l.updateReady,
            (shikooDesktop ? l.updateClosesAppDesktop : l.updateClosesApp),
          ),
        };
    final (label, primary, VoidCallback action) = switch (step) {
      _Step.offered => (l.updateGet, true, () => unawaited(update.download())),
      _Step.downloading => (
        l.cancelButton,
        false,
        () => unawaited(update.cancel()),
      ),
      _Step.ready => (
        l.updateInstall,
        true,
        () => unawaited(_install(context, update, isTV: isTV)),
      ),
      _ => (l.retry, false, () => unawaited(update.download())),
    };
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.s1,
      children: [
        Text(
          title,
          style: t.text(
            t.s.body,
            weight: FontWeight.w700,
            height: Leading.tight,
            color: problem != null ? t.c.danger : null,
          ),
        ),
        Text(
          sub,
          style: t.text(
            t.s.bodySm,
            color: t.c.textMuted,
            height: Leading.tight,
          ),
        ),
      ],
    );
    final button = ShikooButton(
      key: _button,
      label: label,
      primary: primary,
      icon: step == _Step.clock ? ShikooIcon.refresh : null,
      focusNode: widget.focusNode,
      onPressed: () {
        _pressed = true;
        action();
      },
    );
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
            if (step == _Step.clock) texts,
            LayoutBuilder(
              builder: (context, box) {
                final scaler = MediaQuery.textScalerOf(context);
                final labelWidth = textWidth(
                  context,
                  step == _Step.clock ? l.dateSettings : label,
                  t.text(t.s.body, weight: FontWeight.w700),
                );
                // `.update > .actions`: equal halves as Renew and Support, both whole when one won't fit.
                if (step == _Step.clock) {
                  const date = DateSettingsButton(primary: true);
                  return labelWidth + t.s.icon + Space.s2 + 2 * Space.s4 <=
                          (box.maxWidth - Space.s2) / 2
                      ? Row(
                          spacing: Space.s2,
                          children: [
                            const Expanded(child: date),
                            Expanded(child: button),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: Space.s2,
                          children: [date, button],
                        );
                }
                // `.update-row .t` is `flex: 1 1 12em`: under 12em beside the button, it wraps.
                final beside =
                    box.maxWidth - Space.s3 - labelWidth - 2 * Space.s4 >=
                    12 * scaler.scale(t.s.body);
                return beside
                    ? Row(
                        spacing: Space.s3,
                        children: [
                          Expanded(child: texts),
                          button,
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.s2,
                        children: [texts, button],
                      );
              },
            ),
            if (step == _Step.downloading)
              MeterBar(ratio: offer.percent / 100, usage: false),
            ?_installFailed(t, l, offer),
          ],
        ),
      ),
    );
  }
}

/// `phone-update-forced*`, `tv-update-forced*`: in place of everything while this build is below
/// the door's minimum. The connection stays as it was; Back sends the app away.
class ForcedUpdatePage extends ConsumerStatefulWidget {
  const ForcedUpdatePage({super.key});

  @override
  ConsumerState<ForcedUpdatePage> createState() => _ForcedUpdatePageState();
}

class _ForcedUpdatePageState extends ConsumerState<ForcedUpdatePage> {
  final _first = FocusNode();
  _Step? _focused;

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  /// The remote starts on the first button of each state: «دریافت», «انصراف», «نصب», «دوباره», «تنظیمات تاریخ و ساعت».
  void _focusFirst(_Step step, bool isTV) {
    if (!isTV || step == _focused) return;
    _focused = step;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _first.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final offer = ref.watch(shikooUpdateOfferProvider)!;
    final service = ref.watch(shikooStateProvider.select((s) => s.service));
    final isTV = ref.watch(shikooStateProvider.select((s) => s.isTV));
    final update = ref.read(shikooUpdateProvider);
    final step = _stepOf(offer);
    _focusFirst(step, isTV);
    final problem = _problem(l, step);
    final installFailed = _installFailed(
      t,
      l,
      offer,
      align: isTV ? TextAlign.center : TextAlign.start,
    );
    void support() => unawaited(
      openSupport(
        context,
        isTV: isTV,
        link: service?.supportLink ?? ShikooLinks.support,
        below: service == null ? null : serviceTitle(context, service),
        trigger: 'update',
      ),
    );
    Widget button(
      String label,
      VoidCallback onPressed, {
      bool primary = false,
      ShikooIcon? icon,
      bool first = false,
    }) => ShikooButton(
      label: label,
      primary: primary,
      icon: isTV ? icon : null,
      height: isTV ? null : ShikooSizes.touch,
      focusNode: first ? _first : null,
      onPressed: onPressed,
    );
    final actions = switch (step) {
      _Step.offered => [
        button(
          l.updateGet,
          () => unawaited(update.download()),
          primary: true,
          first: true,
        ),
      ],
      _Step.downloading => [
        button(l.cancelButton, () => unawaited(update.cancel()), first: true),
      ],
      _Step.ready => [
        button(
          l.updateInstall,
          () => unawaited(_install(context, update, isTV: isTV)),
          primary: true,
          first: true,
        ),
        // Android's installer can open and still not install: Support keeps that from a loop.
        button(l.support, support, icon: ShikooIcon.qr),
      ],
      _Step.clock => [
        button(
          l.dateSettings,
          () => unawaited(openDateSettings()),
          primary: true,
          icon: ShikooIcon.gear,
          first: true,
        ),
        button(
          l.retry,
          () => unawaited(update.download()),
          icon: ShikooIcon.refresh,
        ),
        button(l.support, support, icon: ShikooIcon.qr),
      ],
      _ => [
        button(
          l.retry,
          () => unawaited(update.download()),
          primary: true,
          icon: ShikooIcon.refresh,
          first: true,
        ),
        button(l.support, support, icon: ShikooIcon.qr),
      ],
    };
    final notice = problem == null
        ? null
        : MessageBox(
            icon: ShikooIcon.alert,
            danger: true,
            strong: problem.$1,
            rest: problem.$2,
          );
    final progress = step == _Step.downloading
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s2,
            children: [
              Text(
                '${l.updateDownloading} ${_progress(l, offer)}',
                textAlign: isTV ? TextAlign.center : TextAlign.start,
                style: t.text(t.s.bodySm, color: t.c.textMuted),
              ),
              MeterBar(ratio: offer.percent / 100, usage: false),
            ],
          )
        : null;
    final result = ResultBlock(
      icon: ShikooIcon.download,
      tone: ResultTone.muted,
      title: l.updateForcedTitle,
      body: [
        TextSpan(
          text: l.updateForcedBody(
            _version(context, offer),
            _mb(offer.release.size),
          ),
        ),
      ],
      more: problem != null
          ? null
          : (shikooDesktop ? l.updateClosesAppDesktop : l.updateClosesApp),
      below: isTV ? (notice ?? progress ?? installFailed) : null,
    );
    final Widget page = isTV
        ? Padding(
            padding: EdgeInsets.symmetric(
              horizontal: t.s.safeX,
              vertical: t.s.safeY,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: t.s.appbar + 2 * ShikooSizes.ring,
                  padding: const EdgeInsets.symmetric(
                    horizontal: ShikooSizes.ring,
                  ),
                  alignment: AlignmentDirectional.centerStart,
                  child: const Brand(),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        Space.s2,
                        Space.s2,
                        Space.s2,
                        Space.s4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: Space.s6,
                        children: [
                          result,
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: Space.s2,
                            children: actions,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : SafeArea(
            minimum: const EdgeInsets.only(bottom: Space.s8),
            child: FillPage(
              padding: const EdgeInsets.fromLTRB(
                Space.s6,
                Space.s2,
                Space.s6,
                0,
              ),
              top: const SizedBox.shrink(),
              middle: Center(child: result),
              bottom: [?notice, ?progress, ?installFailed, ...actions],
            ),
          );
    return Scaffold(
      backgroundColor: t.c.bg,
      body: PageFocusScope(
        child: FocusTraversalGroup(policy: PageTraversalPolicy(), child: page),
      ),
    );
  }
}
