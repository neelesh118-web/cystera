/// The languages the app offers, and who translated them.
///
/// The list is the top sixty-five spoken languages by native speakers, which is a
/// decision with a consequence worth stating: it is a *speaker* ranking, not an
/// Android-install ranking, so it includes languages with relatively few phones and
/// omits some with many. The alternative ranking would reach more installs per
/// translation hour. This one was chosen deliberately, and this comment is where
/// that choice is recorded rather than in someone's memory.
///
/// [machineTranslated] is not a nicety. Every one of these except English was
/// produced by machine, and the app says so in its own language before the user
/// picks one — because this app's entire argument is that its copy never claims
/// more than the code does, and a sentence nobody checked is exactly that claim
/// broken. A human-reviewed locale sets this flag false and the notice disappears.
library;

/// One offered language.
class AppLocale {
  const AppLocale({
    required this.code,
    required this.englishName,
    required this.nativeName,
    this.machineTranslated = true,
  });

  /// The language tag handed to Flutter and to `intl`. Not a country: the app has
  /// no region-specific content, and pinning a region would make a speaker of the
  /// same language in another country fall back to English for no reason.
  final String code;

  /// For somebody reading the English UI who is looking for their language.
  final String englishName;

  /// Written in the language itself. A list that only shows English names is
  /// useless to the person who needs it most.
  final String nativeName;

  /// True when no human has reviewed the copy. See the note at the top of the file.
  final bool machineTranslated;

  /// The language subtag, which is what a [`Locale`] matches on when a stored tag
  /// carries a script and the device asks for only a language. `zh-Hans` and
  /// `zh-Hant` share the subtag `zh`, so this alone is not a key — [code] is.
  String get languageCode => code.split('-').first;
}

/// English first: it is the source text, the fallback for every missing key, and
/// the language every tester reads.
const List<AppLocale> appLocales = [
  AppLocale(code: 'en', englishName: 'English', nativeName: 'English', machineTranslated: false),
  AppLocale(code: 'zh-Hans', englishName: 'Chinese (Mandarin, Simplified)', nativeName: '简体中文'),
  AppLocale(code: 'hi', englishName: 'Hindi', nativeName: 'हिन्दी'),
  AppLocale(code: 'es', englishName: 'Spanish', nativeName: 'Español'),
  AppLocale(code: 'ar', englishName: 'Arabic (Standard)', nativeName: 'العربية'),
  AppLocale(code: 'bn', englishName: 'Bengali', nativeName: 'বাংলা'),
  AppLocale(code: 'pt', englishName: 'Portuguese', nativeName: 'Português'),
  AppLocale(code: 'ru', englishName: 'Russian', nativeName: 'Русский'),
  AppLocale(code: 'ja', englishName: 'Japanese', nativeName: '日本語'),
  AppLocale(code: 'pa', englishName: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ'),
  AppLocale(code: 'de', englishName: 'German', nativeName: 'Deutsch'),
  AppLocale(code: 'jv', englishName: 'Javanese', nativeName: 'Basa Jawa'),
  AppLocale(code: 'ko', englishName: 'Korean', nativeName: '한국어'),
  AppLocale(code: 'fr', englishName: 'French', nativeName: 'Français'),
  AppLocale(code: 'te', englishName: 'Telugu', nativeName: 'తెలుగు'),
  AppLocale(code: 'mr', englishName: 'Marathi', nativeName: 'मराठी'),
  AppLocale(code: 'tr', englishName: 'Turkish', nativeName: 'Türkçe'),
  AppLocale(code: 'ta', englishName: 'Tamil', nativeName: 'தமிழ்'),
  AppLocale(code: 'vi', englishName: 'Vietnamese', nativeName: 'Tiếng Việt'),
  AppLocale(code: 'ur', englishName: 'Urdu', nativeName: 'اردو'),
  AppLocale(code: 'id', englishName: 'Indonesian', nativeName: 'Bahasa Indonesia'),
  AppLocale(code: 'gu', englishName: 'Gujarati', nativeName: 'ગુજરાતી'),
  AppLocale(code: 'fa', englishName: 'Persian', nativeName: 'فارسی'),
  AppLocale(code: 'bho', englishName: 'Bhojpuri', nativeName: 'भोजपुरी'),
  AppLocale(code: 'zh-Hant', englishName: 'Chinese (Traditional)', nativeName: '繁體中文'),
  AppLocale(code: 'th', englishName: 'Thai', nativeName: 'ไทย'),
  AppLocale(code: 'it', englishName: 'Italian', nativeName: 'Italiano'),
  AppLocale(code: 'ha', englishName: 'Hausa', nativeName: 'Hausa'),
  AppLocale(code: 'kn', englishName: 'Kannada', nativeName: 'ಕನ್ನಡ'),
  AppLocale(code: 'ml', englishName: 'Malayalam', nativeName: 'മലയാളം'),
  AppLocale(code: 'my', englishName: 'Burmese', nativeName: 'မြန်မာ'),
  AppLocale(code: 'or', englishName: 'Odia', nativeName: 'ଓଡ଼ିଆ'),
  AppLocale(code: 'as', englishName: 'Assamese', nativeName: 'অসমীয়া'),
  AppLocale(code: 'pl', englishName: 'Polish', nativeName: 'Polski'),
  AppLocale(code: 'uk', englishName: 'Ukrainian', nativeName: 'Українська'),
  AppLocale(code: 'yo', englishName: 'Yoruba', nativeName: 'Yorùbá'),
  AppLocale(code: 'mai', englishName: 'Maithili', nativeName: 'मैथिली'),
  AppLocale(code: 'am', englishName: 'Amharic', nativeName: 'አማርኛ'),
  AppLocale(code: 'om', englishName: 'Oromo', nativeName: 'Oromoo'),
  AppLocale(code: 'ne', englishName: 'Nepali', nativeName: 'नेपाली'),
  AppLocale(code: 'sd', englishName: 'Sindhi', nativeName: 'سنڌي'),
  AppLocale(code: 'si', englishName: 'Sinhala', nativeName: 'සිංහල'),
  AppLocale(code: 'sw', englishName: 'Swahili', nativeName: 'Kiswahili'),
  AppLocale(code: 'km', englishName: 'Khmer', nativeName: 'ខ្មែរ'),
  AppLocale(code: 'ff', englishName: 'Fula', nativeName: 'Fulfulde'),
  AppLocale(code: 'ig', englishName: 'Igbo', nativeName: 'Igbo'),
  AppLocale(code: 'rw', englishName: 'Kinyarwanda', nativeName: 'Ikinyarwanda'),
  AppLocale(code: 'zu', englishName: 'Zulu', nativeName: 'isiZulu'),
  AppLocale(code: 'ms', englishName: 'Malay', nativeName: 'Bahasa Melayu'),
  AppLocale(code: 'su', englishName: 'Sundanese', nativeName: 'Basa Sunda'),
  AppLocale(code: 'ceb', englishName: 'Cebuano', nativeName: 'Cebuano'),
  AppLocale(code: 'fil', englishName: 'Filipino', nativeName: 'Filipino'),
  AppLocale(code: 'nl', englishName: 'Dutch', nativeName: 'Nederlands'),
  AppLocale(code: 'ro', englishName: 'Romanian', nativeName: 'Română'),
  AppLocale(code: 'el', englishName: 'Greek', nativeName: 'Ελληνικά'),
  AppLocale(code: 'hu', englishName: 'Hungarian', nativeName: 'Magyar'),
  AppLocale(code: 'cs', englishName: 'Czech', nativeName: 'Čeština'),
  AppLocale(code: 'sv', englishName: 'Swedish', nativeName: 'Svenska'),
  AppLocale(code: 'he', englishName: 'Hebrew', nativeName: 'עברית'),
  AppLocale(code: 'az', englishName: 'Azerbaijani', nativeName: 'Azərbaycan'),
  AppLocale(code: 'kk', englishName: 'Kazakh', nativeName: 'Қазақша'),
  AppLocale(code: 'uz', englishName: 'Uzbek', nativeName: 'Oʻzbek'),
  AppLocale(code: 'sr', englishName: 'Serbian', nativeName: 'Српски'),
  AppLocale(code: 'so', englishName: 'Somali', nativeName: 'Soomaali'),
  AppLocale(code: 'ku', englishName: 'Kurdish', nativeName: 'Kurdî'),
];

/// The languages whose script runs right to left. Used to set `textDirection` on
/// the picker row and to assert in a test that the list did not forget one — a
/// right-to-left name drawn left to right is the most visible possible bug in a
/// language list.
const Set<String> rightToLeftLanguages = {
  'ar', 'ur', 'fa', 'sd', 'he', 'ku',
};

/// Finds an entry by its full tag. Matching is case-insensitive on the script
/// subtag, because a stored value like `zh-hans` is the same language as
/// `zh-Hans` and treating it as unknown would silently switch someone back to
/// English for a capitalisation.
AppLocale? localeByCode(String? code) {
  if (code == null) return null;
  final wanted = code.toLowerCase();
  for (final locale in appLocales) {
    if (locale.code.toLowerCase() == wanted) return locale;
  }
  // A device locale carries a region the catalogue does not list — `pt-BR`,
  // `en-GB`. The language part is what matters here: the app has no
  // region-specific content, and matching the region too would drop a Portuguese
  // speaker to English over a hyphen.
  final language = wanted.split('-').first;
  for (final locale in appLocales) {
    if (locale.languageCode == language) return locale;
  }
  return null;
}
