/// vBank UI kit — the Spark (o-systems/spark) design system on shadcn_flutter.
///
/// Conventions (mirroring Spark):
/// * Zinc light/dark theme, radius 0.5, no brand colour; red/green/orange only
///   as semantic accents.
/// * Lucide icons, never Material `Icons`.
/// * Content sits in muted, radius-12 panels ([Panel], [ListRow]); text fields
///   are borderless on the muted surface.
/// * Section labels are `.small.semiBold.muted` ([SectionTitle]); page padding 20.
/// * Prompts and confirmations are **bottom sheets** ([showAppSheet],
///   [confirmSheet], [promptSheet]) — never dialogs — padded by the keyboard.
/// * Transient feedback is a [SurfaceCard] toast ([showMessage]).
library;

import 'package:flutter/material.dart' as m;
import '../core/presentation/list_filters.dart' as shared;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:shadcn_flutter/shadcn_flutter.dart';

export 'package:shadcn_flutter/shadcn_flutter.dart';
export 'package:flutter/services.dart' show TextCapitalization;
export '../core/presentation/list_filters.dart'
    show ListFilter, matchesQuery, fmtDate, fmtDateTime, fmtMoney, titleCase;

// -----------------------------------------------------------------------------
// Theme
// -----------------------------------------------------------------------------

class VBankTheme {
  VBankTheme._();

  static ThemeData light() => ThemeData(colorScheme: ColorSchemes.lightZinc, radius: 0.5);
  static ThemeData dark() => ThemeData(colorScheme: ColorSchemes.darkZinc, radius: 0.5);

  /// Semantic accents (Spark uses the raw shadcn palette for these).
  static const Color success = Colors.green;
  static const Color danger = Colors.red;
  static Color warning(BuildContext context) => Colors.orange;

  /// Flutter's page-transition builders live in Material and read the *Material*
  /// theme: `ZoomPageTransitionsBuilder` composites an entering route over
  /// `Theme.of(context).colorScheme.surface`. `ShadcnApp` installs no Material
  /// theme, so that lookup fell back to `ThemeData.fallback()` (light) and every
  /// push flashed a light backdrop in dark mode. This shim sits above the
  /// navigator and pins those colours to the shadcn background.
  /// Flutter's page-transition builders live in Material and read the *Material*
  /// theme: `ZoomPageTransitionsBuilder` composites an entering route over
  /// `Theme.of(context).colorScheme.surface`. `ShadcnApp` installs no Material
  /// theme, so that lookup fell back to `ThemeData.fallback()` (light) and every
  /// push washed the page with light grey in dark mode.
  ///
  /// Call this from `ShadcnApp.builder`, so `context` is *below* the shadcn
  /// theme: the colours then always track the live theme (reading brightness
  /// above the app goes stale when the system flips light/dark).
  static Widget pageTransitionShim(BuildContext context, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    final background = scheme.background;
    final base = scheme.brightness == Brightness.dark ? m.ThemeData.dark() : m.ThemeData.light();
    return m.Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: background,
        canvasColor: background,
        colorScheme: base.colorScheme.copyWith(surface: background),
        pageTransitionsTheme: m.PageTransitionsTheme(
          builders: {
            m.TargetPlatform.android: m.ZoomPageTransitionsBuilder(backgroundColor: background),
            m.TargetPlatform.fuchsia: m.ZoomPageTransitionsBuilder(backgroundColor: background),
            m.TargetPlatform.linux: m.ZoomPageTransitionsBuilder(backgroundColor: background),
            m.TargetPlatform.windows: m.ZoomPageTransitionsBuilder(backgroundColor: background),
            m.TargetPlatform.iOS: const m.CupertinoPageTransitionsBuilder(),
            m.TargetPlatform.macOS: const m.CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: scheme.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: child,
      ),
    );
  }

  /// Spark's borderless text fields and invisible focus ring.
  static Widget componentThemes({required Widget child}) => ComponentTheme<FocusOutlineTheme>(
        data: FocusOutlineTheme(border: Border.all(color: Colors.transparent, width: 0), align: 0),
        child: ComponentTheme<TextFieldTheme>(
          data: TextFieldTheme(border: Border.all(color: Colors.transparent)),
          child: child,
        ),
      );
}

const kPagePadding = EdgeInsets.all(20);
const kPanelRadius = 16.0;
const kHeroRadius = 20.0;

// -----------------------------------------------------------------------------
// Page scaffold
// -----------------------------------------------------------------------------

class AppPage extends StatelessWidget {
  final String title;
  final Widget? subtitle;
  final List<Widget> trailing;
  final Widget child;
  final bool showBack;
  final List<Widget> footers;
  final Widget? floating;

  const AppPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing = const [],
    this.showBack = true,
    this.footers = const [],
    this.floating,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            if (canPop)
              IconButton.ghost(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => Navigator.of(context).pop(),
              ),
          ],
          // One line of title, one of subtitle: the header never grows past two.
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: subtitle == null
              ? null
              : DefaultTextStyle.merge(maxLines: 1, overflow: TextOverflow.ellipsis, child: subtitle!),
          trailing: trailing,
          alignment: canPop ? Alignment.center : Alignment.centerLeft,
        ),
      ],
      footers: footers,
      child: floating == null
          ? child
          : Stack(
              children: [
                Positioned.fill(child: child),
                Positioned(right: 20, bottom: 20, child: floating!),
              ],
            ),
    );
  }
}

/// Pushes a screen with its own sheet layer (see `_withSheetLayer` in main.dart).
Future<T?> pushScreen<T>(BuildContext context, Widget screen) =>
    Navigator.push<T>(context, MaterialPageRoute(builder: (_) => DrawerOverlay(child: screen)));

// -----------------------------------------------------------------------------
// Bottom sheets (replace dialogs) — Spark style
// -----------------------------------------------------------------------------

typedef SheetBuilder<T> = Widget Function(BuildContext context, void Function([T? result]) close);

/// Opens a bottom sheet and resolves with the value passed to `close`.
/// The content is padded by the keyboard inset and scrolls, so text fields
/// stay visible while typing.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  IconData? icon,
  Color? iconColor,
  required SheetBuilder<T> builder,
  bool dismissible = true,
}) async {
  T? result;
  var closed = false;
  final completer = openSheetOverlay<void>(
    context: context,
    position: OverlayPosition.bottom,
    barrierDismissible: dismissible,
    builder: (ctx) {
      void close([T? value]) {
        if (closed) return;
        closed = true;
        result = value;
        closeSheet(ctx);
      }

      final insets = MediaQuery.viewInsetsOf(ctx).bottom;
      final maxHeight = MediaQuery.sizeOf(ctx).height * 0.9;
      return AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: insets),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: kPagePadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (icon != null) ...[Icon(icon, color: iconColor), const Gap(8)],
                      Expanded(child: Text(title).h4),
                    ],
                  ),
                  const Gap(16),
                  builder(ctx, close),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  await completer.future;
  return result;
}

/// Yes/no confirmation. Resolves `true` only when confirmed.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) async {
  final r = await showAppSheet<bool>(
    context,
    title: title,
    icon: icon ?? (destructive ? LucideIcons.trash2 : LucideIcons.info),
    iconColor: destructive ? VBankTheme.danger : null,
    builder: (ctx, close) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message).muted,
        const Gap(20),
        destructive
            ? DestructiveButton(onPressed: () => close(true), child: Text(confirmLabel))
            : PrimaryButton(onPressed: () => close(true), child: Text(confirmLabel)),
        const Gap(8),
        OutlineButton(onPressed: () => close(false), child: Text(cancelLabel)),
      ],
    ),
  );
  return r == true;
}

/// Single text prompt. Resolves `null` when cancelled.
Future<String?> promptSheet(
  BuildContext context, {
  required String title,
  String? message,
  String? label,
  String? hint,
  String initial = '',
  bool obscure = false,
  TextInputType? keyboardType,
  String confirmLabel = 'OK',
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initial);
  return showAppSheet<String>(
    context,
    title: title,
    builder: (ctx, close) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null) ...[Text(message).muted, const Gap(16)],
        LabeledField(
          label: label,
          child: TextField(cursorOpacityAnimates: false, 
            controller: controller,
            autofocus: true,
            obscureText: obscure,
            keyboardType: keyboardType,
            maxLines: maxLines,
            placeholder: hint == null ? null : Text(hint),
            features: obscure ? const [InputFeature.passwordToggle()] : const [],
            onSubmitted: maxLines == 1 ? (_) => close(controller.text) : null,
          ),
        ),
        const Gap(16),
        PrimaryButton(onPressed: () => close(controller.text), child: Text(confirmLabel)),
        const Gap(8),
        OutlineButton(onPressed: () => close(), child: const Text('Cancel')),
      ],
    ),
  );
}

// -----------------------------------------------------------------------------
// Toast
// -----------------------------------------------------------------------------

void showMessage(BuildContext context, String text, {bool error = false, String? description}) {
  showToast(
    context: context,
    location: ToastLocation.bottomCenter,
    showDuration: Duration(seconds: error ? 5 : 3),
    builder: (ctx, overlay) => SurfaceCard(
      child: Basic(
        leading: error ? const Icon(LucideIcons.circleAlert, color: VBankTheme.danger) : null,
        leadingAlignment: Alignment.center,
        title: Text(text),
        subtitle: description == null ? null : Text(description),
        trailing: IconButton.ghost(icon: const Icon(LucideIcons.x), onPressed: overlay.close),
        trailingAlignment: Alignment.center,
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Building blocks
// -----------------------------------------------------------------------------

/// Muted, radius-12 surface (Spark's tile container). Replaces `Card`.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final Color? color;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.selected = false, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (selected ? scheme.primary.withAlpha(20) : scheme.muted),
        borderRadius: BorderRadius.circular(kPanelRadius),
        border: selected ? Border.all(color: scheme.primary.withAlpha(60)) : null,
      ),
      child: child,
    );
  }
}

class LabeledField extends StatelessWidget {
  final String? label;
  final String? helper;
  final Widget child;
  const LabeledField({super.key, this.label, this.helper, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[Text(label!).semiBold.small, const Gap(6)],
        child,
        if (helper != null) ...[const Gap(6), Text(helper!).xSmall.muted],
      ],
    );
  }
}

/// Spark section label with optional trailing action.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(text.toUpperCase(), style: const TextStyle(letterSpacing: 1.2)).xSmall.semiBold.muted,
            ),
            ?trailing,
          ],
        ),
      );
}

/// A receipt line: muted label on the left, the value right-aligned.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasise;
  const InfoRow(this.label, this.value, {super.key, this.emphasise = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: Text(label).small.muted),
            const Gap(12),
            Expanded(
              flex: 3,
              child: Text(value, textAlign: TextAlign.right).small.medium,
            ),
          ],
        ),
      );
}

/// Spark list tile: muted panel, 18px leading icon, `.medium` title,
/// `.small.muted` subtitle.
class ListRow extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = Row(
      children: [
        if (leading != null) ...[
          IconTheme.merge(
            data: IconThemeData(size: 18, color: selected ? scheme.primary : scheme.mutedForeground),
            child: leading!,
          ),
          const Gap(10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title.medium,
              if (subtitle != null) ...[const Gap(2), subtitle!],
            ],
          ),
        ),
        if (trailing != null) ...[
          const Gap(8),
          IconTheme.merge(data: IconThemeData(size: 16, color: scheme.mutedForeground), child: trailing!),
        ],
      ],
    );
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: selected ? scheme.muted : null,
        border: Border(bottom: BorderSide(color: scheme.border)),
      ),
      child: body,
    );
    if (onTap == null) return row;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }
}

class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  const InitialsAvatar(this.name, {super.key, this.size = 36});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Avatar(
      initials: name.trim().isEmpty ? '?' : Avatar.getInitials(name),
      size: size,
      backgroundColor: scheme.background,
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool primary;
  const StatCard({super.key, required this.label, required this.value, this.primary = false});
  @override
  Widget build(BuildContext context) => Panel(
        selected: primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value).large.semiBold,
            const Gap(4),
            Text(label).xSmall.muted,
          ],
        ),
      );
}

/// The inverted "ticket" card: the page's one strong surface, used for the
/// group fund and for a loan. Light theme: near-black on white; dark theme:
/// white on black. [footer] sits below a perforation line.
class HeroCard extends StatelessWidget {
  final Widget body;
  final Widget? footer;
  const HeroCard({super.key, required this.body, this.footer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Light theme: an inverted (near-black) ticket. Dark theme: a lifted dark
    // surface with a hairline — a white slab is too loud on a black page.
    final dark = theme.brightness == Brightness.dark;
    final bg = dark ? scheme.card : scheme.primary;
    final fg = dark ? scheme.foreground : scheme.primaryForeground;
    final content = DefaultTextStyle.merge(
      style: TextStyle(color: fg),
      child: IconTheme.merge(data: IconThemeData(color: fg), child: body),
    );
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kHeroRadius),
        border: dark ? Border.all(color: scheme.border) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 18), child: content),
          if (footer != null) ...[
            _Perforation(color: scheme.background, lineColor: fg.withValues(alpha: 0.35)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: fg),
                child: IconTheme.merge(data: IconThemeData(color: fg), child: footer!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A dashed line with a notch on each side — the tear-off edge of a ticket.
class _Perforation extends StatelessWidget {
  final Color color;
  final Color lineColor;
  const _Perforation({required this.color, required this.lineColor});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 20,
        child: Stack(
          children: [
            Positioned(left: 20, right: 20, top: 9.5, child: DashedDivider(color: lineColor)),
            Positioned(left: -10, top: 0, child: _Notch(color)),
            Positioned(right: -10, top: 0, child: _Notch(color)),
          ],
        ),
      );
}

class _Notch extends StatelessWidget {
  final Color color;
  const _Notch(this.color);
  @override
  Widget build(BuildContext context) =>
      Container(width: 20, height: 20, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class DashedDivider extends StatelessWidget {
  final Color color;
  const DashedDivider({super.key, required this.color});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          const dash = 6.0, gap = 5.0;
          final n = (c.maxWidth / (dash + gap)).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(n, (_) => SizedBox(width: dash, height: 1, child: ColoredBox(color: color))),
          );
        },
      );
}

/// Label over a large value; inherits its colours so it works inside [HeroCard].
class Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool large;
  final CrossAxisAlignment align;
  const Metric({super.key, required this.label, required this.value, this.large = false, this.align = CrossAxisAlignment.start});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(opacity: 0.7, child: Text(label).xSmall),
          const Gap(4),
          large ? Text(value).x3Large.bold : Text(value).large.semiBold,
        ],
      );
}

/// Thin progress bar; [value] 0..1. Inherits the surrounding text colour for
/// its fill so it reads correctly on a [HeroCard] too.
class ProgressBar extends StatelessWidget {
  final double value;
  final double height;
  const ProgressBar({super.key, required this.value, this.height = 6});
  @override
  Widget build(BuildContext context) {
    final fg = DefaultTextStyle.of(context).style.color ?? Theme.of(context).colorScheme.foreground;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: fg.withValues(alpha: 0.18))),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: value.clamp(0, 1).toDouble(),
                heightFactor: 1,
                child: ColoredBox(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.mutedForeground),
            const Gap(16),
            Text(title, textAlign: TextAlign.center).semiBold,
            if (subtitle != null) ...[const Gap(6), Text(subtitle!, textAlign: TextAlign.center).small.muted],
            if (action != null) ...[const Gap(20), action!],
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  final Object error;
  const ErrorView(this.error, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $error').small.muted),
      );
}

/// Small status pill.
class StatusBadge extends StatelessWidget {
  final String text;
  final StatusTone tone;
  const StatusBadge(this.text, {super.key, this.tone = StatusTone.neutral});
  @override
  Widget build(BuildContext context) => switch (tone) {
        StatusTone.primary => PrimaryBadge(child: Text(text)),
        StatusTone.destructive => DestructiveBadge(child: Text(text)),
        StatusTone.secondary => SecondaryBadge(child: Text(text)),
        StatusTone.neutral => OutlineBadge(child: Text(text)),
      };
}

enum StatusTone { primary, secondary, destructive, neutral }

/// Spark filter chips as a single-choice control.
/// Page-level tabs: shadcn's underline [TabList], horizontally scrollable so
/// five labels fit on a phone, with one full-width hairline underneath.
class PageTabs extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const PageTabs({super.key, required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ComponentTheme<TabListTheme>(
          data: const TabListTheme(borderWidth: 0),
          child: TabList(
            index: index,
            onChanged: onChanged,
            children: [for (final l in labels) TabItem(child: Text(l))],
          ),
        ),
      ),
    );
  }
}

class Segmented<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  /// Horizontal scrolling row (Spark's filter bar) instead of a wrapping row.
  final bool scrollable;
  const Segmented({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    // shadcn's boxed segmented control: page tabs are underlined (PageTabs),
    // filters and form choices sit in this muted box — two clearly different
    // things.
    final i = values.indexOf(selected);
    final tabs = Tabs(
      index: i < 0 ? 0 : i,
      onChanged: (i) => onChanged(values[i]),
      children: [for (final v in values) TabItem(child: Text(label(v)))],
    );
    if (scrollable || values.length > 4) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: tabs,
      );
    }
    return Row(children: [Expanded(child: Tabs(
      index: i < 0 ? 0 : i,
      onChanged: (i) => onChanged(values[i]),
      expand: true,
      children: [for (final v in values) TabItem(child: Text(label(v)))],
    ))]);
  }
}

class FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const FilterChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.foreground : scheme.muted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? scheme.background : scheme.foreground,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Spark-style search input: borderless, leading magnifier, clear button.
class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String placeholder;
  const SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.placeholder = 'Search',
  });

  @override
  Widget build(BuildContext context) => TextField(cursorOpacityAnimates: false, 
        controller: controller,
        placeholder: Text(placeholder),
        onChanged: onChanged,
        features: const [
          InputFeature.leading(Icon(LucideIcons.search, size: 16)),
          InputFeature.clear(),
        ],
      );
}

/// One chip in a [FilterableList]. Alias of the platform-neutral
/// `ListFilter`, so the same filter definitions drive the mobile chips and the
/// desktop shells' own controls.
typedef FilterOption<T> = shared.ListFilter<T>;

/// A searchable, filterable list section.
///
/// Owns the query and the selected filter, hands the surviving items to
/// [builder], and shows a "no matches" state when a search or filter excludes
/// everything. Search is a case-insensitive substring match against
/// [searchText]; the chips come from [filters] (omit them for search only).
///
/// The search field only appears once there are [minItemsForSearch] items, so
/// short lists stay uncluttered.
class FilterableList<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) searchText;
  final List<FilterOption<T>> filters;
  final Widget Function(BuildContext context, List<T> items) builder;
  final String searchPlaceholder;
  final int minItemsForSearch;
  final Widget? empty;
  final EdgeInsetsGeometry headerPadding;

  const FilterableList({
    super.key,
    required this.items,
    required this.searchText,
    required this.builder,
    this.filters = const [],
    this.searchPlaceholder = 'Search',
    this.minItemsForSearch = 6,
    this.empty,
    this.headerPadding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
  });

  @override
  State<FilterableList<T>> createState() => _FilterableListState<T>();
}

class _FilterableListState<T> extends State<FilterableList<T>> {
  final _controller = TextEditingController();
  String _query = '';
  int _filter = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty && widget.empty != null) return widget.empty!;

    final filters = widget.filters;
    final index = _filter.clamp(0, filters.isEmpty ? 0 : filters.length - 1);
    final q = _query.trim().toLowerCase();
    final filtered = widget.items.where((item) {
      if (filters.isNotEmpty && !filters[index].test(item)) return false;
      if (q.isEmpty) return true;
      return widget.searchText(item).toLowerCase().contains(q);
    }).toList();

    final showSearch = widget.items.length >= widget.minItemsForSearch || q.isNotEmpty;
    final narrowed = filtered.length != widget.items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSearch || filters.isNotEmpty)
          Padding(
            padding: widget.headerPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSearch)
                  SearchField(
                    controller: _controller,
                    placeholder: widget.searchPlaceholder,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                if (filters.isNotEmpty) ...[
                  if (showSearch) const Gap(10),
                  Segmented<int>(
                    scrollable: true,
                    values: [for (var i = 0; i < filters.length; i++) i],
                    selected: index,
                    label: (i) => filters[i].label,
                    onChanged: (i) => setState(() => _filter = i),
                  ),
                ],
                if (narrowed) ...[
                  const Gap(10),
                  Text('${filtered.length} of ${widget.items.length}').xSmall.muted,
                ],
              ],
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: LucideIcons.search,
                  title: 'No matches',
                  subtitle: q.isEmpty
                      ? 'Nothing here under this filter.'
                      : 'Nothing matches “$_query” under this filter.',
                )
              : widget.builder(context, filtered),
        ),
      ],
    );
  }
}

/// Simple dropdown.
class SimpleSelect<T> extends StatelessWidget {
  final T? value;
  final List<T> items;
  final String Function(T) label;
  final ValueChanged<T?> onChanged;
  final String placeholder;
  const SimpleSelect({
    super.key,
    required this.value,
    required this.items,
    required this.label,
    required this.onChanged,
    this.placeholder = 'Select',
  });

  @override
  Widget build(BuildContext context) {
    return Select<T>(
      value: value,
      onChanged: onChanged,
      placeholder: Text(placeholder),
      itemBuilder: (context, item) => Text(label(item)),
      popup: (context) => SelectPopup(
        items: SelectItemList(
          children: [for (final i in items) SelectItemButton(value: i, child: Text(label(i)).small)],
        ),
      ),
    );
  }
}

/// Overflow menu.
class ActionMenu extends StatelessWidget {
  final List<ActionMenuItem> items;
  final bool enabled;
  const ActionMenu({super.key, required this.items, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return IconButton.ghost(
      icon: const Icon(LucideIcons.ellipsisVertical, size: 16),
      onPressed: !enabled || items.isEmpty
          ? null
          : () {
              showDropdown(
                context: context,
                builder: (ctx) => DropdownMenu(
                  children: [
                    for (final i in items)
                      MenuButton(
                        leading: i.icon == null ? null : Icon(i.icon, size: 16),
                        onPressed: (_) => i.onSelected(),
                        child: Text(i.label),
                      ),
                  ],
                ),
              );
            },
    );
  }
}

class ActionMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback onSelected;
  const ActionMenuItem(this.label, this.onSelected, {this.icon});
}


