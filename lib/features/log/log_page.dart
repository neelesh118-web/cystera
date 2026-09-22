import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_text.dart';
import '../../core/log/day_key.dart';
import '../../core/log/log_controller.dart';
import '../../core/log/log_models.dart';
import '../../core/log/severity.dart';
import '../../core/log/symptom_catalogue.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_hero.dart';
import '../../core/widgets/page_scaffold.dart';
import '../meds/med_section.dart';
import '../metrics/metric_section.dart';
import 'backfill_sheet.dart';
import 'custom_symptom_sheet.dart';
import 'day_strip.dart';
import 'log_widgets.dart';
import 'severity_ramp.dart';
import 'undo_toast.dart';

/// Where a day gets recorded.
///
/// The structure is the 2023 International Evidence-based PCOS Guideline's three
/// domains rather than one long list, because a person looking for "hair" and a
/// person looking for "mood" are having different days.
///
/// The screen is built around one constraint: it gets used on bad days. So every
/// row is a single tap at a coarse intensity, the day strip makes logging
/// yesterday a tap instead of a date picker, and nothing anywhere asks a second
/// question before it accepts an answer.
class LogPage extends StatelessWidget {
  const LogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final log = context.watch<LogController>();

    return PageScaffold(
      // The day is the title, because the day is the one thing this screen can get
      // wrong: everything below it is recorded *against* whichever day is named
      // here, and a user who scrolls a past day's screen without noticing is the
      // failure this header exists to prevent. The tab's name is the small line
      // above it, and "Back to today" sits on the same row — visible only when it
      // would do something.
      header: PageHero(
        overline: AppTextScope.of(context).navLog,
        title: HeroTitle(_subtitle(log)),
        trailing: log.isToday
            ? null
            : TextButton(
                onPressed: () => log.showDay(log.today),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                child: const Text('Back to today'),
              ),
      ),
      children: [
        DayStrip(
          days: DayKey.recentDays(log.today, 14),
          selected: log.day,
          logs: log.recent,
          onSelected: log.showDay,
        ),
        if (log.loading && log.recent.isEmpty)
          const SizedBox(
            height: 2,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (log.writeBlockedReason case final reason?)
          _Banner(icon: Icons.lock_outline, text: reason),
        if (!log.isToday && log.writeBlockedReason == null)
          const _Banner(
            icon: Icons.history_rounded,
            text: 'You are logging a day that has passed. It will be kept as '
                'entered later, which is honest about how it was recorded.',
          ),
        if (log.error case final error?) _Banner(icon: Icons.error_outline, text: error, warning: true),
        _CycleSection(log: log),
        // After the cycle and before the symptom domains: what a person *did* today
        // — took a tablet, skipped one — is closer to a period mark than to how they
        // feel, and it is a tap either way.
        MedSection(log: log),
        // After the medications: a measurement is something the user decided to
        // keep, like a tablet, and it sits with the things they chose to track
        // rather than with the symptoms the guideline asks about.
        MetricSection(log: log),
        _DomainSection(log: log, domain: LogDomain.body),
        _DomainSection(log: log, domain: LogDomain.mind),
        _NoteCard(log: log),
        _NothingCard(log: log),
        const _Footer(),
      ],
    );
  }

  static String _subtitle(LogController log) {
    final day = log.isToday ? 'Today' : _weekday(log.day);
    return '$day, ${log.day.day} ${_month(log.day.month)}';
  }

  static String _weekday(DateTime day) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][day.weekday - 1];

  static String _month(int month) => const [
        '',
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ][month];
}

/// Period and flow: day-level facts rather than severities, so they are asked
/// about separately from the symptom rows.
class _CycleSection extends StatelessWidget {
  const _CycleSection({required this.log});

  final LogController log;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mark = log.shownLog.cycleMark;
    final isPeriod = mark?.kind == CycleMarkKind.period;
    final isSpotting = mark?.kind == CycleMarkKind.spotting;

    return LogCard(
      title: AppTextScope.of(context)
          .domainTitle(LogDomain.cycle.name, LogDomain.cycle.title),
      blurb: 'A period day is what the cycle view counts. FlowLevel is optional.',
      icon: Icons.water_drop_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: _Toggle(
                label: 'Period day',
                selected: isPeriod,
                onTap: log.canWrite
                    ? () => writeAndOfferUndo(
                          context,
                          log,
                          () => log.togglePeriod(flow: mark?.flow),
                        )
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Toggle(
                label: 'Spotting',
                selected: isSpotting,
                onTap: log.canWrite
                    ? () => writeAndOfferUndo(context, log, log.toggleSpotting)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Flow',
          style: TextStyle(color: t.textFaint, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SeverityRamp(
          value: isPeriod ? mark?.flow : null,
          semanticLabel: 'Flow',
          levels: FlowLevel.values,
          enabled: log.canWrite,
          onChanged: (level) => writeAndOfferUndo(
            context,
            log,
            () => log.setFlow(level as FlowLevel?),
          ),
        ),
        if (isPeriod && mark?.backfilled == true)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'This day was entered after the fact, so it stays marked that way.',
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.4),
            ),
          ),
      ],
    );
  }
}

class _DomainSection extends StatelessWidget {
  const _DomainSection({required this.log, required this.domain});

  final LogController log;
  final LogDomain domain;

  @override
  Widget build(BuildContext context) {
    return LogCard(
      // The title is translated; the blurb below it is not yet, which is the
      // most visible remaining gap on this screen and is listed in
      // `docs/languages.md` rather than left to be discovered.
      title: AppTextScope.of(context).domainTitle(domain.name, domain.title),
      blurb: domain.blurb,
      icon: switch (domain) {
        LogDomain.cycle => Icons.water_drop_outlined,
        LogDomain.body => Icons.monitor_heart_outlined,
        LogDomain.mind => Icons.psychology_outlined,
      },
      children: [
        // The guideline's entries for this domain plus any custom symptom filed
        // under it, drawn and scored identically: a symptom the user named is not a
        // second-class one.
        for (final symptom in SymptomCatalogue.drawnFor(domain))
          _SymptomRow(
            symptom: symptom,
            severity: log.shownLog.entries[symptom.id],
            enabled: log.canWrite,
            onEdit: symptom.custom
                ? () => showCustomSymptomSheet(context, log, existing: symptom)
                : null,
            onChanged: (level) {
              if (level is! Severity) return;
              // The controller turns a tap on the level already set into a clear,
              // so this is the whole behaviour of the row: one tap, either way.
              writeAndOfferUndo(
                context,
                log,
                () => log.tapSeverity(symptom.id, level),
              );
            },
          ),
        // The body domain carries the add button, because it is where a custom
        // symptom lands by default and where most of them belong. The sheet lets
        // the user file one under Mind, so nothing is forced into a domain.
        if (domain == LogDomain.body)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: log.canWrite
                    ? () => showCustomSymptomSheet(context, log)
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Track something of my own'),
              ),
            ),
          ),
      ],
    );
  }
}

class _SymptomRow extends StatelessWidget {
  const _SymptomRow({
    required this.symptom,
    required this.severity,
    required this.enabled,
    required this.onChanged,
    this.onEdit,
  });

  final Symptom symptom;
  final Severity? severity;
  final bool enabled;
  final void Function(Enum level) onChanged;

  /// Present only for a symptom the user added: it opens the rename/archive sheet.
  /// A guideline row has nothing to edit, so it has no pencil.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // The name a person taps, in their language. The id stays the record's key and
    // the English label stays what the doctor report prints.
    final label = AppTextScope.of(context).symptomLabel(symptom.id, symptom.label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: enabled ? t.textPrimary : t.textFaint,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_outlined, size: 16, color: t.textFaint),
                  tooltip: 'Rename or remove $label',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          if (symptom.hint case final hint?) ...[
            const SizedBox(height: 2),
            Text(hint, style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.35)),
          ],
          const SizedBox(height: 8),
          SeverityRamp(
            value: severity,
            // The screen reader is told the same name the screen shows, so a
            // translated app does not speak English into someone's ear.
            semanticLabel: label,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// The note, for the things the catalogue does not have a word for.
class _NoteCard extends StatefulWidget {
  const _NoteCard({required this.log});

  final LogController log;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  late final TextEditingController _text = TextEditingController(text: widget.log.shownLog.note ?? '');
  late String _dayKey = DayKey.of(widget.log.day);

  @override
  void didUpdateWidget(covariant _NoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = DayKey.of(widget.log.day);
    // The field follows the day and follows an undo, but never fights the
    // keyboard while the user is typing into it.
    final stored = widget.log.shownLog.note ?? '';
    if (key != _dayKey) {
      _dayKey = key;
      _text.text = stored;
    } else if (stored != _text.text.trim() && !_isDirty) {
      _text.text = stored;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _isDirty => _text.text.trim() != (widget.log.shownLog.note ?? '').trim();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LogCard(
      title: 'Anything else',
      blurb: 'Optional. A sentence you would want the doctor to read.',
      icon: Icons.edit_note_outlined,
      children: [
        TextField(
          controller: _text,
          enabled: widget.log.canWrite,
          maxLines: 3,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          onTapOutside: (_) {
            if (_isDirty) {
              writeAndOfferUndo(context, widget.log, () => widget.log.setNote(_text.text));
            }
          },
          style: TextStyle(color: t.textPrimary, fontSize: 14.5, height: 1.4),
          decoration: InputDecoration(
            hintText: 'e.g. started a new supplement this week',
            hintStyle: TextStyle(color: t.textFaint, fontSize: 14),
            filled: true,
            fillColor: t.background,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: BorderSide(color: t.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: BorderSide(color: t.border),
            ),
          ),
        ),
        if (_isDirty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => writeAndOfferUndo(
                      context,
                      widget.log,
                      () => widget.log.setNote(_text.text),
                    ),
                    child: const Text('Save note'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    _text.text = widget.log.shownLog.note ?? '';
                    setState(() {});
                  },
                  child: const Text('Discard'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Nothing today", which is the most commonly lost data point in a tracker.
class _NothingCard extends StatelessWidget {
  const _NothingCard({required this.log});

  final LogController log;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final nothing = log.shownLog.nothing;
    final hasSymptoms = log.shownLog.entries.isNotEmpty;
    if (hasSymptoms && !nothing) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: t.accentSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nothing ? 'Nothing today — recorded' : 'A day with no symptoms',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            nothing
                ? 'A day with nothing to report is a data point, and it is now part of the '
                    'record. It is not the same as a day the app was never opened.'
                : 'If nothing was wrong, say so. It takes one tap and it is the only way the '
                    'record can tell "fine" apart from "not logged".',
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 14),
          if (nothing)
            OutlinedButton(
              onPressed: log.canWrite
                  ? () => writeAndOfferUndo(context, log, () => log.setNothing(false))
                  : null,
              child: const Text('Withdraw that'),
            )
          else
            OutlinedButton(
              onPressed: log.canWrite
                  ? () => writeAndOfferUndo(context, log, () => log.setNothing(true))
                  : null,
              child: const Text('Nothing to record'),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // What the three words mean, said once instead of next to every row:
          // fourteen repetitions of the same sentence is a page nobody scrolls.
          for (final severity in Severity.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${severity.word} — ${severity.effect}.',
                style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.4),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'A tap at a level you already chose clears it. Nothing here is ordered by severity: '
            'you are writing down what happened, not being scored.',
            style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => showBackfillSheet(context),
            icon: const Icon(Icons.event_repeat_outlined, size: 18),
            label: const Text('Record a period I did not log'),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

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
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: selected ? t.accent : t.border, width: 1.3),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: onTap == null
                  ? t.textFaint
                  : selected
                      ? t.onAccent
                      : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.warning = false});

  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: warning ? t.accent : t.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: warning ? t.accent : t.accentSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: warning ? t.accent : t.textSecondary,
                fontSize: 13,
                height: 1.4,
                fontWeight: warning ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
