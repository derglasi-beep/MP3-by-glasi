import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_by_glasi/models/track.dart';
import 'package:mp3_by_glasi/services/spinning_playlist_service.dart';
import 'package:mp3_by_glasi/services/spinning_session_controller.dart';

void main() {
  test('heart-training pulse targets stay moderate throughout the session', () {
    final expected = <SpinningPhase, ({int min, int max})>{
      SpinningPhase.warmup: (min: 60, max: 65),
      SpinningPhase.build: (min: 65, max: 69),
      SpinningPhase.recovery: (min: 60, max: 69),
      SpinningPhase.load: (min: 70, max: 79),
      SpinningPhase.peak: (min: 80, max: 85),
      SpinningPhase.cooldown: (min: 60, max: 65),
    };

    for (final phase in SpinningPhase.values) {
      expect(
        SpinningPlaylistService.heartRateRange(
          SpinningTrainingProfile.heartRate,
          phase,
        ),
        expected[phase],
      );
    }

    expect(
      SpinningPlaylistService.heartRateRange(
        SpinningTrainingProfile.cadence,
        SpinningPhase.peak,
      ).max,
      95,
    );
  });

  test('interval mode alternates effort and recovery without losing blocks', () {
    final library = [
      for (var index = 0; index < 45; index++)
        Track(
          id: 'interval-song-$index',
          path: '/fake/interval-$index.mp3',
          title: 'Interval Song $index',
          artist: 'Artist $index',
          bpm: 140,
          duration: const Duration(minutes: 3),
        ),
    ];
    for (final minutes in [30, 45, 60]) {
      final planner = SpinningPlaylistService();
      final plan = planner.build(
        library: library,
        duration: Duration(minutes: minutes),
        profile: SpinningTrainingProfile.interval,
        phases: SpinningPlaylistService.intervalPhases,
      );
      final windows = SpinningSessionController.phaseWindowsFor(plan, null);
      final expected = windows.map((window) => window.phase).toList();
      final actual = <SpinningPhase>[];
      for (final selection in plan.selections) {
        if (actual.isEmpty || actual.last != selection.phase) {
          actual.add(selection.phase);
        }
      }
      expect(expected.first, SpinningPhase.warmup);
      expect(expected.last, SpinningPhase.cooldown);
      expect(actual, orderedEquals(expected));
      for (var index = 1; index < expected.length - 1; index++) {
        if (expected[index] == SpinningPhase.peak ||
            expected[index] == SpinningPhase.load) {
          expect(expected[index - 1], SpinningPhase.recovery);
        }
      }
      expect(
        SpinningPlaylistService.heartRateRange(
          SpinningTrainingProfile.interval,
          SpinningPhase.peak,
        ).max,
        89,
      );
    }
  });

  test('interval recovery reuses the same song and length every time', () {
    final library = [
      for (var index = 0; index < 45; index++)
        Track(
          id: 'music-$index',
          path: '/fake/music-$index.mp3',
          title: 'Music $index',
          artist: 'Artist $index',
          bpm: index.isEven ? 108 : 155,
          duration: Duration(seconds: 160 + index * 6),
        ),
    ];

    for (final minutes in [30, 45, 60]) {
      final plan = SpinningPlaylistService().build(
        library: library,
        duration: Duration(minutes: minutes),
        profile: SpinningTrainingProfile.interval,
        phases: SpinningPlaylistService.intervalPhases,
      );
      final recovery = plan.selections
          .where((selection) => selection.phase == SpinningPhase.recovery)
          .toList();
      expect(recovery.length, greaterThanOrEqualTo(3));
      expect(recovery.map((selection) => selection.track.id).toSet().length, 1);

      final first = recovery.first.track;
      expect(
        recovery.every((selection) => selection.track.duration == first.duration),
        isTrue,
      );
      final work = plan.selections
          .where((selection) => selection.phase == SpinningPhase.load ||
              selection.phase == SpinningPhase.peak)
          .toList();
      expect(work, isNotEmpty);
      expect(work.every((selection) => selection.track.id != first.id), isTrue);
    }
  });

  test('manual interval playlist repeats its chosen recovery track', () {
    final recovery = Track(
      id: 'recovery',
      path: '/fake/recovery.mp3',
      title: 'My recovery song',
      bpm: 108,
      duration: const Duration(minutes: 3),
    );
    final work = [
      for (var index = 0; index < 8; index++)
        Track(
          id: 'effort-$index',
          path: '/fake/effort-$index.mp3',
          title: 'Effort $index',
          bpm: index.isEven ? 140 : 158,
          duration: const Duration(minutes: 3),
        ),
    ];
    final planner = SpinningPlaylistService();
    final plan = planner.buildFromPhaseTracks(
      phaseTracks: {
        SpinningPhase.recovery: [recovery],
        SpinningPhase.load: work,
        SpinningPhase.peak: work,
      },
      duration: const Duration(minutes: 45),
      phases: SpinningPlaylistService.intervalPhases,
      profile: SpinningTrainingProfile.interval,
    );
    final recoveries = plan.selections
        .where((selection) => selection.phase == SpinningPhase.recovery)
        .toList();
    expect(recoveries.length, greaterThanOrEqualTo(3));
    expect(recoveries.every((selection) => selection.track.id == recovery.id),
        isTrue);
  });

  test('repeated curve phases keep their original sequence', () {
    const minute = Duration(minutes: 1);
    const phases = <SpinningPhase>[
      SpinningPhase.warmup,
      SpinningPhase.build,
      SpinningPhase.load,
      SpinningPhase.build,
      SpinningPhase.peak,
      SpinningPhase.load,
      SpinningPhase.peak,
      SpinningPhase.cooldown,
    ];
    final curve = <SpinningCurvePoint>[
      for (var i = 0; i < phases.length; i++)
        SpinningCurvePoint(
          position: minute * i,
          phase: phases[i],
          targetBpm: 120,
          tolerance: 7,
        ),
    ];
    final plan = SpinningPlan(
      duration: minute * phases.length,
      tracks: const [],
      phases: const [],
      curve: curve,
    );

    final windows = SpinningSessionController.phaseWindowsFor(plan, null);

    expect(windows.map((item) => item.phase), orderedEquals(phases));
    expect(windows.map((item) => item.start),
        orderedEquals([for (var i = 0; i < phases.length; i++) minute * i]));
    expect(windows.last.end, plan.duration);
    expect(windows[2].nextPhase, SpinningPhase.build);
    expect(windows.last.nextPhase, isNull);
  });

  test('automatic playlist includes every repeated curve block', () {
    final library = [
      for (var index = 0; index < 60; index++)
        Track(
          id: 'song-$index',
          path: '/fake/song-$index.mp3',
          title: 'Song $index',
          artist: 'Artist $index',
          bpm: 124,
          duration: const Duration(minutes: 4),
        ),
    ];

    final plan = SpinningPlaylistService().build(
      library: library,
      duration: const Duration(minutes: 45),
    );
    final expected = SpinningSessionController.phaseWindowsFor(plan, null)
        .map((window) => window.phase)
        .toList();
    final actual = <SpinningPhase>[];
    for (final selection in plan.selections) {
      if (actual.isEmpty || actual.last != selection.phase) {
        actual.add(selection.phase);
      }
    }

    expect(expected, isNotEmpty);
    expect(actual, orderedEquals(expected));
    expect(actual.last, SpinningPhase.cooldown);
  });

  test('custom segments retain repeated phases and durations', () {
    final profile = CustomBpmProfile(
      id: 'regression',
      name: 'Repeated phases',
      segments: const [
        CustomBpmSegment(
          label: 'Start',
          duration: Duration(minutes: 3),
          minBpm: 90,
          maxBpm: 105,
          phase: SpinningPhase.warmup,
        ),
        CustomBpmSegment(
          label: 'Load',
          duration: Duration(minutes: 4),
          minBpm: 120,
          maxBpm: 140,
          phase: SpinningPhase.load,
        ),
        CustomBpmSegment(
          label: 'Recover',
          duration: Duration(minutes: 2),
          minBpm: 100,
          maxBpm: 120,
          phase: SpinningPhase.build,
        ),
        CustomBpmSegment(
          label: 'Load again',
          duration: Duration(minutes: 4),
          minBpm: 120,
          maxBpm: 140,
          phase: SpinningPhase.load,
        ),
        CustomBpmSegment(
          label: 'Finish',
          duration: Duration(minutes: 3),
          minBpm: 90,
          maxBpm: 105,
          phase: SpinningPhase.cooldown,
        ),
      ],
    );
    final plan = SpinningPlan(
      duration: profile.duration,
      tracks: const [],
      phases: const [],
    );
    final windows = SpinningSessionController.phaseWindowsFor(plan, profile);
    expect(windows.length, 5);
    expect(windows[1].nextPhase, SpinningPhase.build);
    expect(windows[2].nextPhase, SpinningPhase.load);
    expect(windows.map((window) => window.label),
        ['Start', 'Load', 'Recover', 'Load again', 'Finish']);
    expect(windows.last.end, profile.duration);
  });
}
