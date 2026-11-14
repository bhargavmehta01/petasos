/// Natural-language scheduling: turns "remind me to call mom tomorrow at 6pm"
/// or "every weekday at 9 summarise my inbox" into a Hermes cron schedule
/// (cron expression, `every 2h`, a `30m` delay, or a local ISO timestamp)
/// that the composer previews before anything is created.
library;

class ScheduleIntent {
  const ScheduleIntent({
    required this.schedule,
    required this.human,
    required this.task,
    required this.prompt,
    required this.name,
    required this.oneShot,
  });

  /// What Hermes cron accepts: `0 9 * * 1-5`, `every 2h`, `30m`,
  /// `2026-11-04T18:00`.
  final String schedule;

  /// "Every weekday at 9:00 AM".
  final String human;

  /// The thing to do, with the scheduling words removed.
  final String task;

  /// The prompt the cron job runs.
  final String prompt;
  final String name;
  final bool oneShot;

  ScheduleIntent copyWith({String? schedule, String? human, String? prompt, String? name}) =>
      ScheduleIntent(
        schedule: schedule ?? this.schedule,
        human: human ?? this.human,
        task: task,
        prompt: prompt ?? this.prompt,
        name: name ?? this.name,
        oneShot: oneShot,
      );
}

const _days = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];
const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

final _dayPattern =
    r'(mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:rs(?:day)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)s?';

int? _dayIndex(String word) {
  final w = word.toLowerCase();
  for (var i = 0; i < _days.length; i++) {
    if (_days[i].startsWith(w.substring(0, w.length.clamp(0, 3)))) return i;
  }
  return null;
}

class _Time {
  const _Time(this.h, this.m);
  final int h;
  final int m;
  String get label {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }
}

/// Parses [text]; returns null when it is not a scheduling request.
ScheduleIntent? parseScheduleIntent(String text, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final raw = text.trim();
  if (raw.isEmpty || raw.length > 500) return null;
  var t = raw.toLowerCase();
  final consumed = <RegExp>[];
  RegExpMatch? take(String pattern) {
    final re = RegExp(pattern, caseSensitive: false);
    final m = re.firstMatch(t);
    if (m != null) consumed.add(RegExp(RegExp.escape(m[0]!), caseSensitive: false));
    return m;
  }

  final remind = RegExp(r'^(please\s+)?remind me\b').hasMatch(t);
  final scheduleVerb =
      remind ||
      RegExp(r'^(please\s+)?(schedule|set up|create)\b').hasMatch(t) ||
      RegExp(r'^(every|each|daily|hourly|weekly)\b').hasMatch(t);

  // ── time of day ─────────────────────────────────────────────────────
  _Time? time;
  final at = take(r'\b(?:at|@)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?');
  if (at != null) {
    var h = int.parse(at[1]!);
    final m = int.tryParse(at[2] ?? '') ?? 0;
    final ap = at[3]?.replaceAll('.', '');
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    if (ap == null && h >= 1 && h <= 6) h += 12; // "at 6" means evening
    if (h > 23 || m > 59) return null;
    time = _Time(h, m);
  } else {
    final bare = take(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b');
    if (bare != null) {
      var h = int.parse(bare[1]!);
      final m = int.tryParse(bare[2] ?? '') ?? 0;
      if (bare[3] == 'pm' && h < 12) h += 12;
      if (bare[3] == 'am' && h == 12) h = 0;
      if (h > 23 || m > 59) return null;
      time = _Time(h, m);
    } else if (take(r'\b(?:at\s+)?noon\b') != null) {
      time = const _Time(12, 0);
    } else if (take(r'\b(?:at\s+)?midnight\b') != null) {
      time = const _Time(0, 0);
    }
  }

  String schedule;
  String human;
  var oneShot = false;

  // ── recurrence ──────────────────────────────────────────────────────
  final interval = take(
    r'\bevery\s+(\d+)\s*(minutes?|mins?|m|hours?|hrs?|h|days?|d)\b',
  );
  final unitEvery = interval == null
      ? take(r'\b(?:every\s+(minute|hour)|(hourly))\b')
      : null;
  final weekdays = take(r'\b(?:every\s+weekdays?|on\s+weekdays|weekdays)\b');
  final weekends = weekdays == null
      ? take(r'\b(?:every\s+weekends?|on\s+weekends)\b')
      : null;
  final dayList =
      take(
        '\\b(?:every|each)\\s+$_dayPattern(?:\\s*(?:,|and|&)\\s*$_dayPattern)*',
      ) ??
      take(
        r'\bon\s+(mondays|tuesdays|wednesdays|thursdays|fridays|saturdays|sundays)(?:\s*(?:,|and|&)\s*(mondays|tuesdays|wednesdays|thursdays|fridays|saturdays|sundays))*\b',
      );
  final daily = take(
    r'\b(?:every\s*day|daily|each\s+day|every\s+(morning|evening|night|afternoon)|each\s+(morning|evening|night))\b',
  );
  final weekly = take(r'\b(?:every\s+week|weekly)\b');

  _Time defaultFor(String? part) => switch (part) {
    'evening' => const _Time(18, 0),
    'night' => const _Time(21, 0),
    'afternoon' => const _Time(14, 0),
    _ => const _Time(8, 0),
  };

  if (interval != null) {
    final n = int.parse(interval[1]!);
    if (n <= 0) return null;
    final u = interval[2]!.startsWith('m')
        ? 'm'
        : interval[2]!.startsWith('h')
        ? 'h'
        : 'd';
    schedule = 'every $n$u';
    final unit = {'m': 'minute', 'h': 'hour', 'd': 'day'}[u]!;
    human = 'Every $n $unit${n == 1 ? '' : 's'}';
  } else if (unitEvery != null) {
    final u = unitEvery[1] == 'minute' ? 'm' : 'h';
    schedule = 'every 1$u';
    human = u == 'm' ? 'Every minute' : 'Every hour';
  } else if (weekdays != null || weekends != null || dayList != null ||
      daily != null || weekly != null) {
    RegExpMatch? partOfDay;
    if (time == null && daily == null) {
      partOfDay = take(
        r'\b(?:in the\s+|at\s+)?(morning|evening|night|afternoon)s?\b',
      );
    }
    final part = daily?[1] ?? daily?[2] ?? partOfDay?[1];
    final tm = time ?? defaultFor(part);
    String dow;
    String when;
    if (weekdays != null) {
      dow = '1-5';
      when = 'Every weekday';
    } else if (weekends != null) {
      dow = '0,6';
      when = 'Every weekend day';
    } else if (dayList != null) {
      final idx = <int>{};
      for (final m in RegExp(_dayPattern).allMatches(dayList[0]!)) {
        final i = _dayIndex(m[1]!);
        if (i != null) idx.add(i);
      }
      if (idx.isEmpty) return null;
      final sorted = idx.toList()..sort();
      dow = sorted.map((i) => (i + 1) % 7).join(',');
      when = 'Every ${sorted.map((i) => _dayShort[i]).join(', ')}';
    } else if (weekly != null) {
      dow = '1';
      when = 'Every Monday';
    } else {
      dow = '*';
      when = 'Every day';
    }
    schedule = '${tm.m} ${tm.h} * * $dow';
    human = '$when at ${tm.label}';
  } else {
    // ── one-shot ──────────────────────────────────────────────────────
    final inDelay = take(
      r'\bin\s+(\d+|an?|one)\s*(minutes?|mins?|hours?|hrs?|days?)\b',
    );
    if (inDelay != null) {
      final n = int.tryParse(inDelay[1]!) ?? 1;
      if (n <= 0) return null;
      final u = inDelay[2]!.startsWith('m')
          ? 'm'
          : inDelay[2]!.startsWith('h')
          ? 'h'
          : 'd';
      schedule = '$n$u';
      final unit = {'m': 'minute', 'h': 'hour', 'd': 'day'}[u]!;
      human = 'Once, in $n $unit${n == 1 ? '' : 's'}';
      oneShot = true;
    } else {
      final tomorrow = take(r'\btomorrow\b');
      final today = tomorrow == null ? take(r'\b(?:today|tonight)\b') : null;
      final onDay = (tomorrow == null && today == null)
          ? take('\\b(?:on|next|this)\\s+$_dayPattern')
          : null;
      if (tomorrow == null && today == null && onDay == null && time == null) {
        return null;
      }
      if (!scheduleVerb && tomorrow == null && onDay == null) return null;
      final tm =
          time ??
          (today != null && t.contains('tonight')
              ? const _Time(20, 0)
              : const _Time(9, 0));
      var day = DateTime(clock.year, clock.month, clock.day, tm.h, tm.m);
      if (tomorrow != null) {
        day = day.add(const Duration(days: 1));
      } else if (onDay != null) {
        final want = _dayIndex(onDay[1]!)!;
        var delta = (want - (clock.weekday - 1)) % 7;
        if (delta == 0 && !day.isAfter(clock)) delta = 7;
        day = day.add(Duration(days: delta));
      } else if (!day.isAfter(clock)) {
        day = day.add(const Duration(days: 1));
      }
      schedule =
          '${day.year.toString().padLeft(4, '0')}-${_pad2(day.month)}-${_pad2(day.day)}'
          'T${_pad2(day.hour)}:${_pad2(day.minute)}';
      final sameDay =
          day.year == clock.year && day.month == clock.month && day.day == clock.day;
      final isTomorrow = day.difference(DateTime(clock.year, clock.month, clock.day)).inDays == 1;
      final dayLabel = sameDay
          ? 'Today'
          : isTomorrow
          ? 'Tomorrow'
          : '${_dayShort[day.weekday - 1]} ${day.month}/${day.day}';
      human = 'Once, $dayLabel at ${tm.label}';
      oneShot = true;
    }
  }

  if (!scheduleVerb && !RegExp(r'\b(every|each|daily|hourly|weekly)\b').hasMatch(raw.toLowerCase())) {
    // "Summarise my inbox every morning" counts; "what happened at 9pm" does not.
    if (oneShot) return null;
  }

  // ── task text ───────────────────────────────────────────────────────
  for (final re in consumed) {
    t = t.replaceFirst(re, ' ');
  }
  var task = t
      .replaceFirst(RegExp(r'^\s*(please\s+)?(remind me( to| that| about)?|schedule( a)?|set up( a)?|create( a)?)\s*'), '')
      .replaceAll(RegExp(r'\s+(to|at|on)\s*$'), '')
      .replaceAll(RegExp(r'^\s*(to|at|on)\s+'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAllMapped(RegExp(r'\s+([,.!?])'), (m) => m[1]!)
      .trim();
  task = task.replaceAll(RegExp(r'^[,.\s]+|[,\s]+$'), '');
  if (task.isEmpty) return null;
  // Keep the user's original casing where we can find the task in it.
  final idx = raw.toLowerCase().indexOf(task);
  if (idx >= 0) task = raw.substring(idx, idx + task.length);

  final prompt = remind
      ? 'Send me a reminder: $task'
      : task[0].toUpperCase() + task.substring(1);
  final name = (remind ? 'Reminder: $task' : prompt);
  return ScheduleIntent(
    schedule: schedule,
    human: human,
    task: task,
    prompt: prompt,
    name: name.length > 48 ? '${name.substring(0, 47)}…' : name,
    oneShot: oneShot,
  );
}

String _pad2(int v) => v.toString().padLeft(2, '0');
