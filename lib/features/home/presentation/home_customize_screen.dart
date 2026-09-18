import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/ds_feature_header.dart';
import '../domain/home_layout.dart';

class HomeCustomizeScreen extends ConsumerWidget {
  const HomeCustomizeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(homeLayoutProvider);
    final notifier = ref.read(homeLayoutProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personalizar inicio'),
        actions: [
          TextButton(
            onPressed: notifier.reset,
            child: const Text('Restablecer'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const DsFeatureHeader(
            title: 'Módulos del inicio',
            subtitle: 'Arrastra para reordenar y usa los interruptores para mostrar u ocultar.',
            icon: Icons.dashboard_customize_rounded,
          ),
          const SizedBox(height: 12),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            // onReorderItem (the replacement) doesn't exist yet on older
            // stable SDKs; drop this ignore when the toolchain floor moves.
            // ignore: deprecated_member_use
            onReorder: notifier.reorder,
            children: [
              for (var i = 0; i < layout.order.length; i++)
                _ModuleTile(
                  key: ValueKey(layout.order[i]),
                  index: i,
                  module: layout.order[i],
                  visible: layout.isVisible(layout.order[i]),
                  onVisibility: (v) => notifier.setVisible(layout.order[i], v),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    super.key,
    required this.index,
    required this.module,
    required this.visible,
    required this.onVisibility,
  });

  final int index;
  final HomeModule module;
  final bool visible;
  final ValueChanged<bool> onVisibility;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(module.icon),
        title: Text(module.label, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: visible, onChanged: onVisibility),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.drag_handle_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
