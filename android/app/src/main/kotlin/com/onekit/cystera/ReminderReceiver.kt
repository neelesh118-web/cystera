package com.onekit.cystera

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.ZoneId

/// Posts a reminder when its alarm fires, and re-arms itself if it is a daily one.
///
/// This runs in the app's process, started by the system if the app is not
/// running, and it deliberately touches nothing else: no database, no key, no
/// Flutter engine. It cannot read the record even if it wanted to — the key needs
/// the user's PIN and is not on this path — which is precisely why the app's
/// privacy story survives having notifications at all. Everything it needs is in
/// the intent, and everything in the intent is the same for every user.
///
/// Not exported, so only this app's own alarms can trigger it.
class ReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (!action.startsWith(Reminders.ACTION_PREFIX)) return
        val id = action.removePrefix(Reminders.ACTION_PREFIX).toIntOrNull() ?: return
        if (id !in Reminders.KNOWN_IDS) return

        val title = intent.getStringExtra(Reminders.EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(Reminders.EXTRA_BODY) ?: return

        Reminders.post(context, id, title, body)

        // A daily reminder has to arm its own next occurrence: there is no
        // repeating state anywhere, so this is what keeps it daily, and it is why
        // the app reschedules nothing on its own behalf.
        val repeatDaily = intent.getBooleanExtra(Reminders.EXTRA_REPEAT_DAILY, false)
        if (repeatDaily) {
            val hour = intent.getIntExtra(Reminders.EXTRA_HOUR, -1)
            val minute = intent.getIntExtra(Reminders.EXTRA_MINUTE, -1)
            val atMillis = System.currentTimeMillis()
            val next = Reminders.nextDaily(atMillis, hour, minute, ZoneId.systemDefault())
            if (next != null) {
                val pending = Reminders.pendingIntent(context, id) {
                    putExtra(Reminders.EXTRA_TITLE, title)
                    putExtra(Reminders.EXTRA_BODY, body)
                    putExtra(Reminders.EXTRA_REPEAT_DAILY, true)
                    putExtra(Reminders.EXTRA_HOUR, hour)
                    putExtra(Reminders.EXTRA_MINUTE, minute)
                }
                val alarmManager =
                    context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                // The next day is armed here rather than in Dart, because the app
                // is very likely not running: this is the only moment the process
                // is guaranteed to exist between two reminders.
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    next,
                    pending,
                )
            }
        } else {
            // A one-shot has now had its one shot, and the slot is cleared so the
            // phone's own answer stops claiming otherwise. The notification stays:
            // this removes the alarm, not what the user is looking at.
            Reminders.disarm(context, id)
        }
    }
}
