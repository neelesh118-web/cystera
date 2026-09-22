/// The three words people use for the same condition, and the fact that changed in
/// 2026.
///
/// This file exists because of a real event, not a style preference. On 12 May 2026
/// polycystic ovary syndrome was renamed **polyendocrine metabolic ovarian syndrome**
/// — PMOS — in a process led by Professor Helena Teede at Monash University, published
/// in The Lancet, and endorsed by more than fifty patient and professional bodies
/// including the Endocrine Society, ASRM and ACOG. Two things about it matter to this
/// app:
///
///  * The reason given was that the old name described the least of the condition and
///    pointed at the wrong organ: a related study found **no increase in abnormal
///    ovarian cysts**, while the metabolic and hormonal parts — the parts that make it
///    worth tracking — went unnamed. That is the same mistake this app is built to
///    avoid in its own copy, so it is not going to keep making it out of habit.
///  * The change has a **three-year transition** and lands fully in the 2028
///    international guideline. A user walking into an appointment this year will meet
///    a doctor, a lab report and a hospital system that all still say PCOS. Saying
///    only the new name would be as misleading as saying only the old one.
///
/// So the app carries all three and explains the difference, which is the only honest
/// option. The names themselves are [ConditionName]s and the sentences about them live
/// behind `AppText`, because a person whose language is not English needs the
/// *explanation* translated even though the abbreviations are not translated in
/// practice.
///
/// What this file deliberately does not contain is any claim about which name is
/// right, or that PCOD means something different from the other two. That question is
/// contested and this app does not settle it — see `docs/terms.md`.
library;

/// Where a name stands: the current official name, the one it replaced, or a third
/// word in wide use that the rename did not address.
enum NameStatus {
  /// The name adopted in May 2026.
  official,

  /// The name it replaced. Still on every existing medical record.
  former,

  /// A word in wide use, especially in South Asia, that is neither of the other two.
  colloquial,
}

/// One word for the condition.
class ConditionName {
  const ConditionName({
    required this.id,
    required this.label,
    required this.status,
  });

  /// The stored value, and the key its expansion is looked up by. Lower case and
  /// stable, like every other id in this codebase.
  final String id;

  /// The abbreviation as it is written on a lab form or spoken in a clinic. Not
  /// translated anywhere, which is a fact about medicine rather than a choice: a
  /// Chinese endocrinologist writes 多囊卵巢综合征 and indexes it under PCOS.
  final String label;

  final NameStatus status;
}

/// Every name the app knows, most current first.
const List<ConditionName> kConditionNames = [
  ConditionName(id: 'pmos', label: 'PMOS', status: NameStatus.official),
  ConditionName(id: 'pcos', label: 'PCOS', status: NameStatus.former),
  ConditionName(id: 'pcod', label: 'PCOD', status: NameStatus.colloquial),
];

// There is deliberately no `kLeadConditionNameId` here. "Which name does the app
// lead with" and "which name is current" are the same question, and [NameStatus]
// already answers it — a second constant would be a second answer waiting to
// disagree with the first.

/// The rename, as dates and numbers rather than as a sentence.
///
/// Kept apart from the prose so a test can pin the facts and a translator can write
/// the sentence — and so a fact that changes has one place to change in.
class ConditionRename {
  const ConditionRename._();

  /// When the new name was announced.
  static const String announced = '12 May 2026';

  /// Where the name-change process was published.
  static const String publishedIn = 'The Lancet';

  /// How long the transition runs, and what it ends at. Both matter: a user needs to
  /// know the old name is not wrong yet.
  static const int transitionYears = 3;
  static const String fullyImplemented = '2028 international guideline';

  /// How many patient and professional organisations took part.
  static const int organisations = 56;

  /// Who it affects, in the app's own words rather than as a statistic to sell with.
  static const String affects = 'about 1 in 8 women';
}

/// The name with this id, or null. Null rather than a default, so a stored value
/// from a future version arrives as "not known" instead of silently becoming PMOS.
ConditionName? conditionNameById(String? id) {
  if (id == null) return null;
  for (final name in kConditionNames) {
    if (name.id == id) return name;
  }
  return null;
}
