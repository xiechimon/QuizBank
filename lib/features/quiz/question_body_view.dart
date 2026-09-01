import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../core/grader.dart';
import '../ai/ai_explain_sheet.dart';
import '../ai/selectable_ai_text.dart';

/// Reusable question body with stem, options, and explanation.
/// Supports single, multiple, judge types.
class QuestionBodyView extends StatelessWidget {
  final Question question;
  final Set<String> selected; // for multiple: pending selections, for single: single chosen
  final bool submitted;
  final String? lastChosen; // normalized chosen string after submit
  final bool? lastCorrect;
  final ValueChanged<String>? onSingleTap;
  final ValueChanged<String>? onMultiToggle;
  final ValueChanged<bool>? onJudgeTap;
  final VoidCallback? onMultiSubmit;

  const QuestionBodyView({
    super.key,
    required this.question,
    this.selected = const {},
    this.submitted = false,
    this.lastChosen,
    this.lastCorrect,
    this.onSingleTap,
    this.onMultiToggle,
    this.onJudgeTap,
    this.onMultiSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _header(context),
        const SizedBox(height: 12),
        _stemCard(context),
        const SizedBox(height: 12),
        _optionsSection(context),
        if (submitted) ...[
          const SizedBox(height: 16),
          _explanationCard(context),
        ],
      ],
    );
  }

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typeLabel = question.type.displayName;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(typeLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  )),
        ),
        const SizedBox(width: 8),
        Text('ID ${question.id}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                )),
        const Spacer(),
        if (submitted && lastCorrect != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: lastCorrect! ? Colors.green.withValues(alpha: 0.15) : cs.errorContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(lastCorrect! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 14, color: lastCorrect! ? Colors.green : cs.error),
                const SizedBox(width: 4),
                Text(lastCorrect! ? '正确' : '错误',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: lastCorrect! ? Colors.green.shade700 : cs.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        )),
              ],
            ),
          ),
      ],
    );
  }

  Widget _stemCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableAIText(
          text: question.stem,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
          onExplain: (sel) => AIExplainSheet.show(context, selection: sel, question: question, submitted: submitted),
        ),
      ),
    );
  }

  Widget _optionsSection(BuildContext context) {
    switch (question.type) {
      case QuestionType.judge:
        return _judgeOptions(context);
      case QuestionType.single:
        return _singleOptions(context);
      case QuestionType.multiple:
        return _multipleOptions(context);
    }
  }

  Widget _singleOptions(BuildContext context) {
    final answer = question.answer.toUpperCase();
    return Column(
      children: question.options.map((opt) {
        final key = opt.key.toUpperCase();
        final isSelected = selected.contains(key);
        final isCorrect = answer.contains(key);
        Color? bg;
        Color? border;
        IconData? trailing;
        if (submitted) {
          if (isCorrect) {
            bg = Colors.green.withValues(alpha: 0.12);
            border = Colors.green;
            trailing = Icons.check_circle_rounded;
          } else if (isSelected && !isCorrect) {
            bg = Theme.of(context).colorScheme.errorContainer;
            border = Theme.of(context).colorScheme.error;
            trailing = Icons.cancel_rounded;
          }
        } else if (isSelected) {
          bg = Theme.of(context).colorScheme.primaryContainer;
          border = Theme.of(context).colorScheme.primary;
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            elevation: 0,
            color: bg ?? Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: border ?? Theme.of(context).colorScheme.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: submitted ? null : () => onSingleTap?.call(key),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected || (submitted && isCorrect)
                            ? (submitted && isCorrect ? Colors.green : Theme.of(context).colorScheme.primary)
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(key,
                            style: TextStyle(
                              color: isSelected || (submitted && isCorrect)
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            )),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(opt.text)),
                    if (trailing != null) Icon(trailing, size: 20, color: border),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _multipleOptions(BuildContext context) {
    final answer = question.answer.toUpperCase();
    return Column(
      children: [
        ...question.options.map((opt) {
          final key = opt.key.toUpperCase();
          final isSelected = selected.contains(key);
          final isCorrect = answer.contains(key);
          Color? bg;
          Color? border;
          IconData? trailing;
          if (submitted) {
            if (isCorrect) {
              bg = Colors.green.withValues(alpha: 0.12);
              border = Colors.green;
              trailing = Icons.check_circle_rounded;
            } else if (isSelected && !isCorrect) {
              bg = Theme.of(context).colorScheme.errorContainer;
              border = Theme.of(context).colorScheme.error;
              trailing = Icons.cancel_rounded;
            }
          } else if (isSelected) {
            bg = Theme.of(context).colorScheme.primaryContainer;
            border = Theme.of(context).colorScheme.primary;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              elevation: 0,
              color: bg ?? Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: border ?? Theme.of(context).colorScheme.outlineVariant),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: submitted ? null : () => onMultiToggle?.call(key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: submitted ? null : (_) => onMultiToggle?.call(key),
                      ),
                      Text(key, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(opt.text)),
                      if (trailing != null) Icon(trailing, size: 20, color: border),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        if (!submitted)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              onPressed: selected.isEmpty ? null : onMultiSubmit,
              child: const Text('提交多选'),
            ),
          ),
        if (submitted && lastChosen != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('你的答案: ${Grader.display(lastChosen!)}  正确答案: ${Grader.display(answer)}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _judgeOptions(BuildContext context) {
    final answer = question.answer.toUpperCase();
    final correctIsTrue = answer == 'T';
    final chosenIsTrue = lastChosen == 'T';
    return Row(
      children: [
        Expanded(
          child: _judgeButton(context,
              label: '正确',
              value: true,
              isSelected: selected.contains('T') || (submitted && chosenIsTrue),
              isCorrectChoice: correctIsTrue,
              submitted: submitted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _judgeButton(context,
              label: '错误',
              value: false,
              isSelected: selected.contains('F') || (submitted && !chosenIsTrue && lastChosen != null),
              isCorrectChoice: !correctIsTrue,
              submitted: submitted),
        ),
      ],
    );
  }

  Widget _judgeButton(BuildContext context,
      {required String label, required bool value, required bool isSelected, required bool isCorrectChoice, required bool submitted}) {
    Color? bg;
    Color? border;
    if (submitted) {
      if (isCorrectChoice) {
        bg = Colors.green.withValues(alpha: 0.15);
        border = Colors.green;
      } else if (isSelected && !isCorrectChoice) {
        bg = Theme.of(context).colorScheme.errorContainer;
        border = Theme.of(context).colorScheme.error;
      }
    } else if (isSelected) {
      bg = Theme.of(context).colorScheme.primaryContainer;
      border = Theme.of(context).colorScheme.primary;
    }
    return Card(
      elevation: 0,
      color: bg ?? Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border ?? Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: submitted ? null : () => onJudgeTap?.call(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(value ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
                  size: 32, color: border ?? Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _explanationCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final answerDisplay = Grader.display(question.answer);
    return Card(
      elevation: 0,
      color: cs.tertiaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_rounded, size: 18, color: cs.onTertiaryContainer),
                const SizedBox(width: 6),
                Text('解析',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onTertiaryContainer,
                        )),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.tertiary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('答案 $answerDisplay',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onTertiary,
                            fontWeight: FontWeight.bold,
                          )),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableAIText(
              text: question.explanation.isEmpty ? '暂无解析' : question.explanation,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onTertiaryContainer, height: 1.4),
              onExplain: (sel) => AIExplainSheet.show(context, selection: sel, question: question, submitted: submitted),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => AIExplainSheet.show(context, selection: question.stem, question: question, submitted: submitted),
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('AI 解析整题'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
