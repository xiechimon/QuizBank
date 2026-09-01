import 'package:flutter/material.dart';
import '../ai/selectable_ai_text.dart';
import 'card_content_parser.dart';

/// 速记卡富文本视图 — 移植 StudyCardContentFormatter.swift
/// heading 不可选，其余 paragraph/bullet/table 可选并带 AI 解析菜单
/// heading 使用橙色竖条，table 使用 ClipRRect + 横向 SingleChildScrollView
class CardContentView extends StatelessWidget {
  final String content;
  final void Function(String selection) onExplain;
  final int? highlightIndex;

  const CardContentView({super.key, required this.content, required this.onExplain, this.highlightIndex});

  @override
  Widget build(BuildContext context) {
    final blocks = CardContentParser.parse(content);
    final hl = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: highlightIndex == i
                ? BoxDecoration(color: hl.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6))
                : null,
            padding: highlightIndex == i ? const EdgeInsets.all(6) : EdgeInsets.zero,
            child: _buildBlock(context, blocks[i], hl),
          ),
      ],
    );
  }

  Widget _buildBlock(BuildContext context, CardBlock block, Color hl) {
    final cs = Theme.of(context).colorScheme;
    final orange = Colors.orange.shade700;
    if (block is HeadingBlock) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 4, height: 14, decoration: BoxDecoration(color: orange, borderRadius: BorderRadius.circular(1.5))),
          const SizedBox(width: 8),
          Expanded(child: Text(block.text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
        ],
      );
    } else if (block is ParagraphBlock) {
      return HighlightedAIText(
        raw: block.text,
        baseStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(height: 1.6, color: cs.onSurface),
        highlight: orange,
        onExplain: onExplain,
      );
    } else if (block is BulletBlock) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('·', style: TextStyle(color: hl, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: HighlightedAIText(
              raw: block.text,
              baseStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(height: 1.6),
              highlight: orange,
              onExplain: onExplain,
            ),
          ),
        ],
      );
    } else if (block is TableBlock) {
      final rows = block.rows;
      if (rows.isEmpty) return const SizedBox.shrink();
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rows.length; i++)
                  Container(
                    decoration: BoxDecoration(
                      color: i == 0 ? hl.withValues(alpha: 0.08) : null,
                      border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3), width: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var j = 0; j < rows[i].length; j++)
                          Container(
                            constraints: const BoxConstraints(minWidth: 90),
                            width: 120,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: j == 0 ? cs.surfaceContainerHighest.withValues(alpha: 0.5) : null,
                              border: j < rows[i].length - 1
                                  ? Border(right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2), width: 0.5))
                                  : null,
                            ),
                            child: HighlightedAIText(
                              raw: rows[i][j],
                              baseStyle: Theme.of(context).textTheme.bodySmall!.copyWith(
                                    fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
                                    height: 1.3,
                                  ),
                              highlight: orange,
                              onExplain: onExplain,
                            ),
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
    return const SizedBox.shrink();
  }
}
