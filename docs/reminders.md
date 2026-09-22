# Reminders, and what they are not allowed to be

Four notifications, and the rules that keep them from becoming a nag. Every claim
here is enforced somewhere — a pure function in `lib/core/reminders/reminder_plan.dart`,
a Kotlin object with no state of its own, or the device test that reads Android's own
answer back — and the places where a claim is only a convention are named as such.

## A reminder may not say anything about the record

This is a privacy decision before it is a design one. A scheduled notification carries
its text from the moment it is armed, and Android stores what the alarm system needs
about it *outside* the app's encrypted database. A body like "your period was due
Tuesday" would therefore be health data written in the clear, sitting next to a
database that is carefully encrypted — and on a phone whose lock screen is the thing
someone else is holding.

So the alarm carries only an id, a fixed title and a fixed body — the same for every
user of the app — and the receiver posts exactly what it was handed:

```
Cystera
A minute to record how today went?
```

and

```
Cystera
Your period may be due in the next few days — the window is open.
```and

```
Cystera
Your period is past the window Cystera had. Log it when it starts, or switch mode if your cycles are changing.
```

and

```
Cystera
Your annual review is due today.
```

None of those come from the record, and the third one is careful to be about the
*app's* window rather than about the user's body. The fourth is the only one whose
*fire time* is a date — the review date moves the alarm, never the words. `test/reminder_plan_test.dart` has a
test that fails if any of those strings ever grows a date: it walks every kind there is.

The same reasoning is why there is no notification package in `pubspec.yaml`. Every
scheduled-notification library stores the notification's text somewhere a receiver can
read while the app is dead — a JSON file, a database, shared preferences. The design
here is inverted instead: **nothing is written down between arming and firing**, which
is also why there is no `RECEIVE_BOOT_COMPLETED` permission and no boot receiver. A
restart clears the alarms, and the settings screen says so in those words rather than
quietly arming something on the user's behalf.

## The four kinds

| | When | On by default |
|---|---|---|
| **The daily nudge** | Once a day, at a time the user picks, at 08:00/12:00/18:00/20:00/22:00 | no |
| **The heads-up** | In the morning, 1–3 days before the earliest day of the window | yes |
| **The late check** | In the morning, 1–3 days after the latest day of the window | yes |
| **The annual review** | In the morning of the day the review falls due | yes |

The nudge is off by default because a notification asking for something is a bigger ask
than one telling you what your own record says, and that ask is the user's to make. The
others are on because they only ever fire when there is something behind them — a
window, or a date the user recorded themselves — and the screen they
are switched on from prints what each one will say before it is switched on.

The nudge's hour is deliberately *not* the 09:00 the record reminders use. The nudge is
about a day that is nearly over; the other two are about a day that has begun. Keeping
them separate also means switching the nudge off cannot move the other two, and the
settings screen can say "in the morning" and be right.

## One late check per window, with nothing stored

This is the rule the feature exists for: **a period that has not arrived produces one
notification and then silence.** The people who most often have late periods are the
ones who least need to be reminded about it, and a reminder that repeats while a period
is late is a nag with an alarm attached.

It is enforced without any state at all, and the absence of state is the design rather
than an accident. A window's fire time is a pure function of the window and the settings,
and it does not move while the window stands; so "arm it only if its moment is still
ahead" is enough to make it fire at most once. An earlier version of this stored an
"already armed" marker in the settings and used it to skip a second arming — and because
applying a plan cancels whatever is not in it, that marker cancelled the very alarm it
had just recorded, so the notification never arrived at all. A test that asserted the
marker was honoured passed while the feature was broken; what caught it was asking what
a user would see. The state was doing nothing the schedule could not do by itself.

The unit of "once" is the window, so a period being logged earns a new check, correctly:
the window moves forward, and the new moment is genuinely new state on the phone. That
is a test, not a comment.

## A window that does not exist arms nothing

When the prediction refuses, the reminders are **cancelled**, not replaced by a generic
nag. Telling someone "your period may be due" when the app has already decided it cannot
say that is the confident wrongness this app is written against. Each of the five
refusals carries its own sentence onto the settings row, reusing the prediction's own
title rather than inventing a second vocabulary for the same fact, and perimenopause mode
gets its own wording — it is not a refusal but a different kind of answer.

Nothing is armed in the past either. A reminder whose moment has gone is skipped, with
the reason shown, rather than fired late or fired immediately on the next launch. That
same rule is what makes the late check happen once: its moment does not move, so once it
is behind you there is nothing left to arm.

And a day that is already written down does not get a nudge asking about it. Anything
counts — a symptom, "nothing today", a note, a period day — because the questionthe nudge asks is "did you write anything down", not "did you write down enough". The
nudge waits for tomorrow instead.

## The one reminder not derived from a cycle

The annual review falls due a year after the date the user recorded, so it is armed
from a date rather than predicted — and everything else about it follows the same
rules. Its moment is 09:00 on the due day, one-shot like the late check. A due day
whose morning has passed is skipped rather than fired late, with the reason on the row
— and once the day itself is behind them, that reason points at the overdue line the
annual review section shows: an unrecorded due day is said out loud there, beside the
picker that clears it, rather than in a second place that would then have to be kept in
step. A record with no review date arms nothing and says so on the row, next to that
same picker. Changing or clearing the
date re-plans and re-applies straight away, the same contract `setReminders` has, so
the screen and the phone are never left disagreeing about whether this year's reminder
exists. And the notification still names no date: the day lives in the plan and in the
alarm's timing, never in the words, which is why the test that hunts for digits in
reminder text walks this kind too.

## Inexact on purpose

Alarms use `setAndAllowWhileIdle`, never `setExactAndAllowWhileIdle`. The exact-alarm
permissions (`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`) are ones Play grants to alarm
clocks and calendars, and asking for one in order to nudge someone about their cycle
would be this app asking for a capability it does not need. The cost is real and is
stated in the footnote of the settings section: Android may deliver a reminder late —
usually within the hour, longer in Doze, and the system may hold it until the phone is
next awake.

The full release manifest for M5 is three permissions:

```
android.permission.POST_NOTIFICATIONS      declared by this app, requested on first use
android.permission.USE_BIOMETRIC           from local_auth
android.permission.USE_FINGERPRINT         from local_auth
```

`POST_NOTIFICATIONS` is asked for when a reminder is switched *on*, not at launch: the
app does not ask for a capability it is not about to use, and if the answer is no the
switch stays off and the row says why instead of promising a notification that cannot
arrive. The guard in `tool/no_internet_check.dart` still passes, so there is still no
`INTERNET` permission in the release build.

## Asked-for and actually-armed are different claims

The settings panel shows both: the plan on the left, and the badge on the right from
Android's own answer about what is armed. Whether an alarm exists is a `PendingIntent`
that either resolves or does not, so "a reminder is set" is checkable rather than a
claim — and the panel has words for the cases where the two disagree, including "the app
asked this phone to arm it, and the phone says it has not".

Two things came out of writing the device test for that panel.

**A `PendingIntent` record outlives the alarm it stood for.** After a one-shot fires, the
record is still there — `FLAG_NO_CREATE` keeps finding it — so the slot went on reporting
itself as armed forever, which is a reminder claiming to be coming months after it
arrived. The receiver now disarms a fired one-shot (cancelling the alarm and the
`PendingIntent`, leaving the notification the user is looking at alone), while the daily
nudge re-arms its own next occurrence in the same breath, because that is the only moment
the process is guaranteed to exist between two of them. The device test checks both: after
`trigger`, the one-shot is gone and the nudge is still there.

**The channel's `lockscreenVisibility` is deprecated and ignored on API 26+.** Android
stores it as `-1000` (`VISIBILITY_NO_OVERRIDE`) no matter what the channel was created
with — the dump below shows exactly that. What actually keeps the text off a locked
screen is the notification's own visibility, which is set to `VISIBILITY_SECRET` on every
reminder, and that *is* visible in the dump as `vis=SECRET`. Had the test asserted the
channel field, it would have been checking a value the platform never kept.

## What the device proved

`integration_test/reminders_test.dart` runs against `PlatformReminderScheduler` — the same
class the app uses — and reads the answers back from Android. On the API 36 emulator:

```
REMINDERS: armed=[dailyNudge, headsUp, lateCheck] notificationsEnabled=true
```Six tests: the phone holds exactly what the plan names;
a new plan replaces rather than adds; a fired one-shot disarms itself while the daily
nudge arms its next day; the annual review slot arms, is read back from Android, and
disarms itself when it fires; slot 9 is refused rather than armed; and cancelling
clears the alarms.

The notification itself is read back from the shell, because `PendingIntent.send()` is
fire-and-forget — a notification dropped for a missing runtime permission or a bad small
icon looks, from inside the test, exactly like one that arrived:

```bash
flutter test integration_test/reminders_test.dart -d <device-id> \
  --dart-define=cystera_hold_for_readback=true
# In a second shell, while the run is going — it is the test build that gets asked:
adb shell pm grant com.onekit.cystera android.permission.POST_NOTIFICATIONS
adb shell dumpsys notification --noredact | grep -i cystera
```

```
NotificationRecord(... pkg=com.onekit.cystera ... id=1 ... channel=cystera_reminders
  flags=AUTO_CANCEL|SILENT category=reminder vis=SECRET))
    android.title=String (Cystera)
    android.text=String (A minute to record how today went?)
NotificationRecord(... pkg=com.onekit.cystera ... id=2 ... vis=SECRET))
    android.text=String (Your period may be due in the next few days — the window is open.)
NotificationRecord(... pkg=com.onekit.cystera ... id=4 ... channel=cystera_reminders
  flags=AUTO_CANCEL category=reminder vis=SECRET))
    android.title=String (Cystera)
    android.text=String (Your annual review is due today.)
    android.showWhen=Boolean (false)
```

That is the receiver posting from the alarm's own intent, with the small icon resolved, on
the channel the app created, marked secret for the lock screen. The run then leaves the
app's data alone and the last test cancels the alarms and the notifications with them.

The id=4 lines were read back the same way on 22 September 2026 (moto g06 power, Android
15), inside the second hold: on `cystera_reminders`, `vis=SECRET`, `showWhen=false`, and
the text the privacy section promises — *Your annual review is due today.* — with no date
anywhere in what the platform reports. Read back rather than asserted: the test itself
knows only that slot 4 fired and then stopped reporting itself as armed.

The `pm grant` line above earns its place. On a freshly wiped phone the first readback
captured nothing at all — `notificationsEnabled=false`, six tests green, zero records in
`dumpsys` — which is the drop the sentence above warns about, observed rather than
hypothesised: the receiver checks the permission and posts nothing. The app itself asks
when a reminder is switched on; a shell run has to ask from the shell.

## How the planning is wired

`planReminders` is pure: a forecast, the settings, a moment, and whether today has
anything recorded in it. The controller recomputes it rather than caching it, so the
screen and the platform cannot be shown two different plans, and applies it after the
record is read, never before.

`apply` *replaces*: everything not in the plan is cancelled, so a window that moved cannot
leave yesterday's reminder behind it. An unchanged plan is not re-applied, so a screen
rebuild does not call into Android three times for nothing. Reminder syncs are also
serialised, one after another: the signature above only works if the sync that wrote it
has finished, and a launch that is already unlocked refreshes twice — which meant two
syncs racing, both calling into Android for the same alarms, and a stale one able to land
*after* the forced sync that replaced it. That was a test failure in M5, not a
theoretical one.

While the app is locked, nothing is applied at all. The plan needs the record, and the
record is not readable then; the alarms already on the phone are left alone, because
locking the app must not delete the user's reminders. A test asserts exactly that.

## Known limits

- **A restart loses the alarms until the app is next opened.** Nothing is stored, so
  there is nothing to restore. The settings screen says so instead of pretending.
- **Delivery is inexact.** Stated on the screen, not hidden.
- **The channel's lock-screen field is not the protection.** The notification's own
  visibility is, and it is set on every reminder.
- **No notification actions.** Tapping a reminder opens the app; there is no "log it"
  button on the notification, because an action would have to carry something about the
  record to be useful.
- **The text is the same for everyone.** That is the price of not writing health data
  outside the encrypted database, and it is a price worth paying.
