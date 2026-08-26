/// Small Yaru-flavoured building blocks for the Linux shell.
///
/// Ubuntu's design language: content grouped in [YaruSection]s of [YaruListTile]s,
/// a [YaruSearchField] above long lists with a [YaruChoiceChipBar] of filters,
/// dialogs with a [YaruDialogTitleBar]. Everything here is Material underneath,
/// which is how Yaru itself is built.
library;

import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../../core/presentation/list_filters.dart';

/// Page padding used across the Linux shell.
const vbankPagePadding = EdgeInsets.symmetric(horizontal: 24, vertical: 20);

/// A searchable, filterable list with Ubuntu's controls.
class YaruFilteredList<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) searchText;
  final List<ListFilter<T>> filters;
  final Widget Function(BuildContext context, List<T> items) builder;
  final String searchHint;
  final int minItemsForSearch;
  final Widget? header;

  const YaruFilteredList({
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
  State<YaruFilteredList<T>> createState() => _YaruFilteredListState<T>();
}

class _YaruFilteredListState<T> extends State<YaruFilteredList<T>> {
  String _query = '';
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final filters = widget.filters;
    final index = filters.isEmpty ? 0 : _filter.clamp(0, filters.length - 1);
    final visible = widget.items.where((item) {
      if (filters.isNotEmpty && !filters[index].test(item)) return false;
      return matchesQuery(widget.searchText(item), _query);
    }).toList();

    final showSearch = widget.items.length >= widget.minItemsForSearch || _query.isNotEmpty;
    final narrowed = visible.length != widget.items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != null) widget.header!,
        if (showSearch || filters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSearch)
                  YaruSearchField(
                    hintText: widget.searchHint,
                    text: _query,
                    onChanged: (v) => setState(() => _query = v),
                    onClear: () => setState(() => _query = ''),
                  ),
                if (filters.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  YaruChoiceChipBar(
                    labels: [for (final f in filters) Text(f.label)],
                    isSelected: [for (var i = 0; i < filters.length; i++) i == index],
                    onSelected: (i) => setState(() => _filter = i),
                  ),
                ],
                if (narrowed) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${visible.length} of ${widget.items.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? YaruEmpty(
                  icon: YaruIcons.search,
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

/// Centred placeholder, styled like Ubuntu's empty views.
class YaruEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const YaruEmpty({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Label/value row used inside sections.
class YaruInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const YaruInfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => YaruListTile(
        title: Text(label),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
}

/// Status pill (loan/meeting/transaction state).
class YaruStatusChip extends StatelessWidget {
  final String label;
  final Color? color;
  const YaruStatusChip(this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: c)),
    );
  }
}

/// A big number with a caption — group fund, member balance.
class YaruStatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasise;
  const YaruStatTile({super.key, required this.label, required this.value, this.emphasise = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: emphasise ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// The app's root messenger. Dialog contexts have no Scaffold of their own,
/// so `ScaffoldMessenger.of(dialogContext)` can end up with nothing to present
/// to; going through the app-level key always reaches the page underneath.
final yaruMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Ubuntu-style toast: a snack bar with no floating behaviour.
void yaruToast(BuildContext context, String message, {bool error = false}) {
  final theme = Theme.of(context);
  final bar = SnackBar(
    content: Text(message),
    backgroundColor: error ? theme.colorScheme.error : null,
    duration: Duration(seconds: error ? 5 : 3),
  );
  final messenger = yaruMessengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);
  try {
    messenger?.showSnackBar(bar);
  } catch (_) {
    // No Scaffold anywhere (e.g. a bare dialog during start-up): drop the toast
    // rather than crash the gesture handler.
  }
}

/// Ubuntu dialog frame: [YaruDialogTitleBar] plus an actions row.
Future<T?> yaruDialog<T>(
  BuildContext context, {
  required String title,
  required Widget content,
  required List<Widget> Function(BuildContext context) actions,
  double width = 460,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => AlertDialog(
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: YaruDialogTitleBar(title: Text(title)),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(child: content),
      ),
      actions: actions(context),
    ),
  );
}

/// Yes/no confirmation.
Future<bool> yaruConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await yaruDialog<bool>(
    context,
    title: title,
    content: Text(message),
    actions: (context) => [
      OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
      if (destructive)
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        )
      else
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
    ],
  );
  return result == true;
}

/// Single-field prompt.
Future<String?> yaruPrompt(
  BuildContext context, {
  required String title,
  String? message,
  String label = '',
  String initial = '',
  bool obscure = false,
  TextInputType? keyboardType,
  String confirmLabel = 'OK',
  int maxLines = 1,
}) async {
  final controller = TextEditingController(text: initial);
  return yaruDialog<String>(
    context,
    title: title,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message != null) ...[Text(message), const SizedBox(height: 16)],
        TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label.isEmpty ? null : label),
          onSubmitted: maxLines == 1 ? (v) => Navigator.pop(context, v) : null,
        ),
      ],
    ),
    actions: (context) => [
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(confirmLabel)),
    ],
  );
}
