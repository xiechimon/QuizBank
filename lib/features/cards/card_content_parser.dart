import 'package:flutter/material.dart';

/// 速记卡 content 行级解析 — 移植自 CardCleaning.swift / StudyCardContentFormatter.swift
/// 约定：# 标题、· 列表、| 表格、【】强调，其余为段落
sealed class CardBlock {
  const CardBlock();
}
class HeadingBlock extends CardBlock {
  final String text;
  const HeadingBlock(this.text);
}
class ParagraphBlock extends CardBlock {
  final String text;
  const ParagraphBlock(this.text);
}
class BulletBlock extends CardBlock {
  final String text;
  const BulletBlock(this.text);
}
class TableBlock extends CardBlock {
  final List<List<String>> rows;
  const TableBlock(this.rows);
}

class CardContentParser {
  static List<CardBlock> parse(String content) {
    final List<CardBlock> result = [];
    final List<List<String>> tableBuffer = [];

    void flushTable() {
      if (tableBuffer.isNotEmpty) {
        result.add(TableBlock(List.unmodifiable(tableBuffer.map((r) => List<String>.from(r)))));
        tableBuffer.clear();
      }
    }

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushTable();
        continue;
      }
      if (trimmed.startsWith('#')) {
        flushTable();
        final text = trimmed.substring(1).trim();
        result.add(HeadingBlock(text));
      } else if (trimmed.startsWith('|')) {
        final raw = trimmed.endsWith('|') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
        final inner = raw.startsWith('|') ? raw.substring(1) : raw;
        final cells = inner.split('|').map((e) => e.trim()).toList();
        tableBuffer.add(cells);
      } else if (trimmed.startsWith('·')) {
        flushTable();
        final text = trimmed.substring(1).trim();
        result.add(BulletBlock(text));
      } else {
        flushTable();
        result.add(ParagraphBlock(trimmed));
      }
    }
    flushTable();
    return result;
  }

  static String cleanBrackets(String text) {
    var result = text;
    while (true) {
      final open = result.indexOf('【');
      if (open == -1) break;
      final close = result.indexOf('】', open + 1);
      if (close == -1) break;
      result = result.substring(0, open) + result.substring(open + 1, close) + result.substring(close + 1);
    }
    return result;
  }

  static List<InlineSpan> buildSpans(String text, TextStyle base, Color highlight) {
    final spans = <InlineSpan>[];
    var i = 0;
    while (i < text.length) {
      final open = text.indexOf('【', i);
      if (open == -1) {
        spans.add(TextSpan(text: text.substring(i), style: base));
        break;
      }
      if (open > i) spans.add(TextSpan(text: text.substring(i, open), style: base));
      final close = text.indexOf('】', open + 1);
      if (close == -1) {
        spans.add(TextSpan(text: text.substring(open), style: base));
        break;
      }
      final inner = text.substring(open + 1, close);
      spans.add(TextSpan(
          text: inner,
          style: base.copyWith(color: highlight, fontWeight: FontWeight.bold, backgroundColor: highlight.withValues(alpha: 0.12))));
      i = close + 1;
    }
    return spans;
  }

  static String formatTableForSpeech(List<List<String>> rows) {
    if (rows.isEmpty) return '';
    final lines = <String>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final name = row.first.trim();
      if (name.isEmpty) continue;
      final values = row.skip(1).where((e) => e.trim().isNotEmpty).toList();
      if (values.isEmpty) {
        lines.add(name);
      } else {
        lines.add('$name：${values.join('、')}');
      }
    }
    return lines.join('。');
  }

  static List<String> cleanedTexts(String content) {
    final blocks = parse(content);
    final out = <String>[];
    for (final b in blocks) {
      if (b is HeadingBlock) {
        out.add(b.text);
      } else if (b is ParagraphBlock) {
        out.add(cleanBrackets(b.text));
      } else if (b is BulletBlock) {
        out.add(cleanBrackets(b.text));
      } else if (b is TableBlock) {
        final t = formatTableForSpeech(b.rows);
        if (t.trim().isNotEmpty) out.add(t);
      }
    }
    return out.where((e) => e.trim().isNotEmpty).toList();
  }
}
