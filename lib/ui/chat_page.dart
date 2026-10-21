import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/chat_client.dart';
import '../adapters/elizabeth_prompt.dart';
import 'chat_providers.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'theme.dart';

/// **The room she is in.**
///
/// A conversation rather than an assistant: the transcript is kept in this widget's state and forgotten when the page
/// closes, because storing a conversation is a different feature with its own disclosure, and nobody asked for it.
///
/// What is sent, on every turn, is the prompt and the transcript -- nothing about the cellar. That is the shape the
/// adapter disclosure promises, and it holds only for as long as this page keeps its hands off `cellarProvider`.
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  String _pending = '';
  String? _trouble;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    final settings = ref.read(chatSettingsProvider).value;
    if (settings == null || !settings.isConfigured) {
      setState(() => _trouble = 'needKey');
      return;
    }
    setState(() {
      _messages.add(ChatMessage.user(text));
      _input.clear();
      _busy = true;
      _trouble = null;
      _pending = '';
    });
    _follow();

    final endpoint = ChatEndpoint(
      baseUrl: settings.baseUrl,
      model: settings.model,
      apiKey: settings.apiKey,
    );
    final history = <ChatMessage>[
      const ChatMessage.system(elizabethSystemPrompt),
      ..._messages,
    ];
    try {
      await for (final piece in const ChatClient().stream(endpoint, history)) {
        if (!mounted) return;
        setState(() => _pending += piece);
        _follow();
      }
      if (!mounted) return;
      setState(() {
        if (_pending.isNotEmpty) _messages.add(ChatMessage.assistant(_pending));
        _pending = '';
        _busy = false;
      });
    } on ChatFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _pending = '';
        _busy = false;
        _trouble = switch (failure.trouble) {
          ChatTrouble.notConfigured => 'needKey',
          ChatTrouble.unauthorised => 'unauthorised',
          ChatTrouble.refused => 'refused',
          ChatTrouble.unreachable => 'unreachable',
        };
      });
    }
  }

  void _follow() {
    // The transcript grows downward, so "stick to the newest" is the bottom of the extent. Posted rather than called
    // directly: during a stream the list has not been laid out for the new text yet, and scrolling to a stale extent
    // just stops one line short every time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  CopyLine? _troubleLine() => switch (_trouble) {
        'needKey' => Copy.chatNeedKey,
        'unauthorised' => Copy.chatTroubleUnauthorised,
        'refused' => Copy.chatTroubleRefused,
        'unreachable' => Copy.chatTroubleUnreachable,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final trouble = _troubleLine();
    return Scaffold(
      appBar: AppBar(title: DualCopyText(Copy.chatTitle, style: HollowType.title)),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && _pending.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: DualCopyText(Copy.chatEmpty, style: HollowType.caption),
                    ),
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    children: [
                      for (final message in _messages) _Bubble(message: message),
                      if (_pending.isNotEmpty) _Bubble(message: ChatMessage.assistant(_pending)),
                      if (_busy && _pending.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )),
                        ),
                    ],
                  ),
          ),
          if (trouble != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: DualCopyText(
                trouble,
                style: HollowType.caption.copyWith(color: HollowPalette.rose),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('chat-input'),
                      controller: _input,
                      style: HollowType.body,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(hintText: ref.copy(Copy.chatPlaceholder)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('chat-send'),
                    onPressed: _busy ? null : _send,
                    child: DualCopyText(Copy.chatSend, style: HollowType.body),
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

/// One turn, drawn on the side it belongs to.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.role == ChatRole.user;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: mine ? HollowPalette.gold.withValues(alpha: 0.16) : HollowPalette.ink.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.text,
          style: HollowType.body.copyWith(color: HollowPalette.ink),
        ),
      ),
    );
  }
}
