# Rules for the release build.
#
# ---------------------------------------------------------------------------
# SQLCipher
# ---------------------------------------------------------------------------
# The encrypted-database library reaches its native code through JNI, and JNI
# resolves methods by *name*. If R8 renames or removes those classes, the
# database layer fails — and it fails only in release builds, only on a device,
# and only at the moment the database is opened. That is the worst shape a bug
# can have, so the classes are kept.
#
# Checked against the actual shipped artifact rather than assumed: `strings` on
# classes.dex of the release APK shows the plugin's descriptors
# (Lnet/zetetic/database/sqlcipher/...) and its native method names
# (nativeOpen, nativeExecute, nativeClose, nativeFinalize) intact. sqflite_sqlcipher
# 3.4.1 uses Zetetic's newer `net.zetetic.database.sqlcipher` namespace, which is
# the one that matters here — `net.sqlcipher.**` is the older generation and is
# kept only so a downgrade or an older plugin copy cannot silently break.
-keep class net.zetetic.database.sqlcipher.** { *; }
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }

# Keep native method names on anything that declares them.
-keepclasseswithmembernames class * {
    native <methods>;
}

# ---------------------------------------------------------------------------
# Keystore-backed storage
# ---------------------------------------------------------------------------
# flutter_secure_storage uses androidx.security's EncryptedSharedPreferences,
# which touches platform classes reflectively.
-keep class androidx.security.crypto.** { *; }

# ---------------------------------------------------------------------------
# Flutter plugins
# ---------------------------------------------------------------------------
# Plugin classes are instantiated by generated registrant code; keeping them
# means a release-only "plugin not registered" failure cannot happen.
-keep class io.flutter.plugins.** { *; }
-keep class com.davidmartos96.sqflite_sqlcipher.** { *; }

# Readable stack traces in release crash reports. The app reports crashes to a
# file the user can read rather than to a server, so the names matter.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
