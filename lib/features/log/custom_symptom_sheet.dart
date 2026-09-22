import 'package:flutter/material.dart';

import '../../core/i18n/app_text.dart';
import '../../core/log/log_controller.dart';
import '../../core/log/symptom_catalogue.dart';
import '../../core/theme/app_theme.dart';

/// Adding or renaming a symptom the guideline does not name.
///
/// The field is free text and is never matched against a catalogue, for the same
/// reason the medication list is: a shipped list of symptoms is a medical claim,
/// and it is wrong for most of the world the moment it ships. The app asks what to
/// call it and how bad it was, and nothing else.
Future<void> showCustomSymptomSheet(
  BuildContext context,
  LogController log, {
  Symptom? existing,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radius)),
      ),
      builder: (_) => _CustomSymptomSheet(log: log, existing: existing),
    );

class _CustomSymptomSheet extends StatefulWidget {
  const _CustomSymptomSheet({required this.log, this.existing});

  final LogController log;
  final Symptom? existing;

  @override
  State<_CustomSymptomSheet> createState() => _CustomSymptomSheetState();
}

class _CustomSymptomSheetState extends State<_CustomSymptomSheet> {
  late final TextEditingController _label =
      TextEditingController(text: widget.existing?.label ?? '');
  late LogDomain _domain = widget.existing?.domain ?? LogDomain.body;
  String? _problem;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final editing = widget.existing != null;
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
            Text(
              editing ? 'Rename this symptom' : 'Add your own symptom',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              editing
                  ? 'Renaming keeps every day already recorded against it. Days are kept '
                      'by id, not by name.'
                  : 'Your own words. It appears beside the others, at the same three levels, '
                      'and is compared by the same rules — a symptom you name is not a '
                      'second-class one.',
              style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _label,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: t.textPrimary, fontSize: 15.5),
              decoration: InputDecoration(
                hintText: 'e.g. Pelvic pain, Cold hands, Post-meal drowsiness',
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
            const SizedBox(height: 14),
            Text('Where it sits', style: TextStyle(color: t.textFaint, fontSize: 12.5)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final domain in const [LogDomain.body, LogDomain.mind])
                  ChoiceChip(
                    label: Text(
                      AppTextScope.of(context)
                          .domainTitle(domain.name, domain.title),
                    ),
                    selected: _domain == domain,
                    onSelected: (_) => setState(() => _domain = domain),
                  ),
              ],
            ),
            if (_problem case final problem?) ...[
              const SizedBox(height: 10),
              Text(
                problem,
                style: TextStyle(color: t.accent, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(editing ? 'Save changes' : 'Add to the log'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            if (editing) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: _remove,
                style: TextButton.styleFrom(foregroundColor: t.accent),
                child: const Text('Remove from the log'),
              ),
              Text(
                'Removing keeps every day already recorded against it. It is taken off '
                'the list, not deleted from your history.',
                style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _remove() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final navigator = Navigator.of(context);
    await widget.log.archiveCustomSymptom(id, true);
    if (!mounted) return;
    navigator.pop();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _problem = 'A name is needed — even one word.');
      return;
    }
    final navigator = Navigator.of(context);
    await widget.log.saveCustomSymptom(id: widget.existing?.id, label: label);
    if (!mounted) return;
    if (widget.log.error case final error?) {
      setState(() => _problem = error);
      return;
    }
    navigator.pop();
  }
}
