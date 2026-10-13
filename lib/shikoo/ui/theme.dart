import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Every colour, size, radius and font of the Shikoo screens, from `design/tokens.css`.
/// A rebrand changes the values here; the names follow the CSS custom properties.

const shikooFont = 'Vazirmatn';

/// The font ships in `assets/fonts/`, which FlClash's pubspec already bundles as a folder,
/// so loading it here keeps pubspec.yaml untouched.
Future<void> loadShikooFonts() {
  final loader = FontLoader(shikooFont);
  for (final weight in const ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/Vazirmatn-$weight.ttf'));
  }
  return loader.load();
}

abstract final class Space {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;
  static const s16 = 64.0;
}

abstract final class Radii {
  static const xs = 3.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const markRatio = 0.28;
}

abstract final class Leading {
  static const tight = 1.35;
  static const body = 1.7;
  static const snug = 1.6;
}

@immutable
class ShikooColors {
  const ShikooColors({
    required this.bg,
    required this.surface,
    required this.surfaceSunken,
    required this.border,
    required this.outline,
    required this.text,
    required this.textMuted,
    required this.iconDisabled,
    required this.primary,
    required this.onPrimary,
    required this.selectedBg,
    required this.focusRing,
    required this.focusBg,
    required this.positive,
    required this.onPositive,
    required this.positiveSoft,
    required this.warning,
    required this.danger,
    required this.dangerSoft,
    required this.onDanger,
    required this.scrim,
    required this.cardShadow,
    required this.raisedShadow,
  });

  final Color bg;
  final Color surface;
  final Color surfaceSunken;
  final Color border;
  final Color outline;
  final Color text;
  final Color textMuted;
  final Color iconDisabled;
  final Color primary;
  final Color onPrimary;
  final Color selectedBg;
  final Color focusRing;
  final Color focusBg;
  final Color positive;
  final Color onPositive;
  final Color positiveSoft;
  final Color warning;
  final Color danger;
  final Color dangerSoft;
  final Color onDanger;
  final Color scrim;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> raisedShadow;

  static const light = ShikooColors(
    bg: Color(0xFFF4F4F1),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFECECE8),
    border: Color(0xFFDEDED8),
    outline: Color(0xFF8B8E87),
    text: Color(0xFF1A1B19),
    textMuted: Color(0xFF5C5F59),
    iconDisabled: Color(0xFFB3B6AF),
    primary: Color(0xFF1A1B19),
    onPrimary: Color(0xFFFFFFFF),
    selectedBg: Color(0xFFEDEEEA),
    focusRing: Color(0xFF1A1B19),
    focusBg: Color(0xFFFFFFFF),
    positive: Color(0xFF117036),
    onPositive: Color(0xFFFFFFFF),
    positiveSoft: Color(0xFFDCF2E3),
    warning: Color(0xFFA15C07),
    danger: Color(0xFFB42318),
    dangerSoft: Color(0xFFFCEBE9),
    onDanger: Color(0xFFFFFFFF),
    scrim: Color(0x73141614),
    cardShadow: [
      BoxShadow(color: Color(0x0F141614), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x0F141614), offset: Offset(0, 6), blurRadius: 16),
    ],
    raisedShadow: [
      BoxShadow(
        color: Color(0x29141614),
        offset: Offset(0, 10),
        blurRadius: 28,
      ),
    ],
  );

  /// Dark on light in both themes: many phone cameras miss an inverted QR.
  static const qrModule = Color(0xFF000000);
  static const qrBg = Color(0xFFFFFFFF);
  static const onQrBg = Color(0xFF1A1B19);

  /// Telegram's own blue, not Shikoo's, in both themes.
  static const telegram = Color(0xFF229ED9);
  static const onTelegram = Color(0xFFFFFFFF);

  static const dark = ShikooColors(
    bg: Color(0xFF121413),
    surface: Color(0xFF1B1E1D),
    surfaceSunken: Color(0xFF252927),
    border: Color(0xFF313634),
    outline: Color(0xFF737975),
    text: Color(0xFFECEEEC),
    textMuted: Color(0xFFA2A8A5),
    iconDisabled: Color(0xFF4C5250),
    primary: Color(0xFFECEEEC),
    onPrimary: Color(0xFF121413),
    selectedBg: Color(0xFF262B29),
    focusRing: Color(0xFFFFFFFF),
    focusBg: Color(0xFF343A37),
    positive: Color(0xFF3DD47A),
    onPositive: Color(0xFF06210F),
    positiveSoft: Color(0xFF153222),
    warning: Color(0xFFF2B544),
    danger: Color(0xFFF5847A),
    dangerSoft: Color(0xFF3A1D1A),
    onDanger: Color(0xFF2A0F0C),
    scrim: Color(0xA6000000),
    cardShadow: [
      BoxShadow(color: Color(0x80000000), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x4D000000), offset: Offset(0, 6), blurRadius: 16),
    ],
    raisedShadow: [
      BoxShadow(
        color: Color(0x99000000),
        offset: Offset(0, 10),
        blurRadius: 28,
      ),
    ],
  );
}

/// Phone and TV share the names; the TV values are sized for three metres (`[data-device="tv"]`).
@immutable
class ShikooSizes {
  const ShikooSizes({
    required this.caption,
    required this.bodySm,
    required this.body,
    required this.title,
    required this.display,
    required this.appbar,
    required this.row,
    required this.button,
    required this.buttonSm,
    required this.icon,
    required this.iconSm,
    required this.flagW,
    required this.flagH,
    required this.mark,
    required this.bar,
    required this.borderControl,
    required this.power,
    required this.powerRing,
    required this.safeX,
    required this.safeY,
    required this.pane,
    required this.dialog,
    required this.dialogText,
    required this.headline,
    required this.code,
    required this.heroIcon,
    required this.qr,
    required this.reportImage,
  });

  final double caption;
  final double bodySm;
  final double body;
  final double title;
  final double display;
  final double appbar;
  final double row;
  final double button;

  /// `.btn-sm`: renew in a finished service's row; its touch target stays [touch].
  final double buttonSm;
  final double icon;
  final double iconSm;
  final double flagW;
  final double flagH;
  final double mark;
  final double bar;
  final double borderControl;
  final double power;
  final double powerRing;
  final double safeX;
  final double safeY;
  final double pane;
  final double dialog;
  final double dialogText;
  final double headline;
  final double code;
  final double heroIcon;
  final double qr;

  /// The tallest a report preview's picture grows (`--size-report-image`).
  final double reportImage;

  static const phone = ShikooSizes(
    caption: 12,
    bodySm: 13,
    body: 15,
    title: 17,
    display: 26,
    appbar: 56,
    row: 56,
    button: 44,
    buttonSm: 36,
    icon: 24,
    iconSm: 18,
    flagW: 27,
    flagH: 18,
    mark: 32,
    bar: 8,
    borderControl: 1,
    power: 160,
    powerRing: 200,
    safeX: 16,
    safeY: 0,
    pane: 0,
    dialog: 340,
    dialogText: 13,
    headline: 24,
    code: 28,
    heroIcon: 64,
    qr: 200,
    reportImage: 200,
  );

  static const tv = ShikooSizes(
    caption: 12,
    bodySm: 14,
    body: 16,
    title: 20,
    display: 30,
    appbar: 40,
    row: 44,
    button: 40,
    buttonSm: 32,
    icon: 20,
    iconSm: 16,
    flagW: 30,
    flagH: 20,
    mark: 28,
    bar: 6,
    borderControl: 2,
    power: 176,
    powerRing: 224,
    safeX: 48,
    safeY: 27,
    pane: 500,
    dialog: 560,
    dialogText: 16,
    headline: 28,
    code: 40,
    heroIcon: 64,
    qr: 300,
    reportImage: 240,
  );

  static const touch = 48.0;

  static const tvCanvas = Size(960, 540);

  /// `--text-scale-max-round`: the round button's text grows no further, its circle being fixed.
  static const roundTextScaleMax = 1.15;

  /// `--name-shrink-min`: the smallest a card's service name gets before it is cut.
  static const nameShrinkMin = 0.75;
  static const powerIcon = 40.0;
  static const powerIconOn = 28.0;
  static const dot = 8.0;
  static const selectedBar = 4.0;
  static const focusRingWidth = 3.0;
  static const focusRingOffset = 2.0;

  /// Room for the focus ring, so it stays inside the TV's safe area (`.tv-top`, `.tv-settings`).
  static const ring = focusRingWidth + focusRingOffset;
  static const scrollThumb = 4.0;
  static const qrSm = 200.0;
  static const buttonLg = 56.0;
  static const buttonLgText = 19.0;
  static const markLg = 88.0;
  static const codeWordSpacing = 0.12;
  static const fade = 24.0;
  static const switchW = 52.0;
  static const switchH = 32.0;
  static const switchThumb = 24.0;
  static const borderRadio = 2.0;
  static const iconStroke = 2.0;
  static const iconStrokeStrong = 2.25;

  /// `--arc-stroke: 2` in a 100-unit frame, so it scales with the ring.
  static const arcStrokeRatio = 0.02;
}

@immutable
class ShikooTheme extends ThemeExtension<ShikooTheme> {
  const ShikooTheme(this.c, this.s);

  final ShikooColors c;
  final ShikooSizes s;

  static ShikooTheme of(BuildContext context) =>
      Theme.of(context).extension<ShikooTheme>()!;

  TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = Leading.tight,
    bool tabular = false,
  }) => TextStyle(
    fontFamily: shikooFont,
    fontSize: size,
    fontWeight: weight,
    color: color ?? c.text,
    height: height,
    letterSpacing: 0,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );

  @override
  ShikooTheme copyWith() => this;

  @override
  ShikooTheme lerp(ShikooTheme? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// FlClash's ThemeManager sets the bar icons from FlClash's own theme, dark by default.
class ShikooSystemUi extends StatelessWidget {
  const ShikooSystemUi({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final icons = brightness == Brightness.light
        ? Brightness.dark
        : Brightness.light;
    return AnnotatedRegion(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: icons,
        statusBarBrightness: brightness,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: icons,
        systemNavigationBarContrastEnforced: false,
      ),
      child: child,
    );
  }
}

class ShikooTvCanvas extends StatelessWidget {
  const ShikooTvCanvas({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!identical(ShikooTheme.of(context).s, ShikooSizes.tv)) return child;
    final data = MediaQuery.of(context);
    const canvas = ShikooSizes.tvCanvas;
    const safe = ShikooSizes.tv;
    final fit = math.min(
      data.size.width / canvas.width,
      data.size.height / canvas.height,
    );
    // One tree at every size, a window of no size yet too, so the app is never built afresh.
    final k = fit > 0 ? fit : 1.0;
    final size = data.size / k;
    return FittedBox(
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: data.copyWith(
            size: size,
            devicePixelRatio: data.devicePixelRatio * k,
            padding: data.padding / k,
            viewPadding:
                data.viewPadding / k +
                EdgeInsets.symmetric(
                  horizontal: safe.safeX,
                  vertical: safe.safeY,
                ),
            viewInsets: data.viewInsets / k,
            systemGestureInsets: data.systemGestureInsets / k,
          ),
          child: child,
        ),
      ),
    );
  }
}

ThemeData shikooThemeData(Brightness brightness, {required bool tv}) {
  final c = brightness == Brightness.light
      ? ShikooColors.light
      : ShikooColors.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: shikooFont,
    scaffoldBackgroundColor: c.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.positive,
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      surface: c.surface,
      onSurface: c.text,
      error: c.danger,
    ),
    extensions: [ShikooTheme(c, tv ? ShikooSizes.tv : ShikooSizes.phone)],
  );
}
