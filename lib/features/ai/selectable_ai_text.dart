import 'package:flutter/material.dart';

/// 可选文本 + 「AI解析」选区菜单
/// 移植自 SelectableText.swift：长按选区后在系统菜单首位插入 AI 解析
class SelectableAIText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Color? highlightColor;
  final void Function(String selection) onExplain;
  final bool selectable;

  const SelectableAIText({
    super.key,
    required this.text,
    required this.onExplain,
    this.style,
    this.highlightColor,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!selectable || text.trim().isEmpty) {
      return Text(text, style: style);
    }
    return SelectableText(
      text,
      style: style,
      contextMenuBuilder: (context, editableTextState) {
        final selection = editableTextState.currentTextEditingValue.selection;
        final full = editableTextState.currentTextEditingValue.text;
        String selected = '';
        if (!selection.isCollapsed && selection.isValid) {
          final start = selection.start.clamp(0, full.length);
          final end = selection.end.clamp(0, full.length);
          selected = full.substring(start, end).trim();
        }
        final canExplain = selected.isNotEmpty;
        final buttonItems = editableTextState.contextMenuButtonItems;
        // Insert AI item at front
        final items = <ContextMenuButtonItem>[
          if (canExplain)
            ContextMenuButtonItem(
              label: 'AI解析',
              onPressed: () {
                ContextMenuController.removeAny();
                onExplain(selected);
              },
            ),
          ...buttonItems,
        ];
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: items,
        );
      },
    );
  }
}

/// 强调高亮版：【】 内橙色加粗
class HighlightedAIText extends StatelessWidget {
  final String raw;
  final TextStyle baseStyle;
  final Color highlight;
  final void Function(String) onExplain;

  const HighlightedAIText({super.key, required this.raw, required this.baseStyle, required this.highlight, required this.onExplain});

  @override
  Widget build(BuildContext context) {
    // build spans with highlight for 【】
    final spans = _buildSpans(raw, baseStyle, highlight);
    // For AI selection we need selectable; use SelectableText.rich with custom menu
    // Fallback: use SelectableAIText for plain if no brackets
    if (!raw.contains('【')) {
      return SelectableAIText(text: raw, style: baseStyle, onExplain: onExplain);
    }
    // Rich selectable with highlight: use SelectableText.rich
    return SelectableText.rich(
      TextSpan(children: spans),
      contextMenuBuilder: (context, editableTextState) {
        final selection = editableTextState.currentTextEditingValue.selection;
        final full = editableTextState.currentTextEditingValue.text;
        String selected = '';
        if (!selection.isCollapsed && selection.isValid) {
          final start = selection.start.clamp(0, full.length);
          final end = selection.end.clamp(0, full.length);
          selected = full.substring(start, end).trim();
        }
        final items = <ContextMenuButtonItem>[
          if (selected.isNotEmpty)
            ContextMenuButtonItem(label: 'AI解析', onPressed: () { ContextMenuController.removeAny(); onExplain(selected); }),
          ...editableTextState.contextMenuButtonItems,
        ];
        return AdaptiveTextSelectionToolbar.buttonItems(anchors: editableTextState.contextMenuAnchors, buttonItems: items);
      },
    );
  }

  static List<InlineSpan> _buildSpans(String text, TextStyle base, Color hl) {
    final spans = <InlineSpan>[];
    var i = 0;
    while (i < text.length) {
      final open = text.indexOf('【', i);
      if (open == -1) { spans.add(TextSpan(text: text.substring(i), style: base)); break; }
      if (open > i) spans.add(TextSpan(text: text.substring(i, open), style: base));
      final close = text.indexOf('】', open + 1);
      if (close == -1) { spans.add(TextSpan(text: text.substring(open), style: base)); break; }
      final inner = text.substring(open + 1, close);
      spans.add(TextSpan(text: inner, style: base.copyWith(color: hl, fontWeight: FontWeight.bold, backgroundColor: hl.withValues(alpha: 0.12))));
      i = close + 1;
    }
    return spans;
  }
}
