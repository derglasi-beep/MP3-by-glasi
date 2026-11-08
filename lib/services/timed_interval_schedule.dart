import 'dart:math' as math;

import 'spinning_playlist_service.dart';

/// Song-based mode follows the music. The other presets use a training clock
/// and never seek, restart or interrupt audio at an interval boundary.
enum TimedIntervalPreset { songs, thirtyThirty, sprint, tabata }

extension TimedIntervalPresetLabels on TimedIntervalPreset {
  String get label => switch (this) {
        TimedIntervalPreset.songs => 'Songwechsel',
        TimedIntervalPreset.thirtyThirty => '30/30',
        TimedIntervalPreset.sprint => 'Sprint 20/100',
        TimedIntervalPreset.tabata => 'Tabata 20/10',
      };

  String get description => switch (this) {
        TimedIntervalPreset.songs =>
          'Ein Erholungssong wiederholt sich; Intervalle wechseln mit den Songs.',
        TimedIntervalPreset.thirtyThirty =>
          '30 Sekunden Belastung, 30 Sekunden aktive Erholung. Musik läuft weiter.',
        TimedIntervalPreset.sprint =>
          '20 Sekunden Sprint, 100 Sekunden aktive Erholung. Musik läuft weiter.',
        TimedIntervalPreset.tabata =>
          '8 × 20 Sekunden Belastung/10 Sekunden Erholung, danach 2 Minuten locker. Musik läuft weiter.',
      };
}

/// Optional workout parameters. Defaults preserve the named presets.
class TimedIntervalConfig {
  final int workSeconds;
  final int recoverySeconds;
  final int roundsPerBlock;
  final int effortRpe;

  const TimedIntervalConfig({
    required this.workSeconds,
    required this.recoverySeconds,
    required this.roundsPerBlock,
    required this.effortRpe,
  });

  factory TimedIntervalConfig.forPreset(TimedIntervalPreset preset) =>
      switch (preset) {
        TimedIntervalPreset.songs => const TimedIntervalConfig(
            workSeconds: 30, recoverySeconds: 30,
            roundsPerBlock: 8, effortRpe: 7),
        TimedIntervalPreset.thirtyThirty => const TimedIntervalConfig(
            workSeconds: 30, recoverySeconds: 30,
            roundsPerBlock: 10, effortRpe: 7),
        TimedIntervalPreset.sprint => const TimedIntervalConfig(
            workSeconds: 20, recoverySeconds: 100,
            roundsPerBlock: 6, effortRpe: 9),
        TimedIntervalPreset.tabata => const TimedIntervalConfig(
            workSeconds: 20, recoverySeconds: 10,
            roundsPerBlock: 8, effortRpe: 9),
      };

  TimedIntervalConfig copyWith({
    int? workSeconds, int? recoverySeconds,
    int? roundsPerBlock, int? effortRpe,
  }) => TimedIntervalConfig(
    workSeconds: workSeconds ?? this.workSeconds,
    recoverySeconds: recoverySeconds ?? this.recoverySeconds,
    roundsPerBlock: roundsPerBlock ?? this.roundsPerBlock,
    effortRpe: effortRpe ?? this.effortRpe,
  );
}

class TimedIntervalStep {
  final Duration start;
  final Duration end;
  final SpinningPhase phase;
  final String label;
  final String instruction;
  final int round;

  const TimedIntervalStep({
    required this.start,
    required this.end,
    required this.phase,
    required this.label,
    required this.instruction,
    required this.round,
  });
}

class TimedIntervalSchedule {
  final List<TimedIntervalStep> steps;
  final Duration duration;
  final TimedIntervalPreset preset;

  const TimedIntervalSchedule({
    required this.steps,
    required this.duration,
    required this.preset,
  });

  static TimedIntervalSchedule build(
    Duration duration,
    TimedIntervalPreset preset, {
    TimedIntervalConfig? config,
  }) {
    final settings = config ?? TimedIntervalConfig.forPreset(preset);
    if (settings.workSeconds < 5 || settings.workSeconds > 600 ||
        settings.recoverySeconds < 5 || settings.recoverySeconds > 600 ||
        settings.roundsPerBlock < 1 || settings.roundsPerBlock > 40 ||
        settings.effortRpe < 5 || settings.effortRpe > 10) {
      throw ArgumentError('Ungültige Intervall-Einstellungen');
    }
    if (duration <= Duration.zero || preset == TimedIntervalPreset.songs) {
      return TimedIntervalSchedule(
        steps: const [],
        duration: duration,
        preset: preset,
      );
    }

    final totalMs = duration.inMilliseconds;
    final warmupMs = math.min(
      const Duration(minutes: 8).inMilliseconds,
      (totalMs * .20).round(),
    );
    final cooldownMs = math.min(
      const Duration(minutes: 5).inMilliseconds,
      (totalMs * .15).round(),
    );
    final workEnd = duration - Duration(milliseconds: cooldownMs);
    final steps = <TimedIntervalStep>[];

    void add(Duration start, Duration end, SpinningPhase phase,
        String label, String instruction, int round) {
      if (end <= start) return;
      steps.add(TimedIntervalStep(
        start: start,
        end: end,
        phase: phase,
        label: label,
        instruction: instruction,
        round: round,
      ));
    }

    var position = Duration(milliseconds: warmupMs);
    add(
      Duration.zero,
      position,
      SpinningPhase.warmup,
      'Warm-up',
      'Locker einrollen · RPE 2–3/10',
      0,
    );

    final workSeconds = settings.workSeconds;
    final recoverySeconds = settings.recoverySeconds;
    var round = 0;
    while (position < workEnd) {
      round++;
      var next = position + Duration(seconds: workSeconds);
      if (next > workEnd) next = workEnd;
      add(
        position,
        next,
        SpinningPhase.peak,
        preset == TimedIntervalPreset.thirtyThirty
            ? 'Belastung $round'
            : 'Sprint $round',
        'Belastung · RPE ${settings.effortRpe}/10',
        round,
      );
      position = next;
      if (position >= workEnd) break;

      final blockBreak = round % settings.roundsPerBlock == 0;
      next = position +
          Duration(seconds: blockBreak ? 120 : recoverySeconds);
      if (next > workEnd) next = workEnd;
      add(
        position,
        next,
        SpinningPhase.build,
        blockBreak ? 'Blockpause' : 'Aktive Erholung',
        'Widerstand reduzieren · locker treten · RPE 2–3/10',
        round,
      );
      position = next;
    }

    add(
      workEnd,
      duration,
      SpinningPhase.cooldown,
      'Cool-down',
      'Locker ausfahren · RPE 2/10',
      0,
    );

    return TimedIntervalSchedule(
      steps: List.unmodifiable(steps),
      duration: duration,
      preset: preset,
    );
  }

  int indexAt(Duration elapsed) {
    if (steps.isEmpty) return -1;
    if (elapsed <= Duration.zero) return 0;
    for (var i = 0; i < steps.length; i++) {
      if (elapsed < steps[i].end) return i;
    }
    return steps.length - 1;
  }

  TimedIntervalStep? stepAt(Duration elapsed) {
    final index = indexAt(elapsed);
    return index < 0 ? null : steps[index];
  }

  TimedIntervalStep? nextAfter(Duration elapsed) {
    final index = indexAt(elapsed);
    return index < 0 || index + 1 >= steps.length
        ? null
        : steps[index + 1];
  }

  Duration remainingAt(Duration elapsed) {
    final step = stepAt(elapsed);
    if (step == null) return Duration.zero;
    final remaining = step.end - elapsed;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }
}
