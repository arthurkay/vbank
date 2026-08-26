/// Fluent building blocks for the Windows shell: [ListTile] rows inside
/// [Card]s, an [AutoSuggestBox]-free search [TextBox] with a filter
/// [ComboBox], [ContentDialog] for forms and [InfoBar] for feedback.
library;

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/presentation/list_filters.dart';

const vbankFluentPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);

/// Searchable, filterable list with Fluent controls.
class FluentFilteredList<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) searchText;
  final List<ListFilter<T>> filters;
  final Widget Function(BuildContext context, List<T> items) builder;
  final String searchHint;
  final int minItemsForSearch;
  final Widget? header;

  const FluentFilteredList({
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
  State<FluentFilteredList<T>> createState() => _FluentFilteredListState<T>();
}

class _FluentFilteredListState<T> extends State<FluentFilteredList<T>> {
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
    final theme = FluentTheme.of(context);
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
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Row(
              children: [
                if (showSearch)
                  Expanded(
                    child: TextBox(
                      controller: _controller,
                      placeholder: widget.searchHint,
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(FluentIcons.search, size: 12),
                      ),
                      suffix: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(FluentIcons.clear, size: 12),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                            ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                if (filters.isNotEmpty) ...[
                  if (showSearch) const SizedBox(width: 12),
                  ComboBox<int>(
                    value: index,
                    items: [
                      for (var i = 0; i < filters.length; i++)
                        ComboBoxItem(value: i, child: Text(filters[i].label)),
                    ],
                    onChanged: (i) => setState(() => _filter = i ?? 0),
                  ),
                ],
                if (narrowed) ...[
                  const SizedBox(width: 12),
                  Text('${visible.length} of ${widget.items.length}', style: theme.typography.caption),
                ],
              ],
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? FluentEmpty(
                  icon: FluentIcons.search,
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

class FluentEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const FluentEmpty({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: theme.inactiveColor.withValues(alpha: 0.6)),
            const SizedBox(height: 14),
            Text(title, style: theme.typography.subtitle),
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

/// A titled card of rows — Fluent's settings-page grouping.
class FluentGroup extends StatelessWidget {
  final String? label;
  final List<Widget> children;
  const FluentGroup({super.key, this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Text(label!, style: theme.typography.bodyStrong),
          ),
        Card(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class FluentInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const FluentInfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 170, child: Text(label, style: theme.typography.caption)),
          Expanded(child: Text(value, style: theme.typography.body)),
        ],
      ),
    );
  }
}

class FluentStatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasise;
  const FluentStatTile({super.key, required this.label, required this.value, this.emphasise = false});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Card(
      borderColor: emphasise ? theme.accentColor : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.typography.subtitle),
          const SizedBox(height: 4),
          Text(label, style: theme.typography.caption),
        ],
      ),
    );
  }
}

class FluentStatusChip extends StatelessWidget {
  final String label;
  final Color? color;
  const FluentStatusChip(this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final c = color ?? theme.inactiveColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(label, style: theme.typography.caption),
      ),
    );
  }
}

/// Fluent's transient feedback.
void fluentInfo(BuildContext context, String message, {bool error = false}) {
  displayInfoBar(
    context,
    duration: Duration(seconds: error ? 6 : 3),
    builder: (context, close) => InfoBar(
      title: Text(error ? 'Something went wrong' : 'Done'),
      content: Text(message),
      severity: error ? InfoBarSeverity.error : InfoBarSeverity.success,
      isLong: message.length > 60,
      onClose: close,
    ),
  );
}

/// Form/confirmation dialog.
Future<T?> fluentDialog<T>(
  BuildContext context, {
  required String title,
  required Widget content,
  required List<Widget> Function(BuildContext context) actions,
  double width = 460,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => ContentDialog(
      constraints: BoxConstraints(maxWidth: width),
      title: Text(title),
      content: SingleChildScrollView(child: content),
      actions: actions(context),
    ),
  );
}

Future<bool> fluentConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await fluentDialog<bool>(
    context,
    title: title,
    content: Text(message),
    actions: (context) => [
      Button(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
      FilledButton(
        style: destructive
            ? ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.red))
            : null,
        onPressed: () => Navigator.pop(context, true),
        child: Text(confirmLabel),
      ),
    ],
  );
  return result == true;
}

Future<String?> fluentPrompt(
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
  return fluentDialog<String>(
    context,
    title: title,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message != null) ...[Text(message), const SizedBox(height: 14)],
        if (obscure)
          PasswordBox(controller: controller, placeholder: placeholder)
        else
          TextBox(
            controller: controller,
            placeholder: placeholder,
            maxLines: maxLines,
            autofocus: true,
          ),
      ],
    ),
    actions: (context) => [
      Button(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(confirmLabel),
      ),
    ],
  );
}

/// Label above a field, Fluent style.
Widget fluentLabel(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: FluentTheme.of(context).typography.caption),
      ),
    );
