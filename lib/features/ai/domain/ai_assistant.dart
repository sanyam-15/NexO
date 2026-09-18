import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_config.dart';
import 'ai_context.dart';
import 'ai_mode.dart';

class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

const _greeting = ChatMessage(
  fromUser: false,
  text: '¡Hola! Soy tu asesor de Nexo. Pregúntame lo que quieras sobre tus finanzas: '
      'cuánto puedes gastar, cómo vas con tus metas, dónde recortar o cómo pagar una deuda.',
);

class AssistantState {
  const AssistantState({this.messages = const [_greeting], this.sending = false});
  final List<ChatMessage> messages;
  final bool sending;
}

/// The Asistente module: a conversational chat grounded in the user's
/// [FinancialSnapshot] and biased by the active [AiCoachMode] persona. History
/// lives in memory for the session (no persistence needed yet).
class AiAssistantController extends StateNotifier<AssistantState> {
  AiAssistantController(this.ref) : super(const AssistantState());
  final Ref ref;

  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty || state.sending) return;

    final asked = [...state.messages, ChatMessage(fromUser: true, text: t)];
    final client = ref.read(llmClientProvider);
    if (client == null) {
      state = AssistantState(messages: [
        ...asked,
        const ChatMessage(fromUser: false, text: 'Configura un proveedor de IA en Ajustes → IA para chatear.'),
      ]);
      return;
    }

    state = AssistantState(messages: asked, sending: true);

    final persona = ref.read(aiPersonaProvider);
    final snap = ref.read(financialSnapshotProvider);
    final recent = asked.length > 8 ? asked.sublist(asked.length - 8) : asked;
    final convo = recent.map((m) => '${m.fromUser ? "Usuario" : "Asesor"}: ${m.text}').join('\n');

    try {
      final reply = await client.complete(
        system: '$persona\n\n'
            'Responde preguntas del usuario sobre SUS finanzas con base en el resumen de '
            'abajo. Sé breve, concreto y directo (2-5 frases). Usa cifras del resumen cuando '
            'ayuden; si falta información, dilo en vez de inventar.\n\n${snap.toPromptText()}',
        userText: '$convo\nAsesor:',
        maxTokens: 800,
      );
      final clean = reply.trim();
      state = AssistantState(messages: [
        ...asked,
        ChatMessage(fromUser: false, text: clean.isEmpty ? '(sin respuesta)' : clean),
      ]);
    } catch (e) {
      state = AssistantState(messages: [
        ...asked,
        ChatMessage(fromUser: false, text: 'No pude responder: $e'),
      ]);
    }
  }

  void clear() => state = const AssistantState();
}

final aiAssistantProvider =
    StateNotifierProvider<AiAssistantController, AssistantState>((ref) => AiAssistantController(ref));
