/// What the app will interrupt you for, and what it promises never to do.
///
/// Reminders are the one part of this app that reaches outside it, so they are
/// designed the way the rest of it is: nothing is promised that the record cannot
/// support, and nothing nags.
///
/// Four kinds, and only four:
///
///  * **A daily nudge** to write the day down, at a time the user picks, and it
///    waits for tomorrow if today is already recorded.
///  * **A heads-up before the window** the prediction opens — set from the
///    window, cancelled by it, and never sent when there is no window.
///  * **One late check**, a couple of days after the window closes, sent **once
///    per window**. Not once a day, not until it is answered — once. This is the
///    rule the whole file exists for: a reminder that repeats while a period is
///    late is a nag with an alarm attached, and the people who most often have
///    late periods are the ones who least need to be told.
///  * **The annual review**, on the morning the review the user recorded falls
///    due. The only one not derived from a cycle: its day comes from a date
///    they set, it fires once like the late check, and its words still name no
///    date — the day lives in the plan, not in the notification.
///
/// The late check is enforced without storing anything, and the absence of state
/// is the design rather than an accident. A window's fire time is a pure function
/// of the window and the settings, and it does not move while the window stands:
/// so "arm it only if its moment is still ahead" is enough to make it fire at
/// most once. An earlier version recorded an armed-marker in the settings and used
/// it to skip a second arming — and because applying a plan cancels whatever is
/// not in it, that marker cancelled the very alarm it had just recorded, so the
/// notification never arrived at all. The state was doing nothing the schedule
/// could not do by itself.
library;

/// The reminder slots the platform arms alarms for.
///
/// The index is the alarm's request code on the Android side, so it is part of
/// the stored contract rather than a display detail: changing the order of these
/// values silently re-labels alarms that are already armed.
enum ReminderKind {
  dailyNudge(1),
  headsUp(2),
  lateCheck(3),

  /// The one reminder this app did not derive from a cycle: the annual review
  /// falls due a year after the date the user recorded, so its day comes from a
  /// date they set rather than from anything the record predicted.
  annualReview(4);

  const ReminderKind(this.alarmId);

  /// Stable id on the platform. Used as the alarm's request code and as the
  /// notification id, which is what makes cancelling one kind possible at all.
  final int alarmId;

  /// The notification texts, fixed in code rather than built from the record.
  ///
  /// This is deliberate and it is a privacy decision, not laziness. A scheduled
  /// notification carries its text from the moment it is armed, and Android
  /// stores whatever the alarm system needs about it outside the app's encrypted
  /// database — so a body that named a date from the record would be health data
  /// written in the clear. These strings are the same for every user, which is
  /// why they can be shown on a lock screen without telling anyone anything.
  String get title => switch (this) {
        ReminderKind.dailyNudge => 'Cystera',
        ReminderKind.headsUp => 'Cystera',
        ReminderKind.lateCheck => 'Cystera',
        ReminderKind.annualReview => 'Cystera',
      };

  String get body => switch (this) {
        // No record content: not the day, not the symptoms, not the date.
        ReminderKind.dailyNudge => 'A minute to record how today went?',
        ReminderKind.headsUp =>
          'Your period may be due in the next few days — the window is open.',
        ReminderKind.lateCheck =>
          'Your period is past the window Cystera had. Log it when it starts, or '
              'switch mode if your cycles are changing.',
        // The day is the one date this app knows about this feature, and it is
        // deliberately not written here: the text is the same for everyone, so
        // it says the review is due without saying which day that is.
        ReminderKind.annualReview => 'Your annual review is due today.',
      };

  /// One line for the settings screen, so what each one will say is checkable
  /// before it is switched on.
  String get sample => switch (this) {
        ReminderKind.dailyNudge => '“A minute to record how today went?”',
        ReminderKind.headsUp => '“Your period may be due in the next few days.”',
        ReminderKind.lateCheck => '“Your period is past the window Cystera had.”',
        ReminderKind.annualReview => '“Your annual review is due today.”',
      };
}

/// The stored reminder preferences, plus the one piece of state that stops the
/// nagging.
class ReminderSettings {
  const ReminderSettings({
    this.dailyNudgeEnabled = false,
    this.dailyNudgeMinutes = defaultDailyMinutes,
    this.headsUpEnabled = true,
    this.headsUpDaysBefore = 2,
    this.lateCheckEnabled = true,
    this.lateCheckGraceDays = 2,
    this.annualReviewEnabled = true,
  });

  /// Evening, because the point of the nudge is to catch a day that is nearly
  /// over — and because a reminder to log how you feel at 9am has nothing to
  /// say about the day ahead of it.
  static const int defaultDailyMinutes = 20 * 60;

  /// Off, and it is the only one that starts off. A notification asking for
  /// something is a bigger ask than one telling you what your own record says,
  /// and the app should not make that ask on the user's behalf. The others are
  /// on by default because they only ever fire when there is something behind
  /// them — a window, or a review date the user recorded themselves — and the
  /// user is looking at the settings screen where they can read what they say.
  final bool dailyNudgeEnabled;

  /// Minutes after local midnight. Stored as an int rather than a `TimeOfDay`
  /// so the model stays pure Dart and the settings survive a locale change.
  final int dailyNudgeMinutes;

  final bool headsUpEnabled;
  final int headsUpDaysBefore;
  final bool lateCheckEnabled;
  final int lateCheckGraceDays;

  /// On, like the two window reminders rather than like the nudge: it only ever
  /// fires when the user has recorded a review date, and by then they have asked
  /// for one by setting it. Switching it off is still a switch, because a
  /// reminder about a health appointment is the sort of thing some people do not
  /// want arriving on a lock screen.
  final bool annualReviewEnabled;

  static const List<int> headsUpChoices = [1, 2, 3];
  static const List<int> lateCheckChoices = [1, 2, 3];

  ReminderSettings copyWith({
    bool? dailyNudgeEnabled,
    int? dailyNudgeMinutes,
    bool? headsUpEnabled,
    int? headsUpDaysBefore,
    bool? lateCheckEnabled,
    int? lateCheckGraceDays,
    bool? annualReviewEnabled,
  }) =>
      ReminderSettings(
        dailyNudgeEnabled: dailyNudgeEnabled ?? this.dailyNudgeEnabled,
        dailyNudgeMinutes: dailyNudgeMinutes ?? this.dailyNudgeMinutes,
        headsUpEnabled: headsUpEnabled ?? this.headsUpEnabled,
        headsUpDaysBefore: headsUpDaysBefore ?? this.headsUpDaysBefore,
        lateCheckEnabled: lateCheckEnabled ?? this.lateCheckEnabled,
        lateCheckGraceDays: lateCheckGraceDays ?? this.lateCheckGraceDays,
        annualReviewEnabled: annualReviewEnabled ?? this.annualReviewEnabled,
      );

  /// `20:00`, in the device's own format rather than a 24-hour assumption.
  String get dailyNudgeLabel {
    final hour = dailyNudgeMinutes ~/ 60;
    final minute = dailyNudgeMinutes % 60;
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = hour < 12 ? 'am' : 'pm';
    return '$h:${minute.toString().padLeft(2, '0')} $suffix';
  }

  bool get anyEnabled =>
      dailyNudgeEnabled || headsUpEnabled || lateCheckEnabled ||
      annualReviewEnabled;

  Map<String, Object?> encode() => {
        'dailyNudgeEnabled': dailyNudgeEnabled,
        'dailyNudgeMinutes': dailyNudgeMinutes,
        'headsUpEnabled': headsUpEnabled,
        'headsUpDaysBefore': headsUpDaysBefore,
        'lateCheckEnabled': lateCheckEnabled,
        'lateCheckGraceDays': lateCheckGraceDays,
        'annualReviewEnabled': annualReviewEnabled,
      };

  /// Reads the stored row, and treats a value it does not recognise as absent.
  ///
  /// Deliberately not a cast: `as bool?` throws on a string, and throwing here
  /// would take out the settings screen for a row written by another version of
  /// the app. A preference is not worth a crash, and "not recognised" and "never
  /// set" deserve the same answer anyway — the default. Same for a number outside
  /// the range the settings screen offers: `lateCheckGraceDays: 400` is not a
  /// preference this build can honour, so it reads as the default rather than
  /// arming an alarm a year out.
  static ReminderSettings decode(Map<String, Object?>? map) {
    if (map == null) return const ReminderSettings();
    return ReminderSettings(
      dailyNudgeEnabled: switch (map['dailyNudgeEnabled']) {
        final bool value => value,
        _ => false,
      },
      dailyNudgeMinutes: switch (map['dailyNudgeMinutes']) {
        final int value when value >= 0 && value < 24 * 60 => value,
        _ => defaultDailyMinutes,
      },
      headsUpEnabled: switch (map['headsUpEnabled']) {
        final bool value => value,
        _ => true,
      },
      headsUpDaysBefore:
          _oneOf(headsUpChoices, map['headsUpDaysBefore']) ?? 2,
      lateCheckEnabled: switch (map['lateCheckEnabled']) {
        final bool value => value,
        _ => true,
      },
      lateCheckGraceDays:
          _oneOf(lateCheckChoices, map['lateCheckGraceDays']) ?? 2,
      annualReviewEnabled: switch (map['annualReviewEnabled']) {
        final bool value => value,
        _ => true,
      },
    );
  }

  /// A stored offset, but only if it is one of the offsets this build offers.
  static int? _oneOf(List<int> choices, Object? value) =>
      value is int && choices.contains(value) ? value : null;

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.dailyNudgeEnabled == dailyNudgeEnabled &&
      other.dailyNudgeMinutes == dailyNudgeMinutes &&
      other.headsUpEnabled == headsUpEnabled &&
      other.headsUpDaysBefore == headsUpDaysBefore &&
      other.lateCheckEnabled == lateCheckEnabled &&
      other.lateCheckGraceDays == lateCheckGraceDays &&
      other.annualReviewEnabled == annualReviewEnabled;

  @override
  int get hashCode => Object.hash(
        dailyNudgeEnabled,
        dailyNudgeMinutes,
        headsUpEnabled,
        headsUpDaysBefore,
        lateCheckEnabled,
        lateCheckGraceDays,
        annualReviewEnabled,
      );
}
