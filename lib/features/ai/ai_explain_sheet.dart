import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../data/models.dart';
import 'ai_config.dart';
import 'ai_explain_service.dart';

/// AI 解析 Sheet — 移植 AIExplainView.swift
/// 上半选中原文，下半 Markdown 流式结果，支持重试/复制
/// - DraggableScrollableSheet 0.5~0.95
/// - 上：选中引用；下：MarkdownBody(selectable:true) 流式追加
/// - mimo/deepseek 走 explainStream 增量，longcat 降级一次返回
/// - 401/网络/空响应/超时 显示占位+重试，不白屏，30s 超时兜底
/// - 底部显示当前 model
class AIExplainSheet extends StatefulWidget {
  final String selection;
  final Question? question;
  final bool submitted;
  final String? cardTitle;
  final String? cardContent;
  final ScrollController? scrollController;

  const AIExplainSheet(
      {super.key,
      required this.selection,
      this.question,
      this.submitted = false,
      this.cardTitle,
      this.cardContent,
      this.scrollController});

  static Future<void> show(BuildContext context,
      {required String selection, Question? question, bool submitted = false, String? cardTitle, String? cardContent}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollCtrl) => AIExplainSheet(
          selection: selection,
          question: question,
          submitted: submitted,
          cardTitle: cardTitle,
          cardContent: cardContent,
          scrollController: scrollCtrl,
        ),
      ),
    );
  }

  @override
  State<AIExplainSheet> createState() => _AIExplainSheetState();
}

class _AIExplainSheetState extends State<AIExplainSheet> {
  String _result = '';
  String? _error;
  bool _loading = true;
  bool _streaming = false;
  StreamSubscription<String>? _sub;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  String _buildContext() {
    if (widget.question != null) {
      return AIExplainContext.forQuestion(widget.question!, submitted: widget.submitted);
    }
    if (widget.cardContent != null) {
      return '【速记卡】${widget.cardTitle ?? ''}\n${widget.cardContent}';
    }
    return '';
  }

  // ——— 抄自 AppleProjects/QuizBank AIExplainService.buildInput ———
  String get _prompt {
    final ctx = _buildContext().trim();
    final buf = StringBuffer();
    buf.writeln('【用户选中的文字】');
    buf.writeln(widget.selection.trim());
    if (ctx.isNotEmpty) {
      final trimmed = ctx.length > 500 ? '${ctx.substring(0, 500)}…' : ctx;
      buf.writeln('\n【整题上下文】');
      buf.writeln(trimmed);
    }
    buf.writeln('\n请按上述要求解析“用户选中的文字”，结合整题上下文说明考点与做题提示。');
    return buf.toString();
  }

  bool _isFallbackDelta(String delta) {
    final t = delta.trim();
    return t.startsWith('【网络错误') ||
        t.startsWith('【鉴权失败') ||
        t.startsWith('【空响应') ||
        t.startsWith('【请求失败') ||
        t.startsWith('【AI 调用异常');
  }

  bool get _isFallbackResult {
    final r = _result.trim();
    return r.startsWith('【网络错误') ||
        r.startsWith('【鉴权失败') ||
        r.startsWith('【空响应') ||
        r.startsWith('【请求失败') ||
        r.startsWith('【AI 调用异常');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = '';
      _streaming = false;
    });
    _sub?.cancel();
    _timeoutTimer?.cancel();
    try {
      final model = await AIConfig.instance.model;
      final isStream = AIConfig.isStreamingModelFor(model);
      final service = await AIExplain.service;
      if (isStream) {
        _streaming = true;
        // 流式初始保持 loading，首个 delta 到达后再关，避免推理阶段空窗显示“暂无结果”
        if (mounted) setState(() => _loading = true);
        final stream = service.explainStream(prompt: _prompt);
        var got = false;
        // 30s 超时兜底：若 30s 内无任何 delta 且无错误，视为超时
        _timeoutTimer = Timer(const Duration(seconds: 30), () {
          if (_streaming && _result.isEmpty && _error == null && mounted) {
            _sub?.cancel();
            setState(() {
              _error = '请求超时，请重试';
              _loading = false;
              _streaming = false;
            });
          }
        });
        _sub = stream.listen((delta) {
          if (!mounted) return;
          got = true;
          if (_loading) {
            setState(() => _loading = false);
          }
          // 断流视为失败，不保留半截：若 delta 为错误前缀fallback，丢弃之前半截
          if (_isFallbackDelta(delta) && _result.isNotEmpty) {
            setState(() => _result = delta);
          } else if (_isFallbackDelta(delta) && _result.isEmpty) {
            setState(() => _result = delta);
          } else {
            setState(() => _result += delta);
          }
        }, onError: (e) {
          _timeoutTimer?.cancel();
          if (!mounted) return;
          setState(() {
            _error = e.toString();
            _loading = false;
            _streaming = false;
            // 断流不保留半截：无论是否 fallback 都清已攒半截，由 fallbackStream 重给
            _result = '';
          });
          _sub?.cancel();
        }, onDone: () {
          _timeoutTimer?.cancel();
          if (!mounted) return;
          if (!got && _result.trim().isEmpty) {
            setState(() => _error = 'AI 未返回内容');
          }
          setState(() {
            _loading = false;
            _streaming = false;
          });
        });
      } else {
        final full = await service.explain(prompt: _prompt);
        if (!mounted) return;
        _timeoutTimer?.cancel();
        setState(() {
          _result = full;
          _loading = false;
          _streaming = false;
        });
      }
    } catch (e) {
      _timeoutTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _streaming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final markdownStyle = MarkdownStyleSheet(
      p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
      h1: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      h2: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      h3: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      strong: const TextStyle(fontWeight: FontWeight.bold),
      em: const TextStyle(fontStyle: FontStyle.italic),
      blockquote: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      blockquoteDecoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: cs.primary.withValues(alpha: 0.7), width: 3))),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      listBullet: Theme.of(context).textTheme.bodyMedium,
      listIndent: 20,
      tableHead: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
      tableBody: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
      tableHeadAlign: TextAlign.center,
      tableBorder: TableBorder.all(color: cs.outlineVariant.withValues(alpha: 0.6), width: 0.7),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      tableCellsDecoration: const BoxDecoration(),
      code: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            backgroundColor: cs.surfaceContainerHighest,
            fontSize: (Theme.of(context).textTheme.bodySmall?.fontSize ?? 12) * 0.92,
          ),
      codeblockDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      codeblockPadding: const EdgeInsets.all(12),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AI 解析'),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        actions: [
          if (_result.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: '复制',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _result));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
              },
            ),
        ],
        bottom: (_loading || (_streaming && _result.isEmpty && _error == null))
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator())
            : null,
      ),
      body: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // selection quote — 上半回显选中原文
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.secondaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    width: 3,
                    height: 40,
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(
                    child: SelectableText(widget.selection,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4, color: cs.onSecondaryContainer))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (_loading || (_streaming && _result.isEmpty && _error == null))
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('正在解析…', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            )
          else if (_error != null)
            Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
                    const SizedBox(height: 8),
                    SelectableText(_error!, style: TextStyle(color: cs.onErrorContainer)),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('重试')),
                    const SizedBox(height: 8),
                    Text('将显示本地占位解析（离线可用）', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onErrorContainer)),
                  ],
                ),
              ),
            )
          else if (_result.isNotEmpty) ...[
            Card(
              elevation: 0,
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: MarkdownBody(
                  data: _result,
                  selectable: true,
                  styleSheet: markdownStyle,
                ),
              ),
            ),
            if (_isFallbackResult) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('重试')),
              const SizedBox(height: 6),
              Text('已显示占位解析，请检查网络/Key 后重试',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ] else
            Text('暂无结果', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 上下文拼装 — 移植 AIExplain.context(for:submitted:)
/// 包含题干/选项/提交后答案/解析，供模型更准
class AIExplainContext {
  static String forQuestion(Question q, {required bool submitted}) {
    final parts = <String>[];
    parts.add('【题干】${q.stem}');
    if (q.options.isNotEmpty) {
      final opts = q.options.map((o) => '${o.key}. ${o.text}').join('\n');
      parts.add('【选项】\n$opts');
    }
    if (submitted) {
      parts.add('【答案】${q.answer}');
      if (q.explanation.isNotEmpty) parts.add('【解析】${q.explanation}');
    }
    return parts.join('\n');
  }
}
