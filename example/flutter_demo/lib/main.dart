import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'screens/rag_screen.dart';
import 'screens/flow_screen.dart';
import 'screens/escalation_screen.dart';

void main() => runApp(const GuardrailsDemoApp());

class GuardrailsDemoApp extends StatelessWidget {
  const GuardrailsDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Colors.teal;
    return MaterialApp(
      title: 'ai_guardrails Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String _locale = 'en';

  static const _localeLabels = {
    'en': 'English',
    'es': 'Español',
    'pt': 'Português',
    'fr': 'Français',
    'de': 'Deutsch',
    'it': 'Italiano',
    'ja': '日本語',
    'ko': '한국어',
    'zh': '中文',
    'ar': 'العربية',
    'hi': 'हिन्दी',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ai_guardrails Demo'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate),
            tooltip: 'Guard message language',
            initialValue: _locale,
            onSelected: (locale) => setState(() => _locale = locale),
            itemBuilder: (context) => [
              for (final entry in _localeLabels.entries)
                PopupMenuItem(
                  value: entry.key,
                  child: Text(
                    '${entry.value} (${entry.key})',
                    style: TextStyle(
                      fontWeight: entry.key == _locale ? FontWeight.bold : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          ChatScreen(locale: _locale),
          RagScreen(locale: _locale),
          FlowScreen(locale: _locale),
          EscalationScreen(locale: _locale),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.article), label: 'RAG'),
          NavigationDestination(icon: Icon(Icons.account_tree), label: 'Flow'),
          NavigationDestination(
              icon: Icon(Icons.trending_up), label: 'Session'),
        ],
      ),
    );
  }
}
