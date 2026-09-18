import 'package:flutter/material.dart';

import 'ds_top_app_bar.dart';

class DsScreenScaffold extends StatelessWidget {
  const DsScreenScaffold({
    super.key,
    required this.title,
    required this.children,
    this.floatingActionButton,
    this.actions,
  });

  final String title;
  final List<Widget> children;
  final Widget? floatingActionButton;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: DsTopAppBar(title: title, actions: actions),
      floatingActionButton: floatingActionButton,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: children,
      ),
    );
  }
}
