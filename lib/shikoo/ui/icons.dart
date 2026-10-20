import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// Icons and flags drawn exactly as `design/mockups/mockup.js` draws them (its SVG symbols).
/// Icons are strokes in the text colour; flags carry their own colours, as content.
enum ShikooIcon {
  power('<path d="M12 3.5v8"/><path d="M6.7 6.8a7.5 7.5 0 1 0 10.6 0"/>'),
  gear(
    '<path d="M9.96 4.89L10.5 2.52h3l.54 2.37 1.55.64 2.05-1.3 2.13 2.13-1.3 2.05.64 1.55 2.37.54v3l-2.37.54-.64 1.55 1.3 2.05-2.13 2.13-2.05-1.3-1.55.64-.54 2.37h-3l-.54-2.37-1.55-.64-2.05 1.3-2.13-2.13 1.3-2.05-.64-1.55-2.37-.54v-3l2.37-.54.64-1.55-1.3-2.05 2.13-2.13 2.05 1.3z"/><circle cx="12" cy="12" r="3"/>',
  ),
  check('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
  alert(
    '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5"/><path d="M12 16.4v.2"/>',
  ),
  bell(
    '<path d="M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>',
  ),
  qr(
    '<rect x="3.5" y="3.5" width="6" height="6" rx="1"/><rect x="14.5" y="3.5" width="6" height="6" rx="1"/><rect x="3.5" y="14.5" width="6" height="6" rx="1"/><path d="M14.5 14.5h2.5v2.5"/><path d="M20.5 14.5v.5"/><path d="M14.5 20.5h6v-2"/>',
  ),
  refresh(
    '<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3"/><path d="M19.5 4.5v4h-4"/>',
  ),
  gauge(
    '<path d="M5.99 19.01A8.5 8.5 0 1 1 18.01 19.01"/><path d="M12 13l4-4"/>',
  ),
  logout(
    '<path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4"/><path d="M9 8l-4 4 4 4"/><path d="M5 12h10"/>',
  ),
  chevronFwd('<path d="M15 6l-6 6 6 6"/>'),
  chevronUp('<path d="M6 15l6-6 6 6"/>'),
  chevronDown('<path d="M6 9l6 6 6-6"/>'),
  back('<path d="M5 12h14"/><path d="M13 6l6 6-6 6"/>'),
  search('<circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5l5 5"/>'),
  x('<path d="M6.5 6.5l11 11"/><path d="M17.5 6.5l-11 11"/>'),
  paste(
    '<rect x="5" y="4.5" width="14" height="17" rx="2"/><rect x="9" y="2.5" width="6" height="4" rx="1"/><path d="M9 12h6"/><path d="M9 16h4"/>',
  ),
  plane(
    '<path d="M21 3.5L3 10.8l6.8 2.6L12.5 20.5z"/><path d="M9.8 13.4L21 3.5"/>',
  ),
  spin('<path d="M12 3.5a8.5 8.5 0 1 1-8.5 8.5"/>'),
  download(
    '<path d="M12 4v11"/><path d="M7 10.5l5 5 5-5"/><path d="M5 20h14"/>',
  ),
  report(
    '<path d="M14 3.5H7a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8.5z"/><path d="M14 3.5v5h5"/><path d="M9 13h6"/><path d="M9 16.5h4"/>',
  ),
  plus('<path d="M12 5v14"/><path d="M5 12h14"/>'),
  wifi(
    '<path d="M3.5 9.5a12 12 0 0 1 17 0"/><path d="M6.8 13a7.5 7.5 0 0 1 10.4 0"/><path d="M10 16.4a3 3 0 0 1 4 0"/>',
  ),
  shield(
    '<path d="M12 3l7.5 3v5.5c0 4.6-3.2 8.2-7.5 9.5-4.3-1.3-7.5-4.9-7.5-9.5V6z"/><path d="M9 12l2.2 2.2L15.5 10"/>',
  ),
  handle('<path d="M5 8h14"/><path d="M5 12h14"/><path d="M5 16h14"/>');

  const ShikooIcon(this.paths);

  final String paths;
}

class SvgIcon extends StatelessWidget {
  const SvgIcon(
    this.icon, {
    super.key,
    required this.size,
    required this.color,
    this.stroke = ShikooSizes.iconStroke,
  });

  final ShikooIcon icon;
  final double size;
  final Color color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
      'stroke="#000" stroke-width="$stroke" stroke-linecap="round" '
      'stroke-linejoin="round">${icon.paths}</svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

const _flags = {
  'DE':
      '<rect width="30" height="20" fill="#FFCE00"/><rect width="30" height="13.34" fill="#DD0000"/><rect width="30" height="6.67" fill="#000"/>',
  'NL':
      '<rect width="30" height="20" fill="#21468B"/><rect width="30" height="13.34" fill="#FFF"/><rect width="30" height="6.67" fill="#AE1C28"/>',
  'FI':
      '<rect width="30" height="20" fill="#FFF"/><rect x="8" width="5.6" height="20" fill="#002F6C"/><rect y="7.2" width="30" height="5.6" fill="#002F6C"/>',
  'US':
      '<rect width="30" height="20" fill="#B22234"/><path d="M0 2.31h30M0 5.38h30M0 8.46h30M0 11.54h30M0 14.62h30M0 17.69h30" stroke="#FFF" stroke-width="1.54"/><rect width="13" height="10.77" fill="#3C3B6E"/><g fill="#FFF"><circle cx="2" cy="2" r=".7"/><circle cx="5" cy="2" r=".7"/><circle cx="8" cy="2" r=".7"/><circle cx="11" cy="2" r=".7"/><circle cx="3.5" cy="5.4" r=".7"/><circle cx="6.5" cy="5.4" r=".7"/><circle cx="9.5" cy="5.4" r=".7"/><circle cx="2" cy="8.8" r=".7"/><circle cx="5" cy="8.8" r=".7"/><circle cx="8" cy="8.8" r=".7"/><circle cx="11" cy="8.8" r=".7"/></g>',
  'GB':
      '<rect width="30" height="20" fill="#012169"/><path d="M0 0l30 20M30 0L0 20" stroke="#FFF" stroke-width="4"/><path d="M0 0l30 20M30 0L0 20" stroke="#C8102E" stroke-width="1.5"/><path d="M15 0v20M0 10h30" stroke="#FFF" stroke-width="6"/><path d="M15 0v20M0 10h30" stroke="#C8102E" stroke-width="3.5"/>',
};

/// A country flag in the design's 3:2 box. Countries the mockup has no drawing for use the
/// emoji flag from FlClash's bundled Twemoji font; an unknown country keeps only the space.
class Flag extends StatelessWidget {
  const Flag({super.key, required this.country});

  final String? country;

  @override
  Widget build(BuildContext context) {
    final t = ShikooTheme.of(context);
    final w = t.s.flagW;
    final h = t.s.flagH;
    final svg = _flags[country];
    final code = country;
    if (code == null) return SizedBox(width: w, height: h);
    final Widget art = svg != null
        ? SvgPicture.string(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 30 20">$svg</svg>',
            width: w,
            height: h,
            fit: BoxFit.fill,
          )
        : FittedBox(
            fit: BoxFit.cover,
            child: Text(
              String.fromCharCodes(
                code.codeUnits.map((unit) => 0x1F1A5 + unit),
              ),
              style: const TextStyle(fontFamily: 'Twemoji', height: 1),
            ),
          );
    return Container(
      width: w,
      height: h,
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: t.c.border),
      ),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.xs)),
      child: art,
    );
  }
}
