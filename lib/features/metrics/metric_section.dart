import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/app_text.dart';
import '../../core/log/log_controller.dart';
import '../../core/metrics/metric_models.dart';
import '../../core/theme/app_theme.dart';
import '../log/log_widgets.dart';
import '../log/undo_toast.dart';

/// The numbers a person records about a day, and the switch that decides which
/// numbers the app is allowed to ask for.
///
/// The card is empty until something is switched on, and that is the design: a
/// period tracker that asks for your weight the first time it opens is a period
/// tracker making a claim about what matters. So the default screen has no number
/// rows at all, and this section says how to add one.
class MetricSection extends StatelessWidget {
  const MetricSection({super.key, required this.log});

  final LogController log;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = log.enabledMetrics;

    if (enabled.isEmpty) {
      return LogCard(
        title: 'Your numbers',
        blurb: 'Optional. Nothing here is asked for until you switch it on.',
        icon: Icons.straighten_outlined,
        children: [
          Text(
            'Weight, sleep, activity, water, temperature, cervical mucus, waist and '
            'blood pressure can be recorded here if you want them. They are '
            'measurements, not symptoms, so they are kept apart from how you feel — '
            'and nothing is compared until there is enough of it to compare.',
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: log.canWrite ? () => showMetricPicker(context, log) : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Choose what to track'),
          ),
        ],
      );
    }

    return LogCard(
      title: 'Your numbers',
      blurb: 'Measurements, kept apart from how you feel. Tap one to record it.',
      icon: Icons.straighten_outlined,
      children: [
        for (final kind in enabled)
          _MetricRow(
            kind: kind,
            metric: log.metricFor(kind),
            enabled: log.canWrite,
            onTap: () => showMetricEditor(context, log, kind),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: log.canWrite ? () => showMetricPicker(context, log) : null,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('What I track'),
            ),
          ],
        ),
        if (enabled.any((kind) => kind.isFertilityAdjacent))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Temperature and mucus are recorded as observations only. Cystera does not '
              'estimate ovulation from either, and will not read them as a fertile window.',
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
            ),
          ),
      ],
    );
  }
}

/// One metric, as a row: its name, what was recorded, and a tap to change it.
class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.kind,
    required this.metric,
    required this.enabled,
    required this.onTap,
  });

  final MetricKind kind;
  final DayMetric? metric;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: t.background,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.title,
                      style: TextStyle(
                        color: enabled ? t.textPrimary : t.textFaint,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metric?.display ?? 'not recorded',
                      style: TextStyle(
                        color: metric == null ? t.textFaint : t.accentSoft,
                        fontSize: 13,
                        fontWeight: metric == null ? FontWeight.w500 : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                metric == null ? Icons.add_circle_outline : Icons.edit_outlined,
                size: 18,
                color: t.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet that appears when the user asks to choose what they track.
Future<void> showMetricPicker(BuildContext context, LogController log) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radius)),
      ),
      builder: (_) => _MetricPickerSheet(log: log),
    );

class _MetricPickerSheet extends StatefulWidget {
  const _MetricPickerSheet({required this.log});

  final LogController log;

  @override
  State<_MetricPickerSheet> createState() => _MetricPickerSheetState();
}

class _MetricPickerSheetState extends State<_MetricPickerSheet> {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What would you like to track?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Switching one off hides the row. It does not delete anything already '
              'recorded — that stays in the record and comes back with the row.',
              style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final kind in MetricKind.values)
                      SwitchListTile(
                        value: widget.log.metricPrefs.isEnabled(kind),
                        onChanged: (on) async {
                          await widget.log.setMetricEnabled(kind, on);
                          if (mounted) setState(() {});
                        },
                        title: Text(kind.title, style: Theme.of(context).textTheme.titleMedium),
                        subtitle: Text(
                          kind.blurb,
                          style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.4),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sheet that records one metric on the shown day.
Future<void> showMetricEditor(
  BuildContext context,
  LogController log,
  MetricKind kind,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radius)),
      ),
      builder: (_) => _MetricEditorSheet(log: log, kind: kind),
    );

class _MetricEditorSheet extends StatefulWidget {
  const _MetricEditorSheet({required this.log, required this.kind});

  final LogController log;
  final MetricKind kind;

  @override
  State<_MetricEditorSheet> createState() => _MetricEditorSheetState();
}

class _MetricEditorSheetState extends State<_MetricEditorSheet> {
  late final TextEditingController _value = TextEditingController(
    text: _initialValue(),
  );
  late final TextEditingController _detail = TextEditingController(
    text: widget.log.metricFor(widget.kind)?.detail ?? '',
  );
  String? _problem;

  String _initialValue() {
    final metric = widget.log.metricFor(widget.kind);
    if (metric == null) return '';
    if (widget.kind == MetricKind.mucus) return metric.value.round().toString();
    return widget.kind.decimals == 0
        ? metric.value.round().toString()
        : metric.value.toStringAsFixed(widget.kind.decimals);
  }

  @override
  void dispose() {
    _value.dispose();
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final kind = widget.kind;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kind.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(kind.blurb, style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45)),
            const SizedBox(height: 16),
            if (kind == MetricKind.mucus)
              _MucusChoices(
                selected: widget.log.metricFor(kind)?.value.round(),
                onSelected: (level) => _saveRaw(level.toDouble()),
              )
            else
              TextField(
                controller: _value,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: kind.decimals > 0,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  suffixText: kind.unit.isEmpty ? null : kind.unit,
                  hintText: kind == MetricKind.exercise ? 'minutes' : 'value',
                  hintStyle: TextStyle(color: t.textFaint, fontSize: 15),
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
            if (kind == MetricKind.exercise) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _detail,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: t.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'What did you do? e.g. walk, yoga, rest day',
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
            ],
            if (_problem case final problem?) ...[
              const SizedBox(height: 10),
              Text(
                problem,
                style: TextStyle(color: t.accent, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: kind == MetricKind.mucus ? null : _save,
                    child: Text(text.save),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.log.metricFor(kind) != null)
                  TextButton(
                    onPressed: _clear,
                    child: const Text('Clear'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(text.cancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final parsed = parseMetric(widget.kind, _value.text);
    switch (parsed) {
      case MetricCleared():
        _clear();
      case MetricRejected(:final reason):
        setState(() => _problem = reason);
      case MetricAccepted(:final value):
        _saveRaw(value);
    }
  }

  void _saveRaw(double value) {
    final detail = widget.kind == MetricKind.exercise ? _detail.text : null;
    Navigator.of(context).pop();
    writeAndOfferUndo(
      context,
      widget.log,
      () => widget.log.setMetricValue(widget.kind, value, detail: detail),
    );
  }

  void _clear() {
    Navigator.of(context).pop();
    writeAndOfferUndo(
      context,
      widget.log,
      () => widget.log.setMetricValue(widget.kind, null),
    );
  }
}

/// The three mucus words as taps, because a phrase is easier to answer than a
/// number nobody knows the scale for.
class _MucusChoices extends StatelessWidget {
  const _MucusChoices({required this.selected, required this.onSelected});

  final int? selected;
  final void Function(int level) onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        for (var level = 1; level <= 3; level++) ...[
          if (level > 1) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: selected == level ? t.accent : t.background,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              child: InkWell(
                onTap: () => onSelected(level),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    border: Border.all(
                      color: selected == level ? t.accent : t.border,
                      width: 1.3,
                    ),
                  ),
                  child: Text(
                    MetricKind.mucusWords(level.toDouble()),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected == level ? t.onAccent : t.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
