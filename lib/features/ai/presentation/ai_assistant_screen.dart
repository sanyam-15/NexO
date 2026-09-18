import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_config.dart';
import '../domain/ai_assistant.dart';

/// The Asistente module: a chat grounded in the user's financial snapshot and
/// the active coaching persona.
class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    // Don't clear/drop the message while a reply is still in flight: send()
    // ignores input when state.sending is true, so the typed text would be lost.
    if (text.isEmpty || ref.read(aiAssistantProvider).sending) return;
    _input.clear();
    ref.read(aiAssistantProvider.notifier).send(text);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = ref.watch(aiReadyProvider);
    final state = ref.watch(aiAssistantProvider);

    ref.listen(aiAssistantProvider, (_, __) => _scrollToEnd());

    final itemCount = state.messages.length + (state.sending ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistente IA'),
        actions: [
          IconButton(
            tooltip: 'Limpiar conversación',
            onPressed: () => ref.read(aiAssistantProvider.notifier).clear(),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!ready)
            Material(
              color: theme.colorScheme.surfaceContainerHigh,
              child: ListTile(
                leading: const Icon(Icons.key_rounded),
                title: const Text('Configura la IA'),
                subtitle: const Text('Elige un proveedor en Ajustes → IA para chatear.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.pushNamed('ai-settings'),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              itemCount: itemCount,
              itemBuilder: (context, i) {
                if (state.sending && i == itemCount - 1) {
                  return const _Bubble(fromUser: false, child: _TypingDots());
                }
                final m = state.messages[i];
                return _Bubble(
                  fromUser: m.fromUser,
                  child: Text(
                    m.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: m.fromUser ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Pregúntale a tu asesor…',
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: state.sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromUser, required this.child});
  final bool fromUser;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(
          color: fromUser ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(fromUser ? 18 : 4),
            bottomRight: Radius.circular(fromUser ? 4 : 18),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _TypingDots extends StatelessWidget {
  const _TypingDots();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 36,
      height: 18,
      child: Center(
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
