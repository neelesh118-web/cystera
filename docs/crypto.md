# Cystera security design

This app makes one promise it cannot take back: **the record stays on the phone.** That
promise is only worth something if it holds on disk, in the keystore, and in the backup
file — not just in the UI copy. This document says what is actually protecting the data,
how much it costs the user, and where the protection genuinely stops.

Everything below is implemented in `lib/core/crypto/`, `lib/core/secure/` and
`lib/core/lock/`, and every claim here has a test in `test/`.

## The five secrets

| Secret | Where it lives | What it protects |
| --- | --- | --- |
| Database key (32 random bytes) | Keystore-wrapped, or sealed by the PIN | The SQLCipher database |
| PIN verifier (HMAC) | `flutter_secure_storage` | Nothing by itself — it is a comparison |
| Device secret (32 random bytes) | Keystore, generated once | The wrapped database key |
| Backup passphrase | Nowhere — only the user | A backup file that leaves the phone |
| Biometric/PIN gate | OS | Convenience and shoulder-surfing |

The database key is the only one that matters. Everything else either wraps it or gates
access to the app that can unwrap it.

## Unlock: one derivation, not two

```
master   = PBKDF2-HMAC-SHA256('cystera.pin.v1' + pin, salt, iterations)
verifier = HMAC-SHA256(master, 'cystera.pin.verify.v1')
wrapKey  = HKDF-SHA256(master, salt: deviceSecret, info: 'cystera.dbkey.v1')
```

The obvious design — two independent PBKDF2 runs, one for the verifier and one for the
wrap key — costs exactly twice as much per unlock for no security benefit, because both
outputs come from the same secret. Measured on this machine, a pure-Dart PBKDF2 at the
interactive count is **418 ms** for a single derivation, so the naive version would put
most of a second of dead time in front of every unlock for nothing. HKDF is cheap and
the work has already been done once.

**No dependency on PBKDF2 for the PIN's real strength.** The `deviceSecret` is 32 random
bytes that never leave the keystore. An attacker who copies the wrapped key out of the
app's storage cannot mount an offline PIN search *at all*, at any iteration count,
because they are missing 256 bits. The iteration count is there to slow down someone
running guesses against the app on the device itself; the rate limit below is what
really stops that.

Verified by `test/crypto_test.dart` and `test/pin_test.dart`: the same PIN with a
different device secret yields a different wrap key and cannot open the database; a wrong
PIN yields a wrap key that fails the box's authentication.

## Measured cost

`dart run tool/bench_kdf.dart`, median of 3, one core, this dev machine:

```
PBKDF2-HMAC-SHA256, 32-byte key, one core:
   20000 iterations    157 ms
   30000 iterations    253 ms
   50000 iterations    577 ms
  120000 iterations   1621 ms
  300000 iterations   3732 ms

PIN unlock (30000 iterations, one derivation)    418 ms
Backup seal + open (300000 iterations, 200 KB)   9013 ms
```

A phone CPU was assumed to be roughly 1.5–3× slower, so these were read as ~0.6–1.2 s for
an unlock and ~4.5 s each way for a backup. The device test now prints the real figures
rather than an estimate based on this dev box (see the table below): on a Moto G06 Power,
**setup 2.0 s, unlock 1.2 s, export 5.2 s, restore 6.3 s**. The estimates were close
enough that the UI decisions they drove still hold. Both numbers changed the UI rather
than being written down and ignored:

- **Unlock at 30 000.** Chosen because it is the figure a person feels on every open. The
  pad shows a busy state and accepts no further digits while it derives.
- **Backup at 300 000.** Deliberately ~10× the interactive cost, because the file is the
  one artifact that leaves the phone and it has *no attempt limit protecting it*. Both the
  export and the restore screens show a non-dismissible progress dialog that says the wait
  is intentional, because a screen that appears frozen for five seconds is how people
  decide an app has crashed and force-close it mid-write.

The iteration count is recorded in the file header and honored on open, so **retuning
these constants never breaks an existing backup** — an old file keeps opening at the cost
it was written with.

## Rate limiting a wrong PIN

`AttemptPolicy` is separate from the verifier because they fail differently: the verifier
protects against someone who has the storage, the policy protects against someone holding
the phone. Five free attempts, then 30 s, 1 min, 5 min, 15 min, 1 hour, repeating. It is
persisted, so killing the app does not reset it, and the count clears on success — whoever
just typed the right PIN could already open the app, so leaving the escalation in place
would only punish someone who forgot and then remembered.

## The backup file

```
CYS1 | version | kdfId | iterations(u32 LE) | salt(16) | nonce(12) | ciphertext | mac(16)
```

AES-256-GCM, key from PBKDF2 over the passphrase. The header carries its own parameters,
and it is passed to the cipher as GCM additional authenticated data — so the parameters
themselves are inside the tag and editing them is detected *as* tampering.

That is a guarantee we hold rather than one we currently lean on: today every header field
either feeds the key derivation (salt, iterations) or is validated before any work
happens (version, KDF id), so a tampered file already fails either way — as
`MalformedBoxException` before deriving, or as `BadSecretException` from the tag. It
matters for the field someone adds later that does neither. `test/crypto_test.dart`
pins down which layer catches which byte, so the distinction cannot quietly rot.

A hostile iteration count is also clamped to 1000–5,000,000 before any KDF work, so a
file cannot ask this app to run a billion-round derivation.

The file contains the schema version, the wrapped database key and the records — which
means **the backup file is exactly as sensitive as the record itself.** Nothing in this
design makes a weak passphrase safe, so the UI asks for one and says so plainly rather
than accepting "1234". A lost passphrase is unrecoverable, and the app says that before
the file is written, not after.

## What a restore actually does

Import **replaces** everything currently on the phone — it is not a merge, and saying
"restore" without saying "replace" is how someone loses a month of logging. The screen
carries that sentence next to the button. The restore report states when the backup was
made, so a five-month-old file is visibly five months old instead of silently overwriting
newer data.

The order is **stage, prove, swap**, and it is the whole safety argument:

1. The incoming database is written to a neighbouring `.restoring` file.
2. That file is opened with the key the payload carries, through SQLCipher, before
   anything on the phone is touched. If the key and the database do not match — a truncated
   or edited file, or a bug in this app — the restore is refused and the existing record is
   left exactly as it was.
3. Only then are the old files moved aside and the new one put in place. They are moved,
   not deleted, and the old copies are only removed once the swap has happened, so a
   failure in between still leaves the record recoverable on disk.

One window remains, and it is named rather than hidden: if the process dies between the
swap and the vault adopting the new key, the file is the restored one while the stored key
is the old one. The app reports that as an unreadable record, and the backup file — which
still holds the matching key — is the way back. Nothing is unrecoverable, which is the
property worth keeping.

### The bug this section was rewritten for

The first version of this code got restore wrong twice, and only a device test found it.
`BackupPayload.parse` required the database bytes to begin with the plaintext SQLite header
`"SQLite format 3\0"` — and a SQLCipher database never does, because it is ciphertext. So
**every restore failed**, in the one flow the whole feature exists for. The host tests
passed because the test fixture fabricated a plaintext SQLite file: the assertion and the
fixture shared the same wrong assumption, so they agreed with each other and with nothing
else. The same version deleted the phone's database *before* writing the new one, so a bad
file would have cost the user their record.

Both are fixed. The fixture is now ciphertext-shaped and asserts that it is, the parser
validates structure only, and the matching of key to database happens in step 2 above where
it can actually be answered. `integration_test/device_test.dart` runs the whole thing on a
real keystore and a real SQLCipher — it is the only test that could have caught this, and
it did.

## What the keystore actually did

The app tells the user the record is encrypted with a key held in the phone's secure
hardware. That sentence is easy to write and, until this was measured, impossible to check:
on an emulator the "hardware" keystore is software, and **every other test in the suite
passes identically on both.** So `integration_test/device_test.dart` asks the platform for
`KeyInfo` of each AndroidKeyStore entry and reports it, and `lib/core/platform/keystore_probe.dart`
turns that into a value the app shows in Settings (see the next section).

Two runs, same test, same app:

| | Moto G06 Power | emulator (API 36) |
| --- | --- | --- |
| `Build.HARDWARE` / API | `mt6768`, API 35 | `ranchu`, API 36 |
| Key protecting the vault | RSA 2048-bit, **secure hardware (TEE)** | RSA 2048-bit, **software only** |
| StrongBox (dedicated chip) | absent | absent |
| Lock screen on the phone | **none** | none |
| Enrolled biometrics | none | none |
| setup / unlock | 1972 ms / 1225 ms | 2564 ms / 1197 ms |
| export / restore | 5223 ms / 6290 ms | 6858 ms / 7973 ms |

What the table is worth:

- **The hardware claim is now a measurement, not an assumption.** On the phone the key is
  inside the TEE, which is what "this key cannot leave the phone" means. On the emulator
  the same probe says *software only* — the app's claim would have been false there, and
  nothing else in the suite could have told us.
- **There is exactly one vault key, and it is RSA.** `flutter_secure_storage` 11 defaults
  to RSA-OAEP 2048 (`<packageId>.FlutterSecureStoragePluginKeyOAEP`) wrapping a 128-bit AES
  key that encrypts the values; the AES keystore key the plugin also knows how to make is
  only used on its authenticated paths. Read from the plugin's Android source, then
  confirmed against the device, because its README and its behaviour have diverged before.
- **The default path never asks the user to authenticate before using that key** — the RSA
  path sets no user-authentication requirement at all, on any phone. So the keystore
  protects the vault against someone who takes the storage, not against someone holding the
  unlocked phone. The PIN wrap is what makes the record depend on a secret only the user
  has; the rate limit is what makes guessing it slow.
- **Biometric unlock is still unproven.** No fingerprints are enrolled on either machine,
  and on a phone with no lock screen none can be enrolled, so `BiometricManager` reports
  nothing available and the prompt was never shown. That is a limit of the evidence, not a
  pass: `test/lock_controller_test.dart` covers the policy, and no test yet covers a real
  fingerprint on real hardware.
- **The timings differ by more than the hardware suggests.** Unlock is within 3% between
  the two machines while the backup KDF is 25% slower on the emulator, because export and
  restore do ten times the derivations and stop being dominated by fixed startup cost. It is
  a reminder that a single number from one machine is a bad basis for a UX decision.
- **And they are not stable on one machine either.** Re-running the same test on the same
  phone while it was busy — two Gradle builds and two installs in the preceding minutes —
  measured `setup=4037ms unlock=2287ms export=12749ms restore=13825ms`, roughly double
  across the board, with no change to the KDF or the file. So the figures in the table are
  a reading, not a constant: a hot or busy phone is about twice as slow, and the screens
  that say "this takes a few seconds" are built to be true for the slow end.

### What the app now says about it, and where that comes from

For a while the probe's answer existed only in this document and in the device test's output — the
app itself said nothing about where the key lives, so the one claim in Settings that is easy to get
wrong ("inside the phone's secure hardware") was the one nothing on screen checked. It is now wired
to the storage panel: `LockController.storageReport()` asks the probe every time the panel is opened,
and `VaultKeyProtection` turns the answer into the words on the row.

The row is the **first** fact on that panel, because everything below it is about what the key is
protecting, and it has four shapes:

| The phone says | The row says |
| --- | --- |
| TEE | in the phone's secure hardware — *it cannot be read off this phone; it is used without asking for your PIN or a fingerprint, so what it guards against is a copy of the storage rather than someone holding the unlocked phone.* |
| StrongBox | in the dedicated security chip |
| Software | **software only on this phone** — *the key is a file protected by the phone's own disk encryption…* plus what is actually protecting the record right now: the PIN wrap, or, with the lock off, that disk encryption is all there is |
| Not reported, error, or a missing key | said plainly, including the emulator note and the phone-with-no-lock-screen note |

Two rules are enforced in that code rather than left to whoever writes the copy:

- **An unreadable answer never reads as a reassurance.** A platform with no channel, a keystore that
  throws, a level the platform declines to name, and a key that is not in the keystore at all are four
  different sentences, and none of them claims hardware protection. `unknown` is deliberately not
  "hardware": failing closed is the only useful direction for a claim like this.
- **Two keys are judged by the weakest.** The plugin can hold an RSA wrapping key and an AES key, and
  the panel reports the protection of the weaker one, because a conjunction is the only honest summary
  of "the vault's protection".

The sentence that matters most is the one about what hardware does *not* cover. The default
secure-storage path sets no user-authentication requirement on that key — so hardware-backed or not,
the keystore protects against someone who copies the storage, not against someone holding the
unlocked phone. Saying "secure hardware" and stopping there would be the app taking credit for the
PIN's work, which is why the row continues past its own headline.

Measured on the emulator, from the same device run that already reported the keystore's own summary:

```
DEVICE settings says: "software only on this phone" — The key is a file protected by the
phone's own disk encryption rather than by security hardware, so anything that can read the
storage can read the key. The lock is off on this record, so the database key is kept here in
that form — on this phone that is disk encryption and nothing more.
```

The assertion beside it is the one worth keeping: on a machine whose vault keys are not hardware
backed, the panel must be in its warning weight. A soft key that reads as a neutral fact is the
failure mode this whole section is about, and it is now a failing test rather than a paragraph
someone could skip.

### The probe's own bug, caught the same way

The first device run failed — on the probe. It matched the vault key with
`alias.startsWith('<packageId>.FlutterSecureStoragePluginKey')`, which is true of *both*
aliases the plugin creates, and the keystore's iteration order returned the RSA one to an
assertion that expected AES. The fix was not a cleverer string match but a better shape:
the report lists **every** plugin-owned key, the summary describes all of them, and
`allVaultKeysHardwareBacked` is the conjunction — because the protection of the vault is
the protection of its weakest key, and a probe that picks one arbitrarily is how a
security claim ends up resting on whichever entry the platform happened to return first.

## Where the protection honestly stops

- **A rooted device with the app unlocked is out of scope.** The database key is in memory
  while the app is open; nothing here defeats a live memory dump or a debugger attached to
  the running process. The design assumes the OS is not already hostile.
- **Biometrics are a UI gate, not a key.** The biometric prompt releases the same
  keystore-wrapped key; someone who can add a fingerprint to an unlocked phone can open
  the app. Enrolling a new biometric does not re-derive anything.
- **Losing the device secret loses the record** unless a backup exists. If the Keystore
  entry is destroyed (factory reset, some OS upgrades, a restore to a different phone from
  a cloud backup that stripped it), the wrapped key is unopenable. This is the cost of
  "even we cannot read it", and it is why the backup exists and is nagged about.
- **No screenshot of the screenshots setting.** `FLAG_SECURE` covers the app while it is
  focused; it cannot stop a second phone pointed at the screen.
- **No forward secrecy on the PIN.** Changing the PIN re-wraps the same database key, so
  someone who learned the old PIN *and* had copied the old wrapped key can still derive the
  database key. A full re-key of the SQLCipher database on PIN change is the honest fix and
  is not implemented yet.
- **Android's own cloud backup is switched off** (`allowBackup=false` plus extraction
  rules), because the OS copying the encrypted database to a user's Drive without them
  choosing to is exactly the surprise this app exists to avoid. The CI guard fails the
  build if that is ever re-enabled.

## The guard

`tool/no_internet_check.dart` runs as part of `flutter test` and in CI. It fails the build
on `INTERNET` in any non-dev manifest **including the merged release manifest** — the only
place a transitive dependency's permission shows up — on cleartext traffic, on network
constructs in `lib/`, and on `allowBackup` being re-enabled. It was verified against the
real release artifact, not just against source:

```
aapt dump permissions build/app/outputs/flutter-apk/app-release.apk      package: com.onekit.cystera
    uses-permission: name='android.permission.USE_BIOMETRIC'
    uses-permission: name='android.permission.USE_FINGERPRINT'
    uses-permission: name='com.onekit.cystera.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

The two biometric permissions come from `local_auth` and are normal (non-runtime,
prompt-free) permissions. The third is Flutter's own signature-level one for local
broadcasts. No `INTERNET`, no storage, no notifications.

`android:allowBackup="false"` and `dataExtractionRules` are checked in the merged release
manifest too, because the OS copying the encrypted database into a user's cloud backup
without them choosing to is the exact surprise this app exists to avoid.

## The launcher icon is the phone's, not ours

The discreet entry is an `activity-alias`, and which alias is enabled is a **component
state owned by the phone**: a launcher refresh, a device restore, or an OS update can put
both back to their manifest defaults while the stored preference still says discreet. So
startup asks the platform what is actually enabled and corrects it, rather than displaying
a setting that has quietly stopped being true. `isDiscreet` is a question, not a switch we
set once and trust.

The cost of aliases-only is a tooling one: Flutter finds the launch activity by looking for
a `<activity>` carrying MAIN/LAUNCHER, and there is none in the release manifest, so
`flutter run` and `flutter test integration_test/` fail with "launch activity not found".
`android/app/src/debug/AndroidManifest.xml` adds a plain launcher entry for development
builds only. The artifact users install is unchanged.

## SQLCipher and R8

The database is opened through `sqflite_sqlcipher` with the raw 32-byte key (not a
passphrase), so there is no second KDF in the storage path. R8 is enabled for release, and
`android/app/proguard-rules.pro` keeps `net.zetetic.database.**` — the plugin's actual
package, verified by dumping the release DEX, since an earlier rule named the plugin's
legacy namespace and would have silently stripped JNI-visible members.
