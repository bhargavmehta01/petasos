/// Pure helpers for Wave 4: commitment extraction, repeated-ask detection,
/// source and confidence chips, offline error detection and the dashboard
/// hand-off link. No Flutter imports so they are cheap to unit test.
library;

import '../../cards/blocks.dart';
import '../../data/models.dart';
import 'w4_models.dart';

// ── Commitments ──────────────────────────────────────────────────────────

final _agentPromise = RegExp(
  r"\b(I'll|I will|I'm going to|I am going to|I can remind you|I'll remind you|"
  r"I'll check|I'll follow up|I'll get back|I'll keep an eye|let me check back)\b"
  r"[^.!?\n]{3,160}[.!?]?",
  caseSensitive: false,
);

final _userPromise = RegExp(
  r"\b(remind me to|remind me about|don't let me forget to|I need to|"
  r"I have to|I promised to)\b[^.!?\n]{3,160}[.!?]?",
  caseSensitive: false,
);

const _weekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// Finds a due date in a phrase: today, tonight, tomorrow, a weekday, "in N
/// days/hours", "next week", "end of day". Returns null when there is none.
DateTime? parseDue(String text, DateTime now) {
  final t = text.toLowerCase();
  DateTime at(DateTime d, int hour) => DateTime(d.year, d.month, d.day, hour);
  final inN = RegExp(r'\bin (\d{1,2}) (minute|hour|day|week)s?\b').firstMatch(t);
  if (inN != null) {
    final n = int.parse(inN.group(1)!);
    return switch (inN.group(2)) {
      'minute' => now.add(Duration(minutes: n)),
      'hour' => now.add(Duration(hours: n)),
      'week' => now.add(Duration(days: 7 * n)),
      _ => now.add(Duration(days: n)),
    };
  }
  if (RegExp(r'\btonight\b').hasMatch(t)) return at(now, 20);
  if (RegExp(r'\b(end of (the )?day|eod|today|this afternoon)\b').hasMatch(t)) {
    return at(now, 17);
  }
  if (RegExp(r'\btomorrow\b').hasMatch(t)) {
    return at(now.add(const Duration(days: 1)), 9);
  }
  if (RegExp(r'\bnext week\b').hasMatch(t)) {
    final monday = now.add(Duration(days: 8 - now.weekday));
    return at(monday, 9);
  }
  if (RegExp(r'\b(this weekend|weekend)\b').hasMatch(t)) {
    final sat = now.add(Duration(days: (6 - now.weekday) % 7));
    return at(sat, 10);
  }
  for (var i = 0; i < _weekdays.length; i++) {
    if (RegExp('\\b${_weekdays[i]}\\b').hasMatch(t)) {
      var delta = (i + 1) - now.weekday;
      if (delta <= 0) delta += 7;
      return at(now.add(Duration(days: delta)), 9);
    }
  }
  return null;
}

String _clean(String s) {
  var out = s
      .replaceAll(RegExp(r'[*_`>#]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (out.endsWith('.') || out.endsWith('!')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

String _stableId(String chatId, String text) {
  var h = 0;
  for (final c in '$chatId|$text'.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return 'c$h';
}

/// Extracts promises from a transcript. Agent replies give agent-owned
/// commitments ("I'll check back Friday"); user messages give user-owned
/// ones ("remind me to call the bank tomorrow"). Code blocks are skipped.
List<HermesMobileCommitment> extractCommitments(
  List<HermesMobileMessage> messages, {
  required String chatId,
  String? chatTitle,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final out = <HermesMobileCommitment>[];
  final seen = <String>{};
  for (final m in messages) {
    final text = m.text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    final re = m.isUser ? _userPromise : _agentPromise;
    for (final match in re.allMatches(text)) {
      final sentence = _clean(match.group(0)!);
      if (sentence.length < 8) continue;
      final lower = sentence.toLowerCase();
      // Skip offers and questions: "I can … if you want", "Shall I …?".
      if (lower.contains('if you') ||
          lower.contains('would you') ||
          match.group(0)!.trim().endsWith('?')) {
        continue;
      }
      final key = lower;
      if (!seen.add(key)) continue;
      final due = parseDue(sentence, m.createdAt.isAfter(at) ? at : m.createdAt);
      var body = sentence;
      if (m.isUser) {
        body = body.replaceFirst(
          RegExp(r"^(remind me to|remind me about|don't let me forget to)\s*",
              caseSensitive: false),
          '',
        );
      }
      body = body.isEmpty ? sentence : body[0].toUpperCase() + body.substring(1);
      out.add(
        HermesMobileCommitment(
          id: _stableId(chatId, lower),
          text: body,
          owner: m.isUser ? CommitmentOwner.user : CommitmentOwner.agent,
          due: due,
          chatId: chatId,
          chatTitle: chatTitle,
          source: 'chat',
          quote: sentence,
        ),
      );
    }
  }
  return out;
}

// ── Repeated asks → watcher proposals ────────────────────────────────────

const _stop = {
  'the', 'a', 'an', 'is', 'are', 'what', 'whats', "what's", 'how', 'much',
  'does', 'do', 'did', 'of', 'for', 'to', 'in', 'on', 'my', 'me', 'i', 'it',
  'any', 'check', 'again', 'now', 'today', 'please', 'can', 'you', 'tell',
  'show', 'and', 'or', 'there', 'still', 'current', 'currently', 'latest',
  'with', 'about', 'at', 'be', 'this', 'that', 'get', 'see', 'has', 'have',
};

/// Words that signal the user is checking on something that changes.
final _checkingWords = RegExp(
  r'\b(price|cost|status|stock|available|availability|open|tracking|track|'
  r'delivered|shipped|score|rate|weather|update|news|release|back in|in stock|'
  r'deal|sale|drop|order|flight|delay|queue|wait)\b',
  caseSensitive: false,
);

Set<String> _keywords(String text) => {
  for (final w in text
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9$€£ ]"), ' ')
      .split(' '))
    if (w.length > 2 && !_stop.contains(w)) w,
};

/// Looks for the same "checking" question asked [minCount] or more times
/// across chats. [asks] is (chatId, text). Returns the strongest proposal.
WatcherProposal? proposeWatcher(
  List<MapEntry<String, String>> asks, {
  int minCount = 3,
  Set<String> dismissed = const {},
}) {
  final checking = [
    for (final a in asks)
      if (_checkingWords.hasMatch(a.value)) a,
  ];
  WatcherProposal? best;
  for (var i = 0; i < checking.length; i++) {
    final base = _keywords(checking[i].value);
    if (base.length < 2) continue;
    final group = <MapEntry<String, String>>[checking[i]];
    for (var j = 0; j < checking.length; j++) {
      if (i == j) continue;
      final other = _keywords(checking[j].value);
      final overlap = base.intersection(other).length;
      final union = base.union(other).length;
      if (union > 0 && overlap >= 2 && overlap / union >= 0.4) {
        group.add(checking[j]);
      }
    }
    if (group.length < minCount) continue;
    final topic = _topicOf(group.map((e) => e.value).toList());
    if (dismissed.contains(topic.toLowerCase())) continue;
    if (best == null || group.length > best.count) {
      best = WatcherProposal(
        topic: topic,
        count: group.length,
        chatIds: {for (final g in group) g.key}.toList(),
      );
    }
  }
  return best;
}

String _topicOf(List<String> texts) {
  final counts = <String, int>{};
  for (final t in texts) {
    for (final w in _keywords(t)) {
      counts[w] = (counts[w] ?? 0) + 1;
    }
  }
  final common = counts.entries.where((e) => e.value >= texts.length - 1).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final words = common.take(4).map((e) => e.key).toList();
  // Keep the words in the order they appear in the shortest question.
  final shortest = texts.reduce((a, b) => a.length <= b.length ? a : b);
  final order = shortest.toLowerCase();
  words.sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
  final topic = words.join(' ');
  return topic.isEmpty ? shortest : topic[0].toUpperCase() + topic.substring(1);
}

// ── Confidence and source chips ─────────────────────────────────────────

enum ConfidenceLevel { high, medium, low }

class ReplyProvenance {
  const ReplyProvenance({
    this.sources = const [],
    this.confidence,
    this.tools = const [],
    this.fromMemory = false,
  });
  final List<LinkRef> sources;
  final ConfidenceLevel? confidence;
  final List<String> tools;
  final bool fromMemory;

  bool get isEmpty =>
      sources.isEmpty && confidence == null && tools.isEmpty && !fromMemory;
}

final _confidenceLine = RegExp(
  r'^\s*[*_]*confidence[*_]*\s*[:\-–]\s*[*_]*(high|medium|moderate|low)\b',
  caseSensitive: false,
  multiLine: true,
);

final _hedges = RegExp(
  r"\b(I'm not sure|I am not sure|I couldn't verify|could not verify|"
  r"unverified|might be wrong|I think|probably|likely|uncertain|"
  r"I don't have (?:live|current|real-time))\b",
  caseSensitive: false,
);

const _webTools = {
  'web_search',
  'web_extract',
  'browser',
  'browser_navigate',
  'fetch',
  'search',
};

/// Reads where a reply came from: its links, an explicit "Confidence: high"
/// line, hedging words, and the tools that ran before it.
ReplyProvenance provenanceOf(HermesMobileMessage m, {List<String> runTools = const []}) {
  if (m.isUser || m.text.trim().isEmpty) return const ReplyProvenance();
  final sources = <LinkRef>[];
  final seen = <String>{};
  for (final b in parseHermesMobileBlocks(m.text)) {
    if (b is LinksBlock) {
      for (final l in b.links) {
        if (seen.add(l.url)) sources.add(l);
      }
    }
  }
  // Inline markdown links in prose count too.
  for (final match in RegExp(r'\[([^\]]+)\]\((https?://[^)\s]+)\)').allMatches(m.text)) {
    final url = match.group(2)!;
    if (seen.add(url)) sources.add(LinkRef(url: url, title: match.group(1)));
  }
  final tools = {...m.toolNames, ...runTools}.toList();
  ConfidenceLevel? level;
  final explicit = _confidenceLine.firstMatch(m.text);
  if (explicit != null) {
    level = switch (explicit.group(1)!.toLowerCase()) {
      'high' => ConfidenceLevel.high,
      'low' => ConfidenceLevel.low,
      _ => ConfidenceLevel.medium,
    };
  } else if (_hedges.hasMatch(m.text)) {
    level = ConfidenceLevel.low;
  } else if (sources.length >= 2 ||
      tools.any((t) => _webTools.contains(t.toLowerCase()))) {
    level = ConfidenceLevel.high;
  }
  final fromMemory = tools.any((t) => t.toLowerCase().contains('memory'));
  return ReplyProvenance(
    sources: sources,
    confidence: level,
    tools: tools,
    fromMemory: fromMemory,
  );
}

// ── Offline detection ────────────────────────────────────────────────────

final _networkError = RegExp(
  r'(SocketException|Failed host lookup|Connection refused|Connection reset|'
  r'Connection closed|Network is unreachable|No route to host|timed out|'
  r'TimeoutException|ClientException|HandshakeException|OS Error)',
  caseSensitive: false,
);

/// True when a send error means "could not reach Hermes" rather than an
/// agent or auth failure, so the message can wait in the offline queue.
bool isOfflineError(String? error) =>
    error != null && _networkError.hasMatch(error);

// ── Outbound actions (undo window) ──────────────────────────────────────

final _outboundWords = RegExp(
  r'\b(send|sends|sending|email|e-mail|mail|message|text|sms|reply|post|'
  r'tweet|publish|order|purchase|buy|checkout|pay|payment|transfer|book|'
  r'reserve|invite|share|submit|rsvp|cancel (?:my|the) (?:order|booking))\b',
  caseSensitive: false,
);

final _outboundCommands = RegExp(
  r'(gmail\S*\s+\S*send|sendmail|smtp|curl\s.*-X\s*(POST|PUT|PATCH)|'
  r'twilio|telegram\S*\s+send|slack\S*\s+(post|send)|gh\s+(pr|issue)\s+(create|comment))',
  caseSensitive: false,
);

/// True when an approval or card action lets something leave the system
/// (a message, a post, an order, a payment). Only those get the undo window.
bool isOutboundAction(String description, {String command = ''}) =>
    _outboundWords.hasMatch(description) ||
    _outboundCommands.hasMatch(command) ||
    _outboundWords.hasMatch(command.split(RegExp(r'\s')).take(3).join(' '));

// ── Dashboard hand-off ───────────────────────────────────────────────────

/// The Hermes dashboard opens a chat with `/chat?resume=<session id>`.
/// Returns null when no dashboard URL is configured.
String? dashboardSessionUrl(String? dashboardBase, String chatId) {
  final base = dashboardBase?.trim() ?? '';
  if (base.isEmpty || chatId.isEmpty) return null;
  final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$trimmed/chat?resume=${Uri.encodeQueryComponent(chatId)}';
}
