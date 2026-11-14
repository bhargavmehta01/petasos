import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/hermes_mobile_theme.dart';
import 'w1_models.dart';

/// Native card for a sudo password, a secret, or a clarifying question.
/// Sensitive values live only in the text field and are cleared on submit.
class HermesMobilePromptCard extends StatefulWidget {
  const HermesMobilePromptCard({super.key, required this.prompt, required this.onAnswer});
  final HermesMobilePrompt prompt;
  final Future<void> Function(String value) onAnswer;

  @override
  State<HermesMobilePromptCard> createState() => _HermesMobilePromptCardState();
}

class _HermesMobilePromptCardState extends State<HermesMobilePromptCard> {
  final _field = TextEditingController();
  final Set<String> _picked = {};
  bool _busy = false;
  bool _reveal = false;

  @override
  void dispose() {
    _field.clear();
    _field.dispose();
    super.dispose();
  }

  Future<void> _submit([String? value, bool skip = false]) async {
    final p = widget.prompt;
    final answer =
        value ??
        (p.multiSelect && _picked.isNotEmpty
            ? [..._picked, if (_field.text.trim().isNotEmpty) _field.text.trim()]
                  .join(', ')
            : _field.text);
    if (!skip && answer.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    _field.clear();
    await widget.onAnswer(answer);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final p = widget.prompt;
    final icon = switch (p.kind) {
      HermesMobilePromptKind.sudo => Icons.admin_panel_settings_outlined,
      HermesMobilePromptKind.secret => Icons.key_outlined,
      HermesMobilePromptKind.clarify => Icons.help_outline_rounded,
    };
    final accent = p.isSensitive ? c.warning : c.accent;
    return Container(
      key: const ValueKey('hermes-mobile-prompt-card'),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(HermesMobileRadius.card),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        boxShadow: hermesMobileShadow(context),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(p.description, style: Theme.of(context).textTheme.bodyMedium),
          if (p.choices.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in p.choices)
                  p.multiSelect
                      ? FilterChip(
                          label: Text(choice),
                          selected: _picked.contains(choice),
                          onSelected: _busy
                              ? null
                              : (on) => setState(
                                  () => on
                                      ? _picked.add(choice)
                                      : _picked.remove(choice),
                                ),
                        )
                      : ActionChip(
                          label: Text(choice),
                          onPressed: _busy ? null : () => _submit(choice),
                        ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _field,
            enabled: !_busy,
            obscureText: p.isSensitive && !_reveal,
            enableSuggestions: !p.isSensitive,
            autocorrect: !p.isSensitive,
            keyboardType: p.isSensitive
                ? TextInputType.visiblePassword
                : TextInputType.text,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              isDense: true,
              hintText: switch (p.kind) {
                HermesMobilePromptKind.sudo => 'Sudo password',
                HermesMobilePromptKind.secret => 'Value (used once, not saved)',
                HermesMobilePromptKind.clarify =>
                  p.choices.isEmpty ? 'Your answer' : 'Or type an answer',
              },
              suffixIcon: p.isSensitive
                  ? IconButton(
                      tooltip: _reveal ? 'Hide' : 'Show',
                      icon: Icon(
                        _reveal
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _reveal = !_reveal),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (p.isSensitive)
                TextButton(
                  onPressed: _busy ? null : () => _submit('', true),
                  child: const Text('Skip'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : () => _submit(),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(p.isSensitive ? 'Send securely' : 'Answer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
