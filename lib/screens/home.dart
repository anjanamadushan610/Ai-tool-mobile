import 'package:flutter/material.dart';

import '../i18n.dart';
import '../state.dart';
import 'account.dart';
import 'server.dart';
import 'tasks.dart';
import 'users.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final tabs = <(String, IconData, Widget)>[
      ('tasks', Icons.code, const TasksScreen()),
      if (s.can('admin.metrics')) ('server', Icons.monitor_heart_outlined, const ServerScreen()),
      if (s.can('admin.users')) ('users', Icons.group_outlined, const UsersScreen()),
      ('account', Icons.person_outline, const AccountScreen()),
    ];
    final i = _tab.clamp(0, tabs.length - 1);
    return Scaffold(
      appBar: AppBar(title: Text('${tr(context, 'app')} · ${tr(context, tabs[i].$1)}')),
      body: IndexedStack(index: i, children: [for (final t in tabs) t.$3]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => _tab = v),
        destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$2), label: tr(context, t.$1))],
      ),
    );
  }
}
