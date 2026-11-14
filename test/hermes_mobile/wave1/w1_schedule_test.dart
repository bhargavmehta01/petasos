import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_schedule.dart';

void main() {
  // Tuesday 2026-11-03 14:55 local.
  final now = DateTime(2026, 11, 3, 14, 55);
  ScheduleIntent? p(String s) => parseScheduleIntent(s, now: now);

  test('daily reminder with a time', () {
    final i = p('Remind me to take vitamins every day at 8am')!;
    expect(i.schedule, '0 8 * * *');
    expect(i.human, 'Every day at 8:00 AM');
    expect(i.task, 'take vitamins');
    expect(i.prompt, 'Send me a reminder: take vitamins');
    expect(i.oneShot, isFalse);
  });

  test('weekday task keeps casing', () {
    final i = p('Every weekday at 9:30 summarise my Gmail inbox')!;
    expect(i.schedule, '30 9 * * 1-5');
    expect(i.task, 'summarise my Gmail inbox');
    expect(i.prompt, 'Summarise my Gmail inbox');
  });

  test('day list and default evening time', () {
    final i = p('every monday and thursday evening check the backups')!;
    expect(i.schedule, '0 18 * * 1,4');
    expect(i.human, 'Every Mon, Thu at 6:00 PM');
    expect(i.task, 'check the backups');
  });

  test('interval', () {
    final i = p('every 2 hours check the price of the XM6')!;
    expect(i.schedule, 'every 2h');
    expect(i.human, 'Every 2 hours');
  });

  test('one-shot delay', () {
    final i = p('remind me in 20 minutes to move the laundry')!;
    expect(i.schedule, '20m');
    expect(i.oneShot, isTrue);
    expect(i.task, 'move the laundry');
  });

  test('tomorrow at a time', () {
    final i = p('Remind me to call the dentist tomorrow at 10am')!;
    expect(i.schedule, '2026-11-04T10:00');
    expect(i.human, 'Once, Tomorrow at 10:00 AM');
    expect(i.task, 'call the dentist');
  });

  test('time already passed today rolls to tomorrow', () {
    final i = p('remind me at 9am to stretch')!;
    expect(i.schedule, '2026-11-04T09:00');
  });

  test('next weekday one-shot', () {
    final i = p('remind me on friday at 5pm to pay Georgia Power')!;
    expect(i.schedule, '2026-11-06T17:00');
    expect(i.task, 'pay Georgia Power');
  });

  test('ordinary questions are not schedules', () {
    expect(p('What happened at 9pm last night?'), isNull);
    expect(p('Plan our Springfield weekend'), isNull);
    expect(p('how do I set an alarm'), isNull);
    expect(p('remind me'), isNull);
  });
}
