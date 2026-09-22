import 'package:flutter/material.dart';

import '../../core/i18n/app_text.dart';
import '../../core/log/log_controller.dart';
import '../../core/meds/dose_history.dart';
import '../../core/meds/med_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';
import '../log/undo_toast.dart';

/// The list the user keeps.
///
/// A sheet rather than a screen: it is opened from the daily card, it is a list of
/// things and three fields, and putting it on a route would make editing the list a
/// journey away from the day being logged. Editing one medication opens its dose
/// history in the same sheet — the list and the dated line it draws are two views
/// of one record, and a second screen between them is how the two start to differ.
///
/// There is no catalogue behind this and no search over drug names. A shipped list
/// of medications would be a medical claim, wrong for most of the world the moment
/// it shipped — and the point of this screen is that the user's own words for their
/// own things are enough. A dose is free text for the same reason: the app does not
/// know what a dose is and will not guess.
void showMedListSheet(BuildContext context, LogController log) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.tokens.surface,
    builder: (_) => _MedListSheet(log: log),
  );
}

class _MedListSheet extends StatefulWidget {
  const _MedListSheet({required this.log});

  final LogController log;

  @override
  State<_MedListSheet> createState() => _MedListSheetState();
}

class _MedListSheetState extends State<_MedListSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _dose = TextEditingController();
  MedKind _kind = MedKind.medication;

  /// The medication being edited, or null when the form is adding one.
  Medication? _editing;

  /// The entry being composed: what happened, the day it is claimed for
  /// (defaulting to today, because recording a change on the day it happened
  /// is the common case and a picker for it would be a step nobody takes),
  /// and its dose in the same free text as the list's field — prefilled from
  /// it, since the wording in force is the usual answer for a backdated start.
  DoseEventKind _eventKind = DoseEventKind.started;
  DateTime? _eventDay;
  final TextEditingController _eventDose = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _eventDose.dispose();
    super.dispose();
  }

  void _startEdit(Medication medication) {
    setState(() {
      _editing = medication;
      _name.text = medication.name;
      _dose.text = medication.dose ?? '';
      _kind = medication.kind;
      _eventKind = DoseEventKind.started;
      _eventDay = widget.log.today;
      _eventDose.text = medication.dose ?? '';
    });
  }

  void _startAdd() {
    setState(() {
      _editing = null;
      _name.clear();
      _dose.clear();
      _kind = MedKind.medication;
      _eventKind = DoseEventKind.started;
      _eventDay = null;
      _eventDose.clear();
    });
  }

  Future<void> _save() async {
    final log = widget.log;
    final editing = _editing;
    await writeAndOfferUndo(context, log, () async {
      await log.saveMedication(
        id: editing?.id,
        name: _name.text,
        kind: _kind,
        dose: _dose.text,
      );
    });
    if (!mounted) return;
    if (log.error == null) _startAdd();
    setState(() {});
  }

  Future<void> _archive(Medication medication) async {
    await writeAndOfferUndo(
      context,
      widget.log,
      () => widget.log.archiveMedication(medication.id),
    );
    if (!mounted) return;
    if (_editing?.id == medication.id) _startAdd();
    setState(() {});
  }

  Future<void> _pickEventDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDay ?? widget.log.today,
      firstDate: DateTime(2000),
      // A claim about a day that has not happened yet is refused here and by
      // the controller alike — the picker's own rule is the earlier of the two.
      lastDate: widget.log.today,
    );
    if (picked == null || !mounted) return;
    setState(() => _eventDay = picked);
  }

  Future<void> _addEvent() async {
    final editing = _editing;
    if (editing == null) return;
    final log = widget.log;
    await writeAndOfferUndo(context, log, () => log.addDoseEvent(
          medicationId: editing.id,
          kind: _eventKind,
          day: _eventDay ?? log.today,
          dose: _eventKind == DoseEventKind.stopped ? null : _eventDose.text,
        ));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _removeEvent(MedDoseEvent event) async {
    await writeAndOfferUndo(
      context,
      widget.log,
      () => widget.log.removeDoseEvent(event.id),
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final log = widget.log;
    final medications = log.medications;

    return Padding(
      padding: EdgeInsets.only(
        left: AppTheme.gutter,
        right: AppTheme.gutter,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppTextScope.of(context).medCardTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Your list, in your words. Nothing here is checked against a '
              'database of drugs, and the dose is free text on purpose.',
              style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 16),
            if (medications.isEmpty)
              Text(
                'Nothing on the list yet.',
                style: TextStyle(color: t.textFaint, fontSize: 13.5),
              )
            else
              for (final medication in medications)
                _MedListRow(
                  medication: medication,
                  editing: _editing?.id == medication.id,
                  onEdit: () => _startEdit(medication),
                  onArchive: () => _archive(medication),
                ),
            const SizedBox(height: 18),
            Divider(color: t.border, height: 1),
            const SizedBox(height: 16),
            Text(
              _editing == null
                  ? AppTextScope.of(context).addOne
                  : 'Edit ${_editing!.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _Field(
              controller: _name,
              label: 'Name',
              hint: 'e.g. Vitamin D',
              enabled: log.canWrite,
            ),
            const SizedBox(height: 10),
            _Field(
              controller: _dose,
              label: 'Dose (optional)',
              hint: 'e.g. 1000 IU, one tablet, two pumps',
              enabled: log.canWrite,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final kind in MedKind.values) ...[
                  Expanded(
                    child: _KindChoice(
                      kind: kind,
                      selected: _kind == kind,
                      onTap: () => setState(() => _kind = kind),
                    ),
                  ),
                  if (kind != MedKind.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _kind.blurb,
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.4),
            ),
            if (log.error case final error?) ...[
              const SizedBox(height: 10),
              Text(
                error,
                style: TextStyle(color: t.accent, fontSize: 12.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: log.canWrite ? _save : null,
                    child: Text(_editing == null ? 'Add to the list' : 'Save changes'),
                  ),
                ),
                if (_editing != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _startAdd,
                    child: Text(AppTextScope.of(context).cancel),
                  ),
                ],
              ],
            ),
            if (_editing != null) ...[
              const SizedBox(height: 16),
              Divider(color: t.border, height: 1),
              const SizedBox(height: 12),
              Text(
                'DOSE HISTORY',
                style: TextStyle(
                  color: t.textFaint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Start, change, or stop — each entry dated by you, drawn as one '
                'line per medication in the doctor report.',
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              if (log.doseEventsFor(_editing!.id).isEmpty)
                Text(
                  'Nothing dated yet.',
                  style: TextStyle(color: t.textFaint, fontSize: 13),
                )
              else
                for (final event in log.doseEventsFor(_editing!.id))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${dayLabel(event.day, inYear: log.today.year)} — '
                            '${event.summary}',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed:
                              log.canWrite ? () => _removeEvent(event) : null,
                          tooltip: 'Remove this entry',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          icon: Icon(
                            Icons.close_outlined,
                            size: 18,
                            color: t.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final kind in DoseEventKind.values) ...[
                    Expanded(
                      child: _EventChoice(
                        label: kind.word,
                        selected: _eventKind == kind,
                        onTap: () => setState(() => _eventKind = kind),
                      ),
                    ),
                    if (kind != DoseEventKind.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: log.canWrite ? _pickEventDay : null,
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  dayLabel(_eventDay ?? log.today, inYear: log.today.year),
                ),
              ),
              if (_eventKind == DoseEventKind.stopped) ...[
                Text(
                  'A stop needs no dose — the day is the fact.',
                  style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.4),
                ),
              ] else ...[
                const SizedBox(height: 4),
                _Field(
                  controller: _eventDose,
                  label: 'Dose',
                  hint: 'e.g. 500 µg',
                  enabled: log.canWrite,
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: log.canWrite ? _addEvent : null,
                  child: const Text('Add entry'),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'Removing something takes it off the daily list and keeps every take '
              'and skip you recorded for it: that history is part of your record and '
              'is what the doctor report prints. Renaming keeps it too — the name '
              'changes, the days do not move. Changing the dose above records '
              'today\'s change in this history too, so the list and its line can '
              'never disagree. To move an entry to another day, remove it and add '
              'it again on that day.',
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedListRow extends StatelessWidget {
  const _MedListRow({
    required this.medication,
    required this.editing,
    required this.onEdit,
    required this.onArchive,
  });

  final Medication medication;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            medication.kind == MedKind.medication
                ? Icons.medication_outlined
                : Icons.spa_outlined,
            size: 18,
            color: editing ? t.accent : t.accentSoft,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medication.displayName,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  medication.kind.title,
                  style: TextStyle(color: t.textFaint, fontSize: 11.5),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Edit')),
          TextButton(
            onPressed: onArchive,
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _KindChoice extends StatelessWidget {
  const _KindChoice({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final MedKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: selected ? t.accent : t.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: selected ? t.accent : t.border, width: 1.3),
          ),
          child: Text(
            kind.title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? t.onAccent : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the three entry words, in the shape the medication kinds use above:
/// a choice, not a menu — three words read faster than three taps.
class _EventChoice extends StatelessWidget {
  const _EventChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: selected ? t.accent : t.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: selected ? t.accent : t.border, width: 1.3),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? t.onAccent : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextField(
      controller: controller,
      enabled: enabled,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(color: t.textPrimary, fontSize: 14.5),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: t.textFaint, fontSize: 13),
        hintStyle: TextStyle(color: t.textFaint, fontSize: 13.5),
        filled: true,
        fillColor: t.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: t.border),
        ),
      ),
    );
  }
}
