import 'package:flutter/material.dart';
import 'features/today/today_view.dart';
import 'features/practice/practice_view.dart';
import 'features/cards/study_home_view.dart';
import 'features/stats/stats_view.dart';
class QuizBankApp extends StatelessWidget {
  const QuizBankApp({super.key});

  static const _chineseFallback = [
    'Microsoft YaHei', // Windows 简中首选，解决日文字形回退
    'PingFang SC', // macOS
    'Hiragino Sans GB',
    'Noto Sans SC',
    'Source Han Sans SC',
    'Noto Sans CJK SC',
    'WenQuanYi Micro Hei',
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'QuizBank',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
          fontFamilyFallback: _chineseFallback,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange,
            brightness: Brightness.dark,
          ),
          fontFamilyFallback: _chineseFallback,
        ),
        home: const RootScaffold(),
      );
  }
}

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _index = 0;

  static const _pages = [
    TodayView(),
    PracticeView(),
    StudyHomeView(),
    StatsView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny), label: '今日'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: '刷题'),
          NavigationDestination(icon: Icon(Icons.lightbulb_outline), selectedIcon: Icon(Icons.lightbulb), label: '速记'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: '复盘'),
        ],
      ),
    );
  }
}
