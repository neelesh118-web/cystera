/// How bad something was, and the words for it.
///
/// Three levels, not five and not a slider. The evidence for two reasons:
///
///  * A five-point scale produces data people cannot reproduce a week later.
///    What was a 3 last Tuesday is a 4 this Tuesday, and a chart of that is a
///    chart of the mood of whoever was logging.
///  * More levels than fingers means aiming, and this screen gets used on days
///    when the user feels awful. One tap has to be enough.
///
/// The words are the ones the app says out loud, kept here rather than in the
/// widgets so the same sentence appears in the log row, the undo toast and the
/// doctor report. `Severity.effect` is the honest half: it says what the level
/// cost the user, which is what they are actually answering when they tap.
library;

enum Severity {
  mild(1, 'Mild', 'it was there, but I got on with the day'),
  moderate(2, 'Moderate', 'it changed what I did today'),
  severe(3, 'Severe', 'it took the day');

  const Severity(this.level, this.word, this.effect);

  /// Stored in the database. 1–3, never 0: absence is the absence of a row, not
  /// a row saying "none", so a cleared symptom cannot be confused with a logged
  /// zero in a later average.
  final int level;

  /// The one-word label on the tap target.
  final String word;

  /// What the level means, in the user's terms rather than a clinician's.
  final String effect;

  static Severity? fromLevel(int? level) {
    for (final value in Severity.values) {
      if (value.level == level) return value;
    }
    return null;
  }

  /// The index into `AppTokens.severity`, whose ramp runs blush → rose →
  /// crimson. Severity climbs the brand ramp instead of switching to a traffic
  /// light, because "severe" is not an error and "mild" is not success.
  int get rampIndex => level;
}

/// How heavy the bleeding was, for the days the user says it was a period.
///
/// Kept separate from [Severity] because "severe flow" is not a worse version of
/// "severe pain" — they are different questions that happen to have three
/// answers, and sharing one enum would invite comparing them.
enum FlowLevel {
  light(1, 'Light'),
  medium(2, 'Medium'),
  heavy(3, 'Heavy');

  const FlowLevel(this.level, this.word);

  final int level;
  final String word;

  static FlowLevel? fromLevel(int? level) {
    for (final value in FlowLevel.values) {
      if (value.level == level) return value;
    }
    return null;
  }

  int get rampIndex => level;
}
