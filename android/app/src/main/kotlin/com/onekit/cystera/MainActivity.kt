package com.onekit.cystera

import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyInfo
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyStore

/// The three platform features the Dart side cannot do on its own.
///
/// All three are privacy features rather than conveniences, which is why they live
/// in Kotlin and are covered by tests on the Dart side of the channel:
///
///  * **The discreet launcher entry.** `activity-alias` lets one app publish two
///    launcher icons and enable exactly one. Switching is silent to the user but
///    visible to the launcher, which may take a few seconds to catch up.
///  * **`FLAG_SECURE`.** Blocks screenshots, screen recording, and — the part
///    people forget — the thumbnail of the app in the recent-apps switcher. For a
///    cycle record that thumbnail is the realistic leak.
///  * **The keystore report.** What the hardware *actually did* with the key that
///    protects the vault, read back from the platform rather than inferred from a
///    plugin's version number. `SECURITY_LEVEL_TRUSTED_ENVIRONMENT` means the key
///    cannot be read out of the phone even by the app itself; `SOFTWARE` means it
///    is only a file with a nice name, which is what an emulator gives you.
///
/// The reminders channel is here for the same reason as the other three:
/// scheduling an inexact alarm and reading Android's own view of what is armed are
/// platform facts, and the app's settings screen shows them rather than repeating
/// what the app believes it did. See `Reminders.kt` for why there is no
/// notification dependency.
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.onekit.cystera/device"
        const val REMINDER_CHANNEL = "com.onekit.cystera/reminders"
        const val DEFAULT_ALIAS = "com.onekit.cystera.LauncherDefault"
        const val DISCREET_ALIAS = "com.onekit.cystera.LauncherDiscreet"
        const val NOTIFICATION_PERMISSION_REQUEST = 4711
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDiscreet" -> result.success(isEnabled(DISCREET_ALIAS))

                    "setDiscreet" -> {
                        val discreet = call.argument<Boolean>("discreet") ?: false
                        // Enabled/disabled together: two launcher icons must never
                        // both be visible, or both disappear.
                        setEnabled(DISCREET_ALIAS, discreet)
                        setEnabled(DEFAULT_ALIAS, !discreet)
                        result.success(null)
                    }

                    "setScreenSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: true
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }

                    "keystoreReport" -> result.success(keystoreReport())

                    // What this installed package asks the system for, read
                    // back from PackageManager rather than from the repository's
                    // manifest: the merged manifest is what ships, so a permission
                    // a dependency added during the merge appears here — in the
                    // receipt — rather than only in a file nobody re-reads.
                    // Read-only; it requests and grants nothing.
                    "requestedPermissions" -> result.success(requestedPermissions())

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REMINDER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val id = call.argument<Int>("id") ?: -1
                        val atMillis = call.argument<Long>("atMillis") ?: -1L
                        if (id !in Reminders.KNOWN_IDS || atMillis <= 0) {
                            // Refused rather than armed: an alarm this app cannot
                            // identify is an alarm nothing can cancel.
                            result.error("badRequest", "unknown reminder id $id", null)
                            return@setMethodCallHandler
                        }
                        Reminders.arm(
                            this,
                            id,
                            atMillis,
                            call.argument<String>("title") ?: "Cystera",
                            call.argument<String>("body") ?: "",
                            call.argument<Boolean>("repeatDaily") ?: false,
                            call.argument<Int>("hour") ?: -1,
                            call.argument<Int>("minute") ?: -1,
                        )
                        result.success(null)
                    }

                    "cancelAll" -> {
                        Reminders.cancelAll(this)
                        result.success(null)
                    }

                    "status" -> result.success(
                        mapOf(
                            "notificationsEnabled" to Reminders.notificationsEnabled(this),
                            "armed" to Reminders.armedIds(this),
                        ),
                    )

                    // Fires the alarm's own intent, so the delivery path is
                    // exercised exactly as Android would exercise it. Used by the
                    // "send me one now" button and by the device test, because an
                    // inexact alarm is not something a test can wait for.
                    "trigger" -> {
                        val id = call.argument<Int>("id") ?: -1
                        val pending = Reminders.existing(this, id)
                        if (pending == null) {
                            result.success(false)
                        } else {
                            pending.send()
                            result.success(true)
                        }
                    }

                    "requestPermission" -> result.success(requestNotificationPermission())

                    else -> result.notImplemented()
                }
            }
    }

    /// Asks for `POST_NOTIFICATIONS` when the user switches a reminder on.
    ///
    /// At the point of use rather than at launch: the permission is meaningless
    /// until there is a reminder to deliver, and this app does not ask for things
    /// it is not about to use. Returns whether notifications are enabled now — on
    /// API 32 and below there is no runtime permission involved at all.
    private fun requestNotificationPermission(): Boolean {
        if (!Reminders.notificationsEnabled(this) &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
            // The answer comes back through onRequestPermissionsResult, so this
            // reports the state as it is now and Dart re-reads it after the
            // dialog closes rather than trusting this value.
            return false
        }
        return Reminders.notificationsEnabled(this)
    }

    /// Everything AndroidKeyStore holds for this app, with the properties that
    /// decide how strong the protection really is.
    ///
    /// Read-only: it opens the keystore and asks `KeyInfo` about each entry. It
    /// creates nothing, so calling it can never change the state it reports.
    private fun keystoreReport(): Map<String, Any?> {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val report = mutableMapOf<String, Any?>(
            "packageName" to packageName,
            "model" to Build.MODEL,
            "hardware" to Build.HARDWARE,
            "sdkInt" to Build.VERSION.SDK_INT,
            // A guess, and labelled as one. It exists so a report can be read
            // without knowing which machine produced it: an emulator's "secure
            // hardware" is a directory on the host, and saying so is the whole
            // point of this probe.
            "emulator" to (Build.FINGERPRINT.contains("generic") ||
                Build.FINGERPRINT.contains("emulator") ||
                Build.PRODUCT.contains("sdk") ||
                Build.HARDWARE.contains("goldfish") ||
                Build.HARDWARE.contains("ranchu")),
            "strongBoxSupported" to
                packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE),
            // Whether the phone has a lock screen at all. The secure-storage plugin
            // changes what it asks of the keystore based on this answer, so a report
            // without it cannot be interpreted.
            "deviceSecure" to (keyguard?.isDeviceSecure == true),
            "keys" to emptyList<Map<String, Any?>>(),
        )
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore")
            keyStore.load(null)
            report["keys"] = keyStore.aliases().toList().map { describeKey(keyStore, it) }
        } catch (error: Exception) {
            report["error"] = error.toString()
        }
        return report
    }

    private fun requestedPermissions(): Map<String, Any?> {
        return try {
            val info = packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            val names = info.requestedPermissions?.toList() ?: emptyList()
            val flags = info.requestedPermissionsFlags?.toList() ?: emptyList()
            val granted = HashMap<String, Boolean>()
            for (index in names.indices) {
                val flag = if (index < flags.size) flags[index] else 0
                granted[names[index]] =
                    (flag and PackageInfo.REQUESTED_PERMISSION_GRANTED) != 0
            }
            mapOf("permissions" to names, "granted" to granted)
        } catch (error: Exception) {
            // The receipt prints this as "not read" rather than falling back to a
            // claim the app wrote about itself.
            mapOf("error" to error.toString())
        }
    }

    private fun describeKey(keyStore: KeyStore, alias: String): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>("alias" to alias)
        try {
            val key = keyStore.getKey(alias, null)
            if (key == null) {
                out["error"] = "the alias holds no key"
                return out
            }
            out["algorithm"] = key.algorithm
            val info = KeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
                .getKeySpec(key, KeyInfo::class.java) as KeyInfo
            out["keySize"] = info.keySize
            out["userAuthenticationRequired"] = info.isUserAuthenticationRequired
            // -1 is the interesting value: it means the key may be used only after
            // an explicit authentication, every single time.
            out["userAuthenticationTimeoutSeconds"] =
                info.userAuthenticationValidityDurationSeconds
            out["invalidatedByBiometricEnrollment"] = info.isInvalidatedByBiometricEnrollment
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Bit 0: device credential (PIN/pattern/password). Bit 1: strong
                // biometric. Which of those may unlock the key is a user-facing
                // difference, so it is reported rather than flattened to a boolean.
                out["userAuthenticationType"] = info.userAuthenticationType
            }
            @Suppress("DEPRECATION")
            val insideHardware = info.isInsideSecureHardware
            out["insideSecureHardware"] = insideHardware
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                out["securityLevel"] = info.securityLevel
            } else {
                // Pre-31 has no security level; the old boolean is the best answer.
                out["securityLevel"] = if (insideHardware) 1 else 0
            }
        } catch (error: Exception) {
            out["error"] = error.toString()
        }
        return out
    }

    private fun component(alias: String) = ComponentName(packageName, alias)

    private fun isEnabled(alias: String): Boolean =
        packageManager.getComponentEnabledSetting(component(alias)) ==
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED

    private fun setEnabled(alias: String, enabled: Boolean) {
        // DONT_KILL_APP: toggling an alias restarts the app by default, which
        // would throw the user out of the screen where they flipped the switch.
        packageManager.setComponentEnabledSetting(
            component(alias),
            if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
