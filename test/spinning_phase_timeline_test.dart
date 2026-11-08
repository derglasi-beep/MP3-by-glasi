import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_by_glasi/models/track.dart';
import 'package:mp3_by_glasi/services/spinning_playlist_service.dart';
import 'package:mp3_by_glasi/services/spinning_session_controller.dart';

void main() {
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
