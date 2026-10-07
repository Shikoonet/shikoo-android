import 'dart:async';
import 'dart:typed_data';

import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ReportShots = ({Uint8List? app, Uint8List? screen});

/// What the app drew and what the window showed, at the tap, before anything opens over it.
Future<ReportShots> takeShots(BuildContext context) async {
  final diag = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(shikooDiagProvider);
  Future<Uint8List?> drawn() async {
    try {
      return await diag.captureApp();
    } catch (_) {
      return null;
    }
  }

  final (app, screen) = await (drawn(), diag.captureScreen()).wait;
  return (app: app, screen: screen);
}

Future<void> openReport(
  BuildContext context,
  String trigger, [
  ReportShots? shots,
]) async {
  final taken = shots ?? await takeShots(context);
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ReportPage(trigger: trigger, shots: taken),
      settings: const RouteSettings(name: 'report'),
    ),
  );
}

/// «پشتیبانی»: chat or report, as a sheet on a phone and the QR dialog on a TV. Without a
/// [trigger], chat only: a sent report's page, or a page showing a live sign-in code.
Future<void> openSupport(
  BuildContext context, {
  required bool isTV,
  String link = ShikooLinks.support,
  String? below,
  String? trigger,
}) async {
  final l = ShikooL10n.of(context);
  final shots = trigger == null ? null : await takeShots(context);
  if (!context.mounted) return;
  void report(BuildContext dialog) {
    Navigator.pop(dialog);
    unawaited(openReport(context, trigger!, shots));
  }

  if (isTV || trigger == null) {
    openLink(
      context,
      isTV: isTV,
      link: link,
      title: l.supportTitle,
      help: l.supportHelpTv,
      below: below,
      beside: trigger == null
          ? null
          : (dialog) => ShikooButton(
              label: ShikooL10n.of(dialog).reportSendToSupport,
              icon: ShikooIcon.report,
              onPressed: () => report(dialog),
            ),
    );
    return;
  }
  await showShikooDialog<void>(
    context,
    children: (dialog) {
      final t = ShikooTheme.of(dialog);
      final l = ShikooL10n.of(dialog);
      return [
        Text(l.support, style: t.text(t.s.title, weight: FontWeight.w700)),
        Text(
          l.reportSupportSheetBody,
          style: t.text(
            t.s.dialogText,
            color: t.c.textMuted,
            height: Leading.body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s3, bottom: Space.s2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s3,
            children: [
              ShikooButton(
                label: l.reportChatTelegram,
                icon: ShikooIcon.plane,
                primary: true,
                onPressed: () {
                  Navigator.pop(dialog);
                  unawaited(
                    launchUrl(
                      Uri.parse(link),
                      mode: LaunchMode.externalApplication,
                    ),
                  );
                },
              ),
              ShikooButton(
                label: l.reportSendToSupport,
                icon: ShikooIcon.report,
                onPressed: () => report(dialog),
              ),
              ShikooButton(
                label: l.cancelButton,
                flat: true,
                onPressed: () => Navigator.pop(dialog),
              ),
            ],
          ),
        ),
      ];
    },
  );
}

/// Home's `.card.update` after a crash, an ANR or a Go panic, once per crash.
class CrashCard extends ConsumerWidget {
  const CrashCard({super.key, required this.send, required this.no});

  final FocusNode send;
  final FocusNode no;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final diag = ref.read(shikooDiagProvider);
    void forget(FocusNode node) {
      // Down first: the button goes with the card, and the remote would land nowhere.
      if (node.hasFocus) node.focusInDirection(TraversalDirection.down);
      unawaited(diag.crashAsked());
    }

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
        spacing: Space.s3,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.s1,
            children: [
              Text(
                l.reportCrashTitle,
                style: t.text(t.s.body, weight: FontWeight.w700),
              ),
              Text(
                l.reportCrashAsk,
                style: t.text(t.s.bodySm, color: t.c.textMuted),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: Space.s2,
            children: [
              ShikooButton(
                label: l.reportCrashNo,
                focusNode: no,
                onPressed: () => forget(no),
              ),
              ShikooButton(
                label: l.reportCrashYes,
                primary: true,
                focusNode: send,
                onPressed: () async {
                  final shots = await takeShots(context);
                  if (!context.mounted) return;
                  forget(send);
                  unawaited(openReport(context, 'crash', shots));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _Phase { preview, sending, sent, failed }

/// The report's preview, its sending and its result, all on one page.
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key, required this.trigger, required this.shots});

  final String trigger;
  final ReportShots shots;

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  /// One per phase: a node handed on to the next phase's button keeps its focus but not its ring.
  final _firsts = {for (final phase in _Phase.values) phase: FocusNode()};
  var _phase = _Phase.preview;
  var _images = true;
  Map<String, Object?>? _report;
  ({String code, bool linked})? _sent;
  Object? _error;
  int _attempt = 0;
  _Phase? _focused;

  @override
  void dispose() {
    for (final node in _firsts.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// «دوباره» sends the very report the first press built, pictures and all.
  Future<void> _send() async {
    final attempt = ++_attempt;
    setState(() => _phase = _Phase.sending);
    final diag = ref.read(shikooDiagProvider);
    try {
      final report = _report ??= await diag.report(
        trigger: widget.trigger,
        about: await diag.about(),
        appImage: widget.shots.app,
        screenImage: widget.shots.screen,
        images: _images,
      );
      final sent = await diag.send(report);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _sent = sent;
        _phase = _Phase.sent;
      });
    } catch (error) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _error = error;
        _phase = _Phase.failed;
      });
    }
  }

  // ponytail: «انصراف» leaves the page; a body already on the wire may still reach the door.
  void _leave() => Navigator.maybePop(context);

  void _support(bool isTV) => unawaited(
    openSupport(
      context,
      isTV: isTV,
      link:
          ref.read(shikooStateProvider).service?.supportLink ??
          ShikooLinks.support,
    ),
  );

  void _focusFirst(bool isTV) {
    if (!isTV || _phase == _focused) return;
    _focused = _phase;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _first.requestFocus();
    });
  }

  FocusNode get _first => _firsts[_phase]!;

  @override
  Widget build(BuildContext context) {
    final l = ShikooL10n.of(context);
    final isTV = ref.watch(shikooStateProvider.select((s) => s.isTV));
    _focusFirst(isTV);
    return SubPage(
      title: l.reportTitle,
      isTV: isTV,
      scrolls: false,
      child: _phase == _Phase.preview
          ? _Preview(
              shots: widget.shots,
              images: _images,
              isTV: isTV,
              send: _first,
              onImages: (on) => setState(() => _images = on),
              onSend: () => unawaited(_send()),
              onCancel: _leave,
            )
          : _result(context, isTV),
    );
  }

  Widget _result(BuildContext context, bool isTV) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    final paragraph = t.text(
      isTV ? s.title : s.bodySm,
      color: t.c.textMuted,
      height: Leading.body,
    );
    Widget button(
      String label,
      VoidCallback onPressed, {
      ShikooIcon? icon,
      bool primary = false,
      bool first = false,
    }) => ShikooButton(
      label: label,
      icon: icon,
      primary: primary,
      height: isTV ? null : ShikooSizes.touch,
      focusNode: first ? _first : null,
      onPressed: onPressed,
    );
    final retry = button(
      l.retry,
      () => unawaited(_send()),
      icon: ShikooIcon.refresh,
      primary: true,
      first: true,
    );
    final cancel = button(l.cancelButton, _leave);
    final close = button(l.close, _leave);
    final support = button(
      l.support,
      () => _support(isTV),
      icon: isTV ? ShikooIcon.qr : null,
    );
    final sent = _sent;
    final error = _error;
    final clock = error is ShikooApiFailure && error.clock;
    // A phone keeps it over its buttons (phone-report-failed-clock); a TV under the title.
    final notice = clock
        ? MessageBox(
            icon: ShikooIcon.alert,
            danger: true,
            strong: l.clockWrongTitle,
            rest: l.clockWrongHelp,
          )
        : null;
    final (block, actions) = switch (_phase) {
      _Phase.sent when sent!.linked => (
        ResultBlock(
          icon: ShikooIcon.check,
          tone: ResultTone.positive,
          title: l.reportSentTitle,
          body: [TextSpan(text: l.reportSentLinked)],
          below: Text(
            l.reportCodeSmall('\u2066${_digits(context, sent.code)}\u2069'),
            textAlign: TextAlign.center,
            style: t.text(s.bodySm, color: t.c.textMuted),
          ),
        ),
        [button(l.close, _leave, primary: true, first: true), support],
      ),
      _Phase.sent => (
        ResultBlock(
          icon: ShikooIcon.check,
          tone: ResultTone.positive,
          title: l.reportSentTitle,
          body: const [],
          below: Column(
            spacing: Space.s3,
            children: [
              _CodeBox(code: _digits(context, sent!.code)),
              Text(
                l.reportGiveCode,
                textAlign: TextAlign.center,
                style: paragraph,
              ),
            ],
          ),
        ),
        [
          button(
            l.support,
            () => _support(isTV),
            icon: isTV ? ShikooIcon.qr : ShikooIcon.plane,
            primary: true,
            first: true,
          ),
          close,
        ],
      ),
      _Phase.failed when clock => (
        ResultBlock(
          icon: ShikooIcon.alert,
          tone: ResultTone.danger,
          title: l.reportFailedTitle,
          body: const [],
          below: isTV ? notice : null,
        ),
        [
          button(
            l.dateSettings,
            () => unawaited(openDateSettings()),
            icon: ShikooIcon.gear,
            primary: true,
            first: true,
          ),
          button(l.retry, () => unawaited(_send()), icon: ShikooIcon.refresh),
        ],
      ),
      _Phase.failed => (
        ResultBlock(
          icon: ShikooIcon.alert,
          tone: ResultTone.danger,
          title: l.reportFailedTitle,
          body: [TextSpan(text: failedHelp(l, error))],
        ),
        [retry, cancel],
      ),
      _ => (
        ResultBlock(
          icon: ShikooIcon.spin,
          spin: true,
          tone: ResultTone.muted,
          title: l.reportSending,
          body: const [],
        ),
        [button(l.cancelButton, _leave, first: true)],
      ),
    };
    if (isTV) {
      return Center(
        child: ShrinkToFit(
          child: Padding(
            padding: const EdgeInsets.all(Space.s2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.s6,
              children: [
                block,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.s2,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: Space.s8),
      child: FillPage(
        padding: const EdgeInsets.symmetric(horizontal: Space.s6),
        top: const SizedBox.shrink(),
        middle: Center(child: block),
        bottom: [if (_phase == _Phase.failed) ?notice, ...actions],
      ),
    );
  }
}

/// The sentence under «فرستاده نشد» for what the door answered, or did not.
String failedHelp(ShikooL10n l, Object? error) => switch (error) {
  ShikooApiFailure(status: 429) => l.reportFailedBusy,
  ShikooApiFailure(status: _?) => l.reportFailedRefused,
  _ => l.reportFailedHelp,
};

/// The report code in the UI's numerals, two groups of four, so it is read and typed whole.
String _digits(BuildContext context, String code) {
  final local = [
    for (final digit in code.split(''))
      int.tryParse(digit) == null
          ? digit
          : localNumber(context, int.parse(digit)),
  ].join();
  return local.length == 8
      ? '${local.substring(0, 4)} ${local.substring(4)}'
      : local;
}

/// `.code-box` with `.code-label`: large enough to read from three metres.
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s6,
        vertical: Space.s4,
      ),
      decoration: ShapeDecoration(
        color: t.c.surface,
        shadows: t.c.cardShadow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.s2,
        children: [
          Text(l.reportCodeLabel, style: t.text(s.body, color: t.c.textMuted)),
          Text(
            code,
            textDirection: TextDirection.ltr,
            style: t
                .text(s.code, weight: FontWeight.w800)
                .copyWith(wordSpacing: s.code * ShikooSizes.codeWordSpacing),
          ),
        ],
      ),
    );
  }
}

/// `.report`: the pictures, the switch and what is sent. A phone scrolls the middle under two
/// pinned buttons; a TV fits it all, the switch beside the buttons.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.shots,
    required this.images,
    required this.isTV,
    required this.send,
    required this.onImages,
    required this.onSend,
    required this.onCancel,
  });

  final ReportShots shots;
  final bool images;
  final bool isTV;
  final FocusNode send;
  final ValueChanged<bool> onImages;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    final s = t.s;
    final toggle = _SwitchRow(
      label: l.reportImagesSwitch,
      on: images,
      onChanged: onImages,
    );
    final note = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${l.reportWhatIsSent} '),
          TextSpan(
            text: l.reportNeverSent,
            style: TextStyle(color: t.c.text, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      style: t.text(s.bodySm, color: t.c.textMuted, height: Leading.body),
    );
    final sendButton = ShikooButton(
      label: l.reportSend,
      primary: true,
      height: isTV ? null : ShikooSizes.touch,
      focusNode: send,
      onPressed: onSend,
    );
    final cancel = ShikooButton(
      label: l.cancelButton,
      height: isTV ? null : ShikooSizes.touch,
      onPressed: onCancel,
    );
    if (isTV) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          ShikooSizes.ring,
          Space.s3,
          ShikooSizes.ring,
          ShikooSizes.ring,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.s3,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: _Pictures(shots: shots, on: images, shrinks: true),
              ),
            ),
            note,
            Row(
              spacing: Space.s3,
              children: [
                Expanded(child: toggle),
                sendButton,
                cancel,
              ],
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: s.safeX),
            child: TvScrollColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.s4,
                children: [
                  _Pictures(shots: shots, on: images),
                  toggle,
                  note,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            s.safeX,
            Space.s3,
            s.safeX,
            Space.s8 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.s3,
            children: [sendButton, cancel],
          ),
        ),
      ],
    );
  }
}

/// `.report-images`: two halves, each a sunken tile over its caption; a TV's [shrinks] to fit.
class _Pictures extends StatelessWidget {
  const _Pictures({
    required this.shots,
    required this.on,
    this.shrinks = false,
  });

  final ReportShots shots;
  final bool on;
  final bool shrinks;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final l = ShikooL10n.of(context);
    Widget picture(Uint8List? png, String caption) {
      final tile = Container(
        padding: const EdgeInsets.all(Space.s2),
        decoration: ShapeDecoration(
          color: t.c.surfaceSunken,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (png != null)
              Opacity(
                opacity: on ? 1 : 0.15,
                child: Image.memory(png, fit: BoxFit.contain),
              ),
            if (!on)
              Center(
                child: Text(
                  l.reportImageOff,
                  textAlign: TextAlign.center,
                  style: t.text(t.s.body, weight: FontWeight.w700),
                ),
              ),
          ],
        ),
      );
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.s2,
          children: [
            if (shrinks)
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: t.s.reportImage),
                  child: tile,
                ),
              )
            else
              SizedBox(height: t.s.reportImage, child: tile),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: t.text(t.s.bodySm, color: t.c.textMuted),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.s3,
      children: [
        picture(shots.app, l.reportImageApp),
        picture(shots.screen, l.reportImageScreen),
      ],
    );
  }
}

/// `.card` › `.row[role=switch]`: the whole row toggles, and the remote stays on it.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.on,
    required this.onChanged,
  });

  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final s = t.s;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
    );
    const pad = (ShikooSizes.switchH - ShikooSizes.switchThumb) / 2;
    return Pressable(
      shape: shape,
      onPressed: () => onChanged(!on),
      builder: (context, focused) => Semantics(
        toggled: on,
        label: label,
        excludeSemantics: true,
        child: Container(
          constraints: BoxConstraints(minHeight: s.row),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          decoration: ShapeDecoration(
            color: focused ? t.c.focusBg : t.c.surface,
            shadows: focused ? t.c.raisedShadow : t.c.cardShadow,
            shape: shape,
          ),
          child: Row(
            spacing: Space.s3,
            children: [
              Expanded(child: Text(label, style: t.text(s.body))),
              Container(
                width: ShikooSizes.switchW,
                height: ShikooSizes.switchH,
                padding: const EdgeInsets.all(pad),
                alignment: on
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                decoration: ShapeDecoration(
                  color: on ? t.c.primary : t.c.surfaceSunken,
                  shape: const StadiumBorder(),
                ),
                // A foreground, as the mockup's inset box-shadow: a border would shrink the thumb.
                foregroundDecoration: on
                    ? null
                    : ShapeDecoration(
                        shape: StadiumBorder(
                          side: BorderSide(
                            color: t.c.outline,
                            width: ShikooSizes.borderRadio,
                          ),
                        ),
                      ),
                child: Container(
                  width: ShikooSizes.switchThumb,
                  height: ShikooSizes.switchThumb,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? t.c.onPrimary : t.c.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
