import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/cellar_tools.dart';
import '../adapters/proposed_writes.dart';
import '../adapters/chat_client.dart';
import '../adapters/elizabeth_prompt.dart';
import '../adapters/web_search.dart';
import '../data/chat_actions.dart';
import '../data/chat_settings.dart';
import '../data/image_picker_channel.dart';
import '../domain/events/ingredient_authoring.dart';
import '../domain/events/recipe_authoring.dart';
import '../domain/events/stock.dart';
import '../domain/model/ingredient.dart';
import '../domain/model/recipe.dart';
import '../domain/units/quantity.dart';
import 'chat_providers.dart';
import '../adapters/registry.dart';
import 'adapters_providers.dart';
import 'library.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy.dart';
import 'photo_capture_page.dart';
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
  /// The photograph waiting to be sent with the next message.
  Uint8List? _attachment;

  /// **What she wants recorded, and has not recorded.** The proposal is shown and the reader decides; nothing is
  /// written until they press the button, which is the rule `cellar_tools.dart` exists to keep.
  PendingChange? _proposal;
  bool _proposalApplied = false;
  String? _trouble;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // **The transcript comes back, because the owner asked for it on 2026-10-22.** Read once, at the start; written
    // after every turn rather than on the way out, because a page that is killed has no way out to write on.
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final store = await ref.read(chatHistoryProvider.future);
    final stored = await store.read();
    if (!mounted || stored.isEmpty) return;
    setState(() => _messages.addAll(stored));
    _follow();
  }

  Future<void> _persist() async {
    final store = await ref.read(chatHistoryProvider.future);
    await store.write(_messages);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    // **A photograph with no words is still a question.** Requiring a sentence to attach a picture meant the one
    // gesture a reader makes with a bottle in hand -- point, and say nothing -- was the one gesture refused.
    if ((text.isEmpty && _attachment == null) || _busy) return;
    // **The switch is the consent, and it is asked before anything else.** A key in a field is not permission to
    // send the cellar anywhere; the adapter card in the settings is where that permission is given, and this is the
    // one place that reads it.
    if (!ref.read(adapterRegistryProvider).isEnabled(AdapterKind.chatModel)) {
      setState(() => _trouble = 'needSwitch');
      return;
    }
    // **Awaited, not read.** The first version took `.value`, which is null until the file has been read -- so a
    // reader who opened the conversation and typed at once was told "no key yet" about a key that was already stored.
    // The owner reported exactly that on 2026-10-22: it worked only after visiting the settings page first, because
    // visiting it gave the read time to finish. Waiting for the future is the fix; there is nothing to cache.
    ChatSettings settings;
    try {
      settings = await ref.read(chatSettingsProvider.future);
    } on Exception {
      settings = const ChatSettings();
    }
    if (!settings.isConfigured) {
      setState(() => _trouble = 'needKey');
      return;
    }
    final attachment = _attachment;
    setState(() {
      _messages.add(ChatMessage.user(text, image: attachment));
      _input.clear();
      _attachment = null;
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
    // **What she is allowed to look at, gathered at the moment she is asked.** The ledger rather than a copy of it:
    // the volumes she reads are the volumes the screen shows. No write tool exists -- see `cellar_tools.dart` for why
    // that is a decision and not an omission.
    final cellar = ref.read(cellarProvider).value;
    final seed = ref.read(seedProvider).value;
    final box = CellarToolBox(
      stock: cellar?.stock.bottles ?? const <BottleState>[],
      // **The names, not just the ids.** She was reading the ledger alone and saying 「gin · 700 ml · id: gin」; a
      // reader asking what they can make wants the library's name for it, which is what the seed already holds.
      ingredients: seed?.ingredients ?? const <Ingredient>[],
      recipes: seed?.recipes ?? const <Recipe>[],
    );
    final history = <ChatMessage>[
      const ChatMessage.system(elizabethSystemPrompt),
      ..._messages,
    ];
    try {
      await for (final piece in const ChatClient().converse(
        endpoint,
        history,
        tools: CellarToolBox.tools,
        runTool: (call) async {
          // **The line goes down before the work, and is filled in after it.** A call that never returns still leaves
          // evidence that it was attempted, which is the only thing an action log is worth anything for.
          final store = await ref.read(chatActionsProvider.future);
          final index = await store.start(ChatAction(
            at: DateTime.now(),
            tool: call.name,
            arguments: call.arguments,
          ));
          final answer = await box.run(
            call,
            search: (query) => const DeepSeekSearch().search(endpoint, query),
            propose: (proposal) {
              if (mounted) {
                setState(() {
                  _proposal = proposal;
                  _proposalApplied = false;
                });
              }
            },
          );
          await store.settle(index, answer);
          return answer;
        },
      )) {
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
      unawaited(_persist());
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

  /// **The card, and the only place a write happens.** Two buttons: one records through the same `addBottle` the
  /// stock form uses, the other drops the proposal. There is no third path, and no path where the model writes.
  Widget _proposalCard(PendingChange proposal) {
    // What it is, and what it is about. A bottle id is not a name, so the seed is asked before the id is shown.
    final (CopyLine verb, String subject) = switch (proposal) {
      AddBottle(:final sku) => (
          Copy.chatProposalHeading,
          '${ref.read(seedProvider).value?.ingredients.where((i) => i.id == sku).map((i) => i.name).firstOrNull ?? sku} · ${proposal.millilitres} ml',
        ),
      RecountBottle(:final bottleId) => (Copy.chatProposalRecount, '$bottleId · ${proposal.millilitres} ml'),
      DiscardBottle(:final bottleId) => (Copy.chatProposalDiscard, '$bottleId · ${proposal.millilitres} ml'),
      NewIngredient(:final name, :final category) => (
          Copy.chatProposalIngredient,
          category == null ? name : '$name · $category',
        ),
      RenameBottle(:final bottleId, :final name) => (Copy.chatProposalRenameBottle, '$bottleId → $name'),
      RenameIngredient(:final ingredientId, :final name) => (Copy.chatProposalRenameIngredient, '$ingredientId → $name'),
      NewRecipe(:final name, :final items) => (
          Copy.chatProposalRecipe,
          '$name · ${items.map((item) => '${item.amount}${item.unit == null ? '' : ' ${item.unit}'} ${item.ingredientId}').join(' + ')}',
        ),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: HollowPalette.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DualCopyText(verb, style: HollowType.caption),
          const SizedBox(height: 4),
          Text(subject, style: HollowType.body.copyWith(color: HollowPalette.ink)),
          const SizedBox(height: 6),
          Row(
            children: [
              if (_proposalApplied)
                DualCopyText(Copy.chatProposalDone, style: HollowType.caption.copyWith(color: HollowPalette.gold))
              else ...[
                FilledButton(
                  key: const ValueKey('proposal-apply'),
                  onPressed: () async {
                    final notifier = ref.read(cellarProvider.notifier);
                    await applyWrite(writeFor(proposal), notifier);
                    if (mounted) {
                      setState(() {
                        _proposalApplied = true;
                        _proposal = null;
                      });
                    }
                  },
                  child: DualCopyText(Copy.chatProposalApply, style: HollowType.body),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey('proposal-dismiss'),
                  onPressed: () => setState(() => _proposal = null),
                  child: DualCopyText(Copy.chatProposalDismiss, style: HollowType.body),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  CopyLine? _troubleLine() => switch (_trouble) {
        'needSwitch' => Copy.chatNeedSwitch,
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
          if (_proposal case final proposal?) _proposalCard(proposal),
          // **What is attached, said before it is sent.** The first version kept it in state and showed nothing,
          // so a reader who picked a photograph had no way to know it had been picked -- and no way to take it back.
          if (_attachment != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(
                children: [
                  const Icon(Icons.image_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DualCopyText(Copy.chatPhotoAttached, style: HollowType.caption),
                  ),
                  IconButton(
                    key: const ValueKey('chat-detach'),
                    onPressed: () => setState(() => _attachment = null),
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: null,
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
                  // **Only where the system picker exists.** A button that opens nothing on two of the three
                  // platforms is the thing the 2026-09-25 rule forbids.
                  if (canPickFromLibrary)
                    IconButton(
                      key: const ValueKey('chat-pick'),
                      onPressed: _busy
                          ? null
                          : () async {
                              final bytes = await pickPictureFromLibrary();
                              if (bytes == null || !mounted) return;
                              setState(() => _attachment = bytes);
                            },
                      icon: const Icon(Icons.photo_library_outlined, size: 22),
                      tooltip: null,
                    ),
                  IconButton(
                    key: const ValueKey('chat-attach'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final bytes = await takePhoto(context);
                            if (bytes == null || !mounted) return;
                            setState(() => _attachment = bytes);
                          },
                    icon: const Icon(Icons.photo_camera_outlined, size: 22),
                    tooltip: null,
                  ),
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
          plainReply(message.text),
          style: HollowType.body.copyWith(color: HollowPalette.ink),
        ),
      ),
    );
  }
}

/// Perform the write a proposal became.
///
/// The proposal-to-write mapping lives in `proposed_writes.dart`, where a test can read it back; this
/// only says which method on the cellar each write names. Splitting them is what makes the mapping
/// checkable at all -- in one switch behind a provider and a pump, a case wired to the wrong method
/// looked exactly like a case wired correctly.
Future<void> applyWrite(CellarWrite write, CellarNotifier notifier) async {
  switch (write) {
    case WriteAddBottle(:final sku, :final millilitres):
      await notifier.addBottle(sku: sku, volume: Volume.fromMillilitres(millilitres));
    case WriteRecountBottle(:final bottleId, :final millilitres):
      await notifier.recountBottle(bottleId, Volume.fromMillilitres(millilitres));
    case WriteDiscardBottle(:final bottleId, :final millilitres):
      await notifier.discardBottle(bottleId, Volume.fromMillilitres(millilitres));
    case WriteRenameBottle(:final bottleId, :final name):
      await notifier.renameBottle(bottleId, name);
    case WriteRenameIngredient(:final ingredientId, :final name):
      await notifier.renameIngredient(ingredientId, name);
    case WriteAuthorRecipe(:final name, :final items, :final method, :final glass):
      await notifier.authorRecipe(AuthoredRecipe(
        id: '',
        name: name,
        method: method,
        glass: glass,
        items: <AuthoredItem>[
          for (final item in items)
            AuthoredItem(ingredientId: item.ingredientId, amount: item.amount, unit: item.unit),
        ],
      ));
    case WriteAuthorIngredient(:final name, :final category):
      await notifier.authorIngredient(AuthoredIngredient(id: '', name: name, category: category));
  }
}

/// Take the Markdown out of a reply, because nothing here renders it.
///
/// The model answers in Markdown by habit and this transcript is a plain `Text`, so a reader was shown
/// `**成这样**` with the asterisks still in it. Two things are done about that: the prompt tells her not
/// to write it, and this removes the marks that arrive anyway. It strips rather than renders on purpose --
/// a Markdown renderer is a dependency, and a package-size argument already cost this application its
/// voice.
String plainReply(String text) {
  var out = text;

  // Fenced blocks: the content stays, the fence and its language tag go.
  out = out.replaceAll(RegExp(r'^```[^\n]*$', multiLine: true), '');
  // Inline code and every emphasis marker.
  out = out.replaceAll('`', '');
  out = out.replaceAll(RegExp(r'\*\*\*|___'), '');
  out = out.replaceAll(RegExp(r'\*\*|__'), '');
  out = out.replaceAll('*', '');
  // Headings and block quotes: the words are the content, the prefix is not.
  out = out.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  out = out.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  // A list keeps one mark, the one this interface already uses for a list.
  out = out.replaceAll(RegExp(r'^\s*[-+]\s+', multiLine: true), '\u00b7 ');
  // Table rules and pipes: the cells stay, the drawing goes.
  out = out.replaceAll(RegExp(r'^\s*\|?[-: ]+\|[-: |]*$', multiLine: true), '');
  out = out.replaceAll('|', ' ');
  // Links keep their words and lose their targets.
  out = out.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (match) => match[1] ?? '');
  // Whatever the removals left behind.
  out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return out.trim();
}
