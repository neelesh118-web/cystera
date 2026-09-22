package com.onekit.cystera

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.time.ZoneId
import java.time.ZonedDateTime

/// Reminders, with no dependency and no state of their own.
///
/// This app does not use a notification package, and the reason is not
/// minimalism: every scheduled-notification library stores the notification's
/// *text* somewhere outside the encrypted database so that a receiver can post it
/// while the app is dead. This record's notification text would then be health
/// data written in the clear — "your period is late" sitting in a JSON file next
/// to a database that is carefully encrypted.
///
/// So the design is inverted: the alarm carries only an id, a fixed title and a
/// fixed body, all of which are the same for every user of the app and none of
/// which come from the record. When the alarm fires, [ReminderReceiver] posts
/// exactly what it was handed. Nothing is written down between arming and firing,
/// which also means nothing survives a reboot — stated in the settings screen
/// rather than hidden, because a reminder that quietly stops after a restart is
/// worse than one that says it will.
///
/// Two phone-facing consequences, both deliberate:
///
///  * **Inexact, on purpose.** `setAndAllowWhileIdle` is the strongest alarm
///    available without `SCHEDULE_EXACT_ALARM`, which Play restricts to alarms
///    and calendars. Android may therefore deliver a reminder late — usually
///    within the hour, longer in Doze — and the settings screen says so instead of
///    promising a time the app cannot keep.
///  * **Hidden on the lock screen.** The channel is created with
///    `VISIBILITY_SECRET`, so the notification does not appear on a locked phone
///    at all. Anyone holding the phone sees nothing; the sound is the only hint,
///    and a sound is not a record.
object Reminders {

    const val CHANNEL_ID = "cystera_reminders"

    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_REPEAT_DAILY = "repeatDaily"
    const val EXTRA_HOUR = "hour"
    const val EXTRA_MINUTE = "minute"

    const val ACTION_PREFIX = "com.onekit.cystera.REMINDER."

    /// The id the daily nudge uses, matched in Dart by `ReminderKind.alarmId`.
    const val DAILY_NUDGE_ID = 1

    /// The actions this app will ever schedule. Anything else is refused rather
    /// than armed, so a bad id cannot leave an alarm nothing can cancel.
    val KNOWN_IDS = setOf(1, 2, 3, 4)

    private fun notificationManager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun alarmManager(context: Context): AlarmManager =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    /// Idempotent, and called from both sides of the process boundary: the
    /// receiver may be the first thing to run after an update, when the channel
    /// does not exist yet, and a notification with no channel is silently dropped
    /// on API 26+.
    fun ensureChannel(context: Context) {
        val manager = notificationManager(context)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Reminders",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Reminders you set in Cystera. They never contain " +
                "anything you recorded."
            // The whole point: nothing from this app appears on a locked screen.
            lockscreenVisibility = Notification.VISIBILITY_SECRET
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    /// The intent's action and class are what identify an alarm; the extras are
    /// not. That is what lets [existing] find an armed slot and cancel it without
    /// knowing anything about what it was going to say.
    fun intent(context: Context, id: Int): Intent =
        Intent(context, ReminderReceiver::class.java).setAction(ACTION_PREFIX + id)

    /// `FLAG_IMMUTABLE` is required by API 31+ and, more importantly here, keeps
    /// the intent un-editable by anything that intercepts it. The same flags must
    /// be used to look an alarm up again, or `getBroadcast` will not match it.
    fun pendingIntent(context: Context, id: Int, extras: Intent.() -> Unit = {}): PendingIntent {
        val intent = intent(context, id).apply(extras)
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /// The armed alarm for a slot, or null. This is the app's *only* record that a
    /// reminder is set, and it lives in the system rather than on disk.
    fun existing(context: Context, id: Int): PendingIntent? =
        PendingIntent.getBroadcast(
            context,
            id,
            intent(context, id),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE,
        )

    fun isArmed(context: Context, id: Int): Boolean = existing(context, id) != null

    fun armedIds(context: Context): List<Int> = KNOWN_IDS.filter { isArmed(context, it) }

    /// Arms a slot. Inexact and allowed in Doze: `setAndAllowWhileIdle`, never
    /// `setExactAndAllowWhileIdle`, which needs a permission Play grants only to
    /// alarm clocks and calendars.
    fun arm(
        context: Context,
        id: Int,
        atMillis: Long,
        title: String,
        body: String,
        repeatDaily: Boolean,
        hour: Int,
        minute: Int,
    ) {
        ensureChannel(context)
        val pending = pendingIntent(context, id) {
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_REPEAT_DAILY, repeatDaily)
            putExtra(EXTRA_HOUR, hour)
            putExtra(EXTRA_MINUTE, minute)
        }
        alarmManager(context).setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            atMillis,
            pending,
        )
    }

    /// Cancels the alarm and the `PendingIntent` behind it, and leaves any
    /// notification already posted for the slot alone.
    ///
    /// This is what a one-shot calls after it has fired, and the reason is not
    /// bookkeeping: a `PendingIntent` record outlives the alarm it stood for, so
    /// without this the slot would go on answering "armed" forever — the settings
    /// panel would report a reminder as still coming, long after it arrived and
    /// long after it could ever come again.
    fun disarm(context: Context, id: Int) {
        existing(context, id)?.let { pending ->
            alarmManager(context).cancel(pending)
            pending.cancel()
        }
    }

    /// Cancels the alarm *and* any notification already posted for the slot.
    ///
    /// Both halves matter: leaving a delivered notification behind after the user
    /// switched the reminder off looks exactly like the switch not working.
    fun cancel(context: Context, id: Int) {
        disarm(context, id)
        notificationManager(context).cancel(id)
    }

    fun cancelAll(context: Context) {
        for (id in KNOWN_IDS) cancel(context, id)
    }

    /// When the same local time comes round again.
    ///
    /// Computed in the phone's zone rather than by adding 24 hours, so a clock
    /// change moves the reminder with the clock instead of an hour away from it.
    fun nextDaily(atMillis: Long, hour: Int, minute: Int, zone: ZoneId): Long? {
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null
        val now = ZonedDateTime.now(zone)
        var next = now.toLocalDate().atTime(hour, minute).atZone(zone)
        if (!next.isAfter(now)) next = next.plusDays(1)
        // Guard against arming something that is already in the past after a
        // clock change, which would fire immediately and look like a bug.
        return if (next.toInstant().toEpochMilli() > atMillis) {
            next.toInstant().toEpochMilli()
        } else {
            next.plusDays(1).toInstant().toEpochMilli()
        }
    }

    /// Posts the notification. No record content: the strings handed in are the
    /// fixed ones from `ReminderKind`, identical for every user of the app.
    fun post(context: Context, id: Int, title: String, body: String) {
        ensureChannel(context)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val tap = launch?.let {
            PendingIntent.getActivity(
                context,
                id,
                it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            // Belt and braces behind the channel's own visibility: on API 26+ the
            // channel decides, and this is what a reader of the code sees.
            .setVisibility(Notification.VISIBILITY_SECRET)
            .setShowWhen(false)
            .apply { if (tap != null) setContentIntent(tap) }
            .build()
        notificationManager(context).notify(id, notification)
    }

    /// Whether the OS will deliver anything from this app at all.
    fun notificationsEnabled(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED &&
                notificationManager(context).areNotificationsEnabled()
        } else {
            notificationManager(context).areNotificationsEnabled()
        }
}
