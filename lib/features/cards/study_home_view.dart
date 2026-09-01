// M3: Card, FilterChip, PageView, MenuAnchor, NavigationBar via app.dart
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../core/topic_progress.dart';
import '../ai/ai_explain_sheet.dart';
import '../quiz/quiz_session_view.dart';
import 'card_content_parser.dart';
import 'card_content_view.dart';
import 'card_reading_service.dart';

/// StudyHomeView: list 17 modules. Each card navigates to StudyCardDetailView
/// which supports PageView pagination, MenuAnchor dropdown for 17 modules,
/// related question jump, optional card favorite. Uses Card, FilterChip.
class StudyHomeView extends ConsumerStatefulWidget {
  const StudyHomeView({super.key});

  @override
  ConsumerState<StudyHomeView> createState() => _StudyHomeViewState();
}

class _StudyHomeViewState extends ConsumerState<StudyHomeView> {
  TopicStatus? _filterStatus; // null = all
  bool _onlyFavorite = false;

  @override
  Widget build(BuildContext context) {
    final modulesAsync = ref.watch(allStudyModulesProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('速记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => _showSearch(context),
          ),
        ],
      ),
      body: modulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (modules) {
          final allCards = modules.expand((m) => m.cards).toList();
          final filteredModules = _applyFilter(modules);

          return Column(
            children: [
              _filterChips(context),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text('${allCards.length} 张卡片 · ${modules.length} 模块',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const Spacer(),
                    Text('${filteredModules.fold(0, (s, m) => s + m.cards.length)} 已筛选',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.primary)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: filteredModules.isEmpty
                    ? Center(child: Text('无匹配卡片', style: TextStyle(color: cs.onSurfaceVariant)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        itemCount: filteredModules.length,
                        itemBuilder: (context, modIndex) {
                          final mod = filteredModules[modIndex];
                          return _moduleSection(context, mod, modules);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<StudyModule> _applyFilter(List<StudyModule> modules) {
    if (_filterStatus == null && !_onlyFavorite) return modules;
    return modules
        .map((m) {
          final filtered = m.cards.where((c) {
            if (_onlyFavorite && !c.isFavorite) return false;
            if (_filterStatus != null && TopicStatusX.fromRaw(c.storedStatusRaw) != _filterStatus) return false;
            return true;
          }).toList();
          return StudyModule(id: m.id, name: m.name, order: m.order, cards: filtered);
        })
        .where((m) => m.cards.isNotEmpty)
        .toList();
  }

  Widget _filterChips(BuildContext context) {
    final filters = <Widget>[
      FilterChip(
        label: const Text('全部'),
        selected: _filterStatus == null && !_onlyFavorite,
        onSelected: (_) => setState(() {
          _filterStatus = null;
          _onlyFavorite = false;
        }),
      ),
      FilterChip(
        label: const Text('未学'),
        selected: _filterStatus == TopicStatus.new_,
        onSelected: (_) => setState(() => _filterStatus = _filterStatus == TopicStatus.new_ ? null : TopicStatus.new_),
      ),
      FilterChip(
        label: const Text('学习中'),
        selected: _filterStatus == TopicStatus.learning,
        onSelected: (_) => setState(() => _filterStatus = _filterStatus == TopicStatus.learning ? null : TopicStatus.learning),
      ),
      FilterChip(
        label: const Text('已通过'),
        selected: _filterStatus == TopicStatus.passed,
        onSelected: (_) => setState(() => _filterStatus = _filterStatus == TopicStatus.passed ? null : TopicStatus.passed),
      ),
      FilterChip(
        label: const Text('已毕业'),
        selected: _filterStatus == TopicStatus.graduated,
        onSelected: (_) => setState(() => _filterStatus = _filterStatus == TopicStatus.graduated ? null : TopicStatus.graduated),
      ),
      FilterChip(
        label: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.star_rounded, size: 14), SizedBox(width: 4), Text('收藏')]),
        selected: _onlyFavorite,
        onSelected: (v) => setState(() => _onlyFavorite = v),
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: filters.map((w) => Padding(padding: const EdgeInsets.only(right: 8), child: w)).toList()),
    );
  }

  Widget _moduleSection(BuildContext context, StudyModule mod, List<StudyModule> allModules) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('${mod.order}', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(mod.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Chip(label: Text('${mod.cards.length} 卡'), visualDensity: VisualDensity.compact),
            ],
          ),
        ),
        ...mod.cards.map((card) => _cardTile(context, card: card, module: mod, allModules: allModules)),
      ],
    );
  }

  Widget _cardTile(BuildContext context, {required StudyCard card, required StudyModule module, required List<StudyModule> allModules}) {
    final cs = Theme.of(context).colorScheme;
    final status = TopicStatusX.fromRaw(card.storedStatusRaw);
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case TopicStatus.new_:
        statusColor = cs.outline;
        statusIcon = Icons.circle_outlined;
        break;
      case TopicStatus.learning:
        statusColor = Colors.orange;
        statusIcon = Icons.auto_stories_rounded;
        break;
      case TopicStatus.passed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        break;
      case TopicStatus.graduated:
        statusColor = cs.primary;
        statusIcon = Icons.workspace_premium_rounded;
        break;
    }

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => StudyCardDetailView(
              initialCard: card,
              allModules: allModules,
            ),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(statusIcon, color: statusColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(card.content.replaceAll('\n', ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                          child: Text(status.displayName, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Text('${card.relatedQuestionIds.length} 题',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                        if (card.isFavorite) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade600),
                        ],
                        const Spacer(),
                        if (card.nextReviewDate != null && status == TopicStatus.passed)
                          Text(_fmtDate(card.nextReviewDate!),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.month}/${d.day} 复习';

  void _showSearch(BuildContext context) {
    showSearch(context: context, delegate: _CardSearchDelegate(allModulesProvider: allStudyModulesProvider, ref: ref));
  }
}

// ---------------------------------------------------------------------------
// Detail view with pagination (PageView) + MenuAnchor dropdown + favorite + question jump
// ---------------------------------------------------------------------------
class StudyCardDetailView extends ConsumerStatefulWidget {
  final StudyCard initialCard;
  final List<StudyModule> allModules;

  const StudyCardDetailView({super.key, required this.initialCard, required this.allModules});

  @override
  ConsumerState<StudyCardDetailView> createState() => _StudyCardDetailViewState();
}

class _StudyCardDetailViewState extends ConsumerState<StudyCardDetailView> {
  late List<StudyCard> _flatCards;
  late int _currentIndex;
  late PageController _pageController;
  StudyModule? _selectedModule; // for MenuAnchor filter
  late final CardReadingService _tts;
  bool _continuous = false;
  String? _playingCardId;
  bool _resumeChecked = false;
  bool _playingExplanations = false;

  @override
  void initState() {
    super.initState();
    _tts = CardReadingService();
    _tts.addListener(_onTtsTick);
    _flatCards = widget.allModules.expand((m) => m.cards).toList();
    _flatCards.sort((a, b) {
      final ao = a.module?.order ?? a.order;
      final bo = b.module?.order ?? b.order;
      if (ao != bo) return ao.compareTo(bo);
      return a.order.compareTo(b.order);
    });
    _currentIndex = _flatCards.indexWhere((c) => c.cardId == widget.initialCard.cardId);
    if (_currentIndex < 0) _currentIndex = 0;
    _pageController = PageController(initialPage: _currentIndex);
  }

  void _onTtsTick() {
    if (mounted) setState(() {});
    // 持久化断点（每 tick debounce）
    if (_tts.isPlaying && _playingCardId != null) {
      CardReadingService.saveResume(cardId: _playingCardId!, index: _tts.currentIndex);
    }
    // 连续播放：本卡读完自动进下一卡，全部卡读完则播关联题解析
    if (!_tts.isPlaying && _continuous && _playingCardId != null) {
      final finishedNaturally = _tts.currentIndex >= _tts.texts.length && _tts.texts.isNotEmpty;
      if (!finishedNaturally) return; // 手动暂停不自动翻页
      if (_playingExplanations) {
        _playingExplanations = false;
        _continuous = false;
        _playingCardId = null;
        CardReadingService.clearResume();
        return;
      }
      final visible = _visibleCards;
      final idx = visible.indexWhere((c) => c.cardId == _playingCardId);
      if (idx != -1 && idx < visible.length - 1) {
        final next = visible[idx + 1];
        _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
        Future.delayed(const Duration(milliseconds: 320), () {
          if (!mounted || !_continuous) return;
          _currentIndex = idx + 1;
          _startCardTts(next);
        });
      } else if (idx == visible.length - 1) {
        _playQuestionExplanations(visible[idx]);
      }
    }
  }

  Future<void> _startCardTts(StudyCard card, {int startIndex = 0}) async {
    final texts = CardContentParser.cleanedTexts(card.content);
    if (texts.isEmpty) return;
    _playingCardId = card.cardId;
    _continuous = true;
    _playingExplanations = false;
    await _tts.play(texts, startIndex: startIndex);
  }

  Future<void> _playQuestionExplanations(StudyCard card) async {
    if (card.relatedQuestionIds.isEmpty) {
      _continuous = false;
      _playingCardId = null;
      _playingExplanations = false;
      await CardReadingService.clearResume();
      return;
    }
    _playingExplanations = true;
    try {
      final db = ref.read(appDatabaseProvider);
      final rows = await db.allQuestions;
      final byId = {for (final r in rows) r.id: r};
      final exps = <String>[];
      for (final id in card.relatedQuestionIds) {
        final row = byId[id];
        if (row == null) {
          continue;
        }
        final exp = row.explanation.trim();
        final stem = row.stem.trim();
        if (exp.isNotEmpty) {
          exps.add('题目 $id 解析：$exp');
        } else if (stem.isNotEmpty) {
          exps.add('题目 $id：$stem');
        }
      }
      if (exps.isEmpty) {
        _continuous = false;
        await CardReadingService.clearResume();
        return;
      }
      _playingCardId = card.cardId; // 复用同卡Id标识解析段
      await _tts.play(exps);
    } catch (_) {
      _continuous = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_resumeChecked) {
      _resumeChecked = true;
      _checkResume();
    }
  }

  Future<void> _checkResume() async {
    final resume = await CardReadingService.loadResume();
    if (resume == null || !mounted) return;
    final flat = _flatCards;
    final match = flat.indexWhere((c) => c.cardId == resume.cardId);
    if (match == -1) return;
    // 仅当断点卡与当前首卡同模块或可见时提示
    final visibleIds = _visibleCards.map((c) => c.cardId).toSet();
    if (!visibleIds.contains(resume.cardId)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('检测到上次朗读断点（第 ${resume.index + 1} 段），是否续播？'),
      action: SnackBarAction(label: '续播', onPressed: () {
        final card = flat.firstWhere((c) => c.cardId == resume.cardId);
        final idx = _visibleCards.indexWhere((c) => c.cardId == card.cardId);
        if (idx != -1) {
          _pageController.jumpToPage(idx);
          setState(() => _currentIndex = idx);
          _startCardTts(card, startIndex: resume.index);
        }
      }),
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  void dispose() {
    _tts.removeListener(_onTtsTick);
    _tts.dispose();
    _pageController.dispose();
    super.dispose();
  }

  List<StudyCard> get _visibleCards {
    if (_selectedModule == null) return _flatCards;
    return _flatCards.where((c) => c.module?.id == _selectedModule!.id).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = _visibleCards;
    // keep current index in range
    if (visible.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('速记详情')), body: const Center(child: Text('无卡片')));
    }
    // If filter changes, we need to recalc current
    final currentCard = visible[_currentIndex.clamp(0, visible.length - 1)];

    return Scaffold(
      appBar: AppBar(
        title: Text(currentCard.title),
        actions: [
          // TTS 卡朗读（连续/断点）
          IconButton(
            icon: Icon(_tts.isPlaying ? Icons.pause_circle_filled_rounded : Icons.record_voice_over_rounded),
            tooltip: _tts.isPlaying ? '暂停朗读（保留断点）' : '朗读本卡（连续）',
            onPressed: () async {
              if (_tts.isPlaying) {
                _continuous = false;
                await _tts.pause();
                // 暂停保留断点，不清除
                if (_playingCardId != null) {
                  await CardReadingService.saveResume(cardId: _playingCardId!, index: _tts.currentIndex);
                }
              } else {
                // 若当前卡与断点同卡且未播过，尝试续播
                final resume = await CardReadingService.loadResume();
                int start = 0;
                if (resume != null && resume.cardId == currentCard.cardId) {
                  start = resume.index;
                  // 若已播完则从头
                  final total = CardContentParser.cleanedTexts(currentCard.content).length;
                  if (start >= total) start = 0;
                }
                final texts = CardContentParser.cleanedTexts(currentCard.content);
                if (texts.isEmpty) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本卡无可朗读内容')));
                  return;
                }
                await _startCardTts(currentCard, startIndex: start);
              }
            },
          ),
          // MenuAnchor dropdown for 17 modules
          MenuAnchor(
            builder: (context, controller, child) => IconButton(
              icon: const Icon(Icons.category_rounded),
              onPressed: () => controller.isOpen ? controller.close() : controller.open(),
            ),
            menuChildren: [
              MenuItemButton(
                onPressed: () async {
                  _continuous = false;
                  _playingExplanations = false;
                  _playingCardId = null;
                  await CardReadingService.clearResume();
                  if (_tts.isPlaying) await _tts.stop();
                  setState(() {
                    _selectedModule = null;
                    _currentIndex = 0;
                    _pageController.jumpToPage(0);
                  });
                },
                child: Text('全部模块 (${_flatCards.length})', style: TextStyle(fontWeight: _selectedModule == null ? FontWeight.bold : FontWeight.normal)),
              ),
              ...widget.allModules.map((m) => MenuItemButton(
                    onPressed: () async {
                      _continuous = false;
                      _playingExplanations = false;
                      _playingCardId = null;
                      await CardReadingService.clearResume();
                      if (_tts.isPlaying) await _tts.stop();
                      final old = _pageController;
                      setState(() {
                        _selectedModule = m;
                        _currentIndex = 0;
                        _pageController = PageController(initialPage: 0);
                      });
                      old.dispose();
                    },
                    child: Text('${m.name} (${m.cards.length})',
                        style: TextStyle(fontWeight: _selectedModule?.id == m.id ? FontWeight.bold : FontWeight.normal)),
                  )),
            ],
          ),
          Consumer(builder: (context, ref, _) {
            return IconButton(
              icon: Icon(currentCard.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: currentCard.isFavorite ? Colors.amber : null),
              onPressed: () async {
                final next = !currentCard.isFavorite;
                setState(() => currentCard.isFavorite = next);
                try {
                  final db = ref.read(appDatabaseProvider);
                  await (db.update(db.studyCards)..where((t) => t.cardId.equals(currentCard.cardId))).write(
                    StudyCardsCompanion(isFavorite: drift.Value(next)),
                  );
                  ref.invalidate(allStudyCardsProvider);
                  ref.invalidate(allStudyModulesProvider);
                } catch (_) {}
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next ? '已收藏' : '已取消收藏')));
                }
              },
            );
          }),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: visible.length > 1 ? (_currentIndex + 1) / visible.length : 1,
            backgroundColor: cs.surfaceContainerHighest,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Chip(
                  label: Text(currentCard.module?.name ?? '通用'),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Text('${_currentIndex + 1} / ${visible.length}', style: Theme.of(context).textTheme.labelSmall),
                const Spacer(),
                Text(TopicStatusX.fromRaw(currentCard.storedStatusRaw).displayName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: visible.length,
              onPageChanged: (i) async {
                // 手动翻页：停止连续但保留断点（若是连续播放中，则视为中断，不自动续）
                if (_tts.isPlaying) {
                  _continuous = false;
                  await _tts.stop();
                }
                setState(() => _currentIndex = i);
              },
              itemBuilder: (context, index) {
                final card = visible[index];
                // highlightIndex is driven by TTS currentIndex when this card is the current one
                return ListenableBuilder(
                  listenable: _tts,
                  builder: (context, _) {
                    final hl = (index == _currentIndex && _tts.isPlaying) ? _tts.currentIndex : null;
                    return _cardPage(context, card, hl);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _currentIndex > 0 ? () => _pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('上一张'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => QuizSessionView(
                        questionIds: cardRelatedIds(currentCard),
                        title: currentCard.title,
                        sourceRaw: 'cardJump',
                      ),
                    ));
                  },
                  icon: const Icon(Icons.quiz_rounded),
                  label: Text('练习 ${cardRelatedIds(currentCard).length} 题'),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _currentIndex < visible.length - 1 ? () => _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('下一张'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<int> cardRelatedIds(StudyCard c) => c.relatedQuestionIds;

  Widget _cardPage(BuildContext context, StudyCard card, int? highlightIndex) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          color: cs.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Divider(color: cs.outlineVariant),
                const SizedBox(height: 12),
                CardContentView(
                  content: card.content,
                  highlightIndex: highlightIndex,
                  onExplain: (sel) => AIExplainSheet.show(context, selection: sel, cardTitle: card.title, cardContent: card.content),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.quiz_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 6),
                    Text('关联题目 ${card.relatedQuestionIds.length}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => QuizSessionView(questionIds: card.relatedQuestionIds, title: card.title, sourceRaw: 'cardJump'),
                        ));
                      },
                      child: const Text('去练习 >'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: card.relatedQuestionIds.take(20).map((id) => Chip(label: Text('#$id'), visualDensity: VisualDensity.compact)).toList(),
                ),
                if (card.relatedQuestionIds.length > 20) Text('...等 ${card.relatedQuestionIds.length} 题', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // optional card favorite toggle card
        Card(
          elevation: 0,
          color: cs.secondaryContainer.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.lightbulb_rounded, color: cs.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(child: Text('掌握技巧：先理解卡片内容，再通过关联题目巩固。答对本题卡片相关的全部题目即视为掌握，进入 7 天巩固周期。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSecondaryContainer))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CardSearchDelegate extends SearchDelegate<StudyCard?> {
  final FutureProvider<List<StudyModule>> allModulesProvider;
  final WidgetRef ref;
  _CardSearchDelegate({required this.allModulesProvider, required this.ref});
  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => query = '')];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => close(context, null));
  @override
  Widget buildResults(BuildContext context) => _list(context);
  @override
  Widget buildSuggestions(BuildContext context) => _list(context);
  Widget _list(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final async = ref.watch(allModulesProvider);
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error $e')),
        data: (mods) {
          final all = mods.expand((m) => m.cards).where((c) => query.isEmpty || c.title.toLowerCase().contains(query.toLowerCase()) || c.content.toLowerCase().contains(query.toLowerCase())).take(50).toList();
          if (all.isEmpty) return const Center(child: Text('无结果'));
          return ListView.builder(
            itemCount: all.length,
            itemBuilder: (context, i) {
              final c = all[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  title: Text(c.title),
                  subtitle: Text(c.content, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    close(context, c);
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudyCardDetailView(initialCard: c, allModules: mods)));
                  },
                ),
              );
            },
          );
        },
      );
    });
  }
}


