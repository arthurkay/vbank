/// macOS building blocks, in Apple's idiom: a sidebar window, toolbars,
/// [MacosListTile] rows, sheets for forms and [MacosAlertDialog] for
/// confirmations, [MacosSegmentedControl] for filters.
library;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../core/presentation/list_filters.dart';

const vbankMacPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 16);

/// Searchable, filterable list with a macOS search field and a segmented
/// control of filters.
class MacosFilteredList<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) searchText;
  final List<ListFilter<T>> filters;
  final Widget Function(BuildContext context, List<T> items) builder;
  final String searchHint;
  final int minItemsForSearch;
  final Widget? header;

  const MacosFilteredList({
    super.key,
    required this.items,
    required this.searchText,
    required this.builder,
    this.filters = const [],
    this.searchHint = 'Search',
    this.minItemsForSearch = 6,
    this.header,
  });

  @override
  State<MacosFilteredList<T>> createState() => _MacosFilteredListState<T>();
}

class _MacosFilteredListState<T> extends State<MacosFilteredList<T>> {
  final _controller = TextEditingController();
  MacosTabController? _tabs;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.filters.isNotEmpty) {
      _tabs = MacosTabController(length: widget.filters.length)..addListener(_onTab);
    }
  }

  void _onTab() => setState(() {});

  @override
  void dispose() {
    _tabs?.removeListener(_onTab);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filters = widget.filters;
    final index = _tabs?.index ?? 0;
    final visible = widget.items.where((item) {
      if (filters.isNotEmpty && !filters[index].test(item)) return false;
      return matchesQuery(widget.searchText(item), _query);
    }).toList();

    final showSearch = widget.items.length >= widget.minItemsForSearch || _query.isNotEmpty;
    final narrowed = visible.length != widget.items.length;
    final typography = MacosTheme.of(context).typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != null) widget.header!,
        if (showSearch || filters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSearch)
                  MacosTextField(
                    controller: _controller,
                    placeholder: widget.searchHint,
                    prefix: const MacosIcon(CupertinoIcons.search, size: 14),
                    clearButtonMode: OverlayVisibilityMode.editing,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                if (filters.isNotEmpty && _tabs != null) ...[
                  const SizedBox(height: 10),
                  MacosSegmentedControl(
                    controller: _tabs!,
                    tabs: [for (final f in filters) MacosTab(label: f.label)],
                  ),
                ],
                if (narrowed) ...[
                  const SizedBox(height: 8),
                  Text('${visible.length} of ${widget.items.length}', style: typography.caption1),
                ],
              ],
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? MacosEmpty(
                  icon: CupertinoIcons.search,
                  title: 'No matches',
                  subtitle: _query.isEmpty
                      ? 'Nothing here under this filter.'
                      : 'Nothing matches “$_query” under this filter.',
                )
              : widget.builder(context, visible),
        ),
      ],
    );
  }
}

class MacosEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const MacosEmpty({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MacosIcon(icon, size: 40, color: theme.typography.caption1.color),
            const SizedBox(height: 14),
            Text(title, style: theme.typography.headline),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: theme.typography.body),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// Grouped rows, the macOS “inset grouped” look.
class MacosGroupBox extends StatelessWidget {
  final String? label;
  final List<Widget> children;
  const MacosGroupBox({super.key, this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(label!.toUpperCase(), style: theme.typography.caption2),
          ),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.canvasColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// A row with a trailing control. `MacosListTile` has no trailing slot, so this
/// mirrors its metrics and typography and adds one.
class MacosRow extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const MacosRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle(style: theme.typography.headline, child: title),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  DefaultTextStyle(style: theme.typography.caption1, child: subtitle!),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: row);
  }
}

class MacosInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const MacosInfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 160, child: Text(label, style: theme.typography.caption1)),
          Expanded(child: Text(value, style: theme.typography.body)),
        ],
      ),
    );
  }
}

class MacosStatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasise;
  const MacosStatTile({super.key, required this.label, required this.value, this.emphasise = false});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.canvasColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: emphasise ? theme.primaryColor : theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: theme.typography.title2),
            const SizedBox(height: 4),
            Text(label, style: theme.typography.caption1),
          ],
        ),
      ),
    );
  }
}

class MacosStatusChip extends StatelessWidget {
  final String label;
  final Color? color;
  const MacosStatusChip(this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final c = color ?? theme.dividerColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(label, style: theme.typography.caption2),
      ),
    );
  }
}

/// macOS has no snack bar; brief feedback is an alert the user dismisses.
Future<void> macosToast(BuildContext context, String message, {bool error = false}) {
  return showMacosAlertDialog<void>(
    context: context,
    builder: (context) => MacosAlertDialog(
      appIcon: MacosIcon(
        error ? CupertinoIcons.exclamationmark_triangle : CupertinoIcons.checkmark_circle,
        size: 46,
      ),
      title: Text(error ? 'Something went wrong' : 'Done'),
      message: Text(message, textAlign: TextAlign.center),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context),
        child: const Text('OK'),
      ),
    ),
  );
}

Future<bool> macosConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showMacosAlertDialog<bool>(
    context: context,
    builder: (context) => MacosAlertDialog(
      appIcon: MacosIcon(
        destructive ? CupertinoIcons.exclamationmark_triangle : CupertinoIcons.question_circle,
        size: 46,
      ),
      title: Text(title),
      message: Text(message, textAlign: TextAlign.center),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        color: destructive ? MacosColors.systemRedColor : null,
        onPressed: () => Navigator.pop(context, true),
        child: Text(confirmLabel),
      ),
      secondaryButton: PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context, false),
        child: Text(cancelLabel),
      ),
    ),
  );
  return result == true;
}

/// A macOS sheet: slides down from the title bar, for anything with fields.
Future<T?> macosSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context) content,
  required List<Widget> Function(BuildContext context) actions,
  double width = 460,
}) {
  return showMacosSheet<T>(
    context: context,
    builder: (context) => MacosSheet(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: MacosTheme.of(context).typography.title3, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              Flexible(child: SingleChildScrollView(child: content(context))),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                for (final action in actions(context)) ...[action, const SizedBox(width: 8)],
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Single-field prompt as a sheet.
Future<String?> macosPrompt(
  BuildContext context, {
  required String title,
  String? message,
  String placeholder = '',
  String initial = '',
  bool obscure = false,
  String confirmLabel = 'OK',
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initial);
  return macosSheet<String>(
    context,
    title: title,
    content: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message != null) ...[
          Text(message, style: MacosTheme.of(context).typography.body),
          const SizedBox(height: 14),
        ],
        MacosTextField(
          controller: controller,
          placeholder: placeholder,
          obscureText: obscure,
          maxLines: maxLines,
          autofocus: true,
        ),
      ],
    ),
    actions: (context) => [
      PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(confirmLabel),
      ),
    ],
  );
}
