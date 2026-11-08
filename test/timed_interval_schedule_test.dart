import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_by_glasi/services/spinning_playlist_service.dart';
import 'package:mp3_by_glasi/services/timed_interval_schedule.dart';

void main() {
  for (final preset in [
    TimedIntervalPreset.thirtyThirty,
    TimedIntervalPreset.sprint,
    TimedIntervalPreset.tabata,
  ]) {
    test('${preset.label} has a contiguous clock-based schedule', () {
      for (final minutes in [30, 45, 60, 90]) {
        final duration = Duration(minutes: minutes);
        final schedule = TimedIntervalSchedule.build(duration, preset);
        expect(schedule.steps.first.phase, SpinningPhase.warmup);
        expect(schedule.steps.first.start, Duration.zero);
        expect(schedule.steps.last.phase, SpinningPhase.cooldown);
        expect(schedule.steps.last.end, duration);
        for (var i = 1; i < schedule.steps.length; i++) {
          expect(schedule.steps[i].start, schedule.steps[i - 1].end);
          expect(schedule.steps[i].end > schedule.steps[i].start, isTrue);
        }
        final firstWorkIndex = schedule.steps.indexWhere(
          (step) => step.phase == SpinningPhase.peak,
        );
        expect(firstWorkIndex, greaterThan(0));
        final firstWork = schedule.steps[firstWorkIndex];
        expect(
          firstWork.end - firstWork.start,
          Duration(seconds:
              preset == TimedIntervalPreset.thirtyThirty ? 30 : 20),
        );
        final afterWork = schedule.steps[firstWorkIndex + 1];
        expect(afterWork.phase, SpinningPhase.build);
        expect(
          afterWork.end - afterWork.start,
          Duration(seconds: switch (preset) {
            TimedIntervalPreset.thirtyThirty => 30,
            TimedIntervalPreset.sprint => 100,
            TimedIntervalPreset.tabata => 10,
            TimedIntervalPreset.songs => 0,
          }),
        );
        expect(schedule.stepAt(firstWork.start)?.phase, SpinningPhase.peak);
        expect(schedule.stepAt(firstWork.end)?.phase, SpinningPhase.build);
        expect(schedule.remainingAt(firstWork.end), afterWork.end - afterWork.start);
        expect(schedule.stepAt(duration)?.phase, SpinningPhase.cooldown);
      }
    });
  }

  test('Tabata inserts a full recovery after eight hard efforts', () {
    final schedule = TimedIntervalSchedule.build(
      const Duration(minutes: 30),
      TimedIntervalPreset.tabata,
    );
    final blockRest = schedule.steps.firstWhere(
      (step) => step.label == 'Blockpause',
    );
    expect(blockRest.round, 8);
    expect(blockRest.end - blockRest.start, const Duration(minutes: 2));
    expect(blockRest.instruction, contains('Widerstand'));
  });

  test('song mode has no independent interval timer', () {
    final schedule = TimedIntervalSchedule.build(
      const Duration(minutes: 30),
      TimedIntervalPreset.songs,
    );
    expect(schedule.steps, isEmpty);
    expect(schedule.stepAt(Duration.zero), isNull);
  });
}
