import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme.dart';
import '../../../../core/domain/money.dart';
import '../../../../core/failures.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/common.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/services/protection_rules.dart';
import '../widgets/receipt_visuals.dart';
import 'item_editor_sheet.dart';
import 'review_presenter.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key, required this.args});
  final ReviewArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = reviewPresenterProvider(args);
    final async = ref.watch(provider);

    ref.listen(provider, (prev, next) {
      final form = next.value;
      if (form == null) return;
      if (form.savedId != null && prev?.value?.savedId == null) {
        showMessage(
          context,
          form.receipt.status == ReceiptStatus.queuedOffline
              ? 'Saved. Keepr will read it when you are back online.'
              : 'Receipt saved',
        );
        if (args.draft != null) {
          context.pushReplacement('/receipt/${form.savedId}');
        } else {
          context.pop();
        }
      } else if (form.error != null) {
        showMessage(context, form.error!, error: true);
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(args.draft != null ? 'Review receipt' : 'Edit receipt')),
      body: switch (async) {
        AsyncData(:final value) => _Form(args: args, form: value),
        AsyncError(:final error) => ErrorState(
          message: error is AppFailure ? error.message : 'Could not open this receipt.',
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: async.value == null ? null : _SaveBar(args: args, form: async.value!),
    );
  }
}

class _SaveBar extends ConsumerWidget {
  const _SaveBar({required this.args, required this.form});
  final ReviewArgs args;
  final ReviewForm form;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presenter = ref.read(reviewPresenterProvider(args).notifier);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        ),
        child: ContentWidth(
          shrinkHeight: true,
          child: Row(
            children: [
              if (form.canSaveForLater) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: form.saving ? null : presenter.saveForLater,
                    child: const Text('Read later'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 2,
                child: LoadingButton(
                  label: form.canEdit ? 'Save receipt' : 'View only',
                  icon: Icons.check_rounded,
                  loading: form.saving,
                  onPressed: form.canEdit ? presenter.save : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.args, required this.form});
  final ReviewArgs args;
  final ReviewForm form;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presenter = ref.read(reviewPresenterProvider(args).notifier);
    final r = form.receipt;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final deadline = r.returnDeadline;

    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (form.banner != null) _Banner(kind: form.bannerKind, message: form.banner!),
          if (form.duplicates.isNotEmpty)
            _DuplicateWarning(duplicate: form.duplicates.first, onSaveAnyway: presenter.acknowledgeDuplicates),
          _Attachments(args: args, form: form),
          const SectionHeader('Purchase'),
          _CheckedField(
            label: 'Store or seller',
            icon: Icons.storefront_rounded,
            initialValue: r.merchant,
            error: form.errors['merchant'],
            needsCheck: form.unconfirmed.contains('merchant'),
            onConfirm: () => presenter.confirmField('merchant'),
            onChanged: presenter.setMerchant,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          _DateField(
            date: r.purchaseDate,
            error: form.errors['purchaseDate'],
            needsCheck: form.unconfirmed.contains('purchaseDate'),
            onConfirm: () => presenter.confirmField('purchaseDate'),
            onChanged: presenter.setPurchaseDate,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _CheckedField(
                  label: 'Total paid',
                  icon: Icons.payments_rounded,
                  initialValue: moneyInputText(r.total.minor),
                  error: form.errors['total'],
                  needsCheck: form.unconfirmed.contains('total'),
                  onConfirm: () => presenter.confirmField('total'),
                  onChanged: (v) => presenter.setTotal(parseMoneyInput(v)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: kSupportedCurrencies.contains(r.total.currency) ? r.total.currency : null,
                  decoration: InputDecoration(labelText: 'Currency', errorText: form.errors['currency']),
                  items: [for (final c in kSupportedCurrencies) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (c) => c == null ? null : presenter.setCurrency(c),
                ),
              ),
            ],
          ),
          if (r.items.isNotEmpty && form.itemsTotal.minor > 0 && (r.total.minor == 0 || form.itemsTotal.minor > r.total.minor))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: presenter.useItemsTotal,
                icon: const Icon(Icons.calculate_rounded, size: 18),
                label: Text('Use items total (${formatMoney(form.itemsTotal)})'),
              ),
            ),
          const SizedBox(height: 16),
          Text('Category', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in Category.values)
                ChoiceChip(
                  avatar: Icon(CategoryStyle.of(c).icon, size: 18, color: CategoryStyle.of(c).color),
                  label: Text(c.label),
                  selected: r.category == c,
                  onSelected: (_) => presenter.setCategory(c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: r.paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Payment method (optional)',
              prefixIcon: Icon(Icons.credit_card_rounded),
            ),
            onChanged: presenter.setPaymentMethod,
          ),
          SectionHeader(
            'Items',
            trailing: TextButton.icon(
              onPressed: () async {
                final item = await showItemEditor(context, presenter.newItem());
                if (item != null) presenter.upsertItem(item);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add item'),
            ),
          ),
          if (r.items.isEmpty)
            SurfaceCard(
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add the products you bought to track their warranties and serial numbers.',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final item in r.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ItemTile(
                  item: item,
                  warrantyEnd: r.warrantyEndFor(item),
                  error: form.errors.entries
                      .where((e) => e.key.startsWith('items.${r.items.indexOf(item)}.'))
                      .map((e) => e.value)
                      .firstOrNull,
                  onEdit: () async {
                    final updated = await showItemEditor(context, item);
                    if (updated != null) presenter.upsertItem(updated);
                  },
                  onDelete: () => presenter.removeItem(item.id),
                ),
              ),
          const SectionHeader('Return window'),
          Wrap(
            spacing: 8,
            children: [
              for (final (days, label) in [
                (null, 'None'),
                (7, '7 days'),
                (14, '14 days'),
                (30, '30 days'),
                if (r.returnDays != null && !const [7, 14, 30].contains(r.returnDays))
                  (r.returnDays, '${r.returnDays} days'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: r.returnDays == days,
                  onSelected: (_) => presenter.setReturnDays(days),
                ),
            ],
          ),
          if (deadline != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Returnable until ${formatDate(deadline)}. We’ll remind you 3 days before.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (form.errors['returnDays'] != null)
            Text(form.errors['returnDays']!, style: text.bodySmall?.copyWith(color: scheme.error)),
          const SectionHeader('Notes'),
          TextFormField(
            initialValue: r.notes,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(hintText: 'Gift for Ali, kept box in storage room…'),
            onChanged: presenter.setNotes,
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.kind, required this.message});
  final BannerKind? kind;
  final String message;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (kind) {
      BannerKind.aiFilled => (KeeprColors.brand, Icons.auto_awesome_rounded),
      BannerKind.offline => (KeeprColors.sky, Icons.cloud_off_rounded),
      BannerKind.failed => (KeeprColors.amber, Icons.info_rounded),
      _ => (KeeprColors.brand, Icons.edit_note_rounded),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _DuplicateWarning extends StatelessWidget {
  const _DuplicateWarning({required this.duplicate, required this.onSaveAnyway});
  final Receipt duplicate;
  final VoidCallback onSaveAnyway;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: KeeprColors.amber.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.content_copy_rounded, color: KeeprColors.amber),
            const SizedBox(width: 10),
            Expanded(child: Text('This looks like a duplicate', style: Theme.of(context).textTheme.titleSmall)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'You already saved ${duplicate.merchant} for ${formatMoney(duplicate.total)} on ${formatDate(duplicate.purchaseDate)}.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(onPressed: () => context.push('/receipt/${duplicate.id}'), child: const Text('View existing')),
            const Spacer(),
            FilledButton.tonal(onPressed: onSaveAnyway, child: const Text('Save anyway')),
          ],
        ),
      ],
    ),
  );
}

class _Attachments extends ConsumerWidget {
  const _Attachments({required this.args, required this.form});
  final ReviewArgs args;
  final ReviewForm form;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presenter = ref.read(reviewPresenterProvider(args).notifier);
    final attachments = form.receipt.attachments;
    return SizedBox(
      height: 112,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final a in attachments)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _AttachmentImage(attachment: a, localBytes: form.newImages[a.id]),
                  ),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Pill(label: a.kind.name, color: Colors.black87, dense: true),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove photo',
                      iconSize: 16,
                      onPressed: () => presenter.removeAttachment(a.id),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
            ),
          PopupMenuButton<(AttachmentKind, bool)>(
            tooltip: 'Add photo',
            onSelected: (v) => presenter.addPhoto(v.$1, fromCamera: v.$2),
            itemBuilder: (_) => const [
              PopupMenuItem(value: (AttachmentKind.receipt, true), child: Text('Receipt · camera')),
              PopupMenuItem(value: (AttachmentKind.receipt, false), child: Text('Receipt · gallery')),
              PopupMenuItem(value: (AttachmentKind.product, true), child: Text('Product photo')),
              PopupMenuItem(value: (AttachmentKind.serial, true), child: Text('Serial number label')),
            ],
            child: Container(
              width: 96,
              height: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 6),
                  Text('Add photo', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentImage extends ConsumerWidget {
  const _AttachmentImage({required this.attachment, this.localBytes});
  final Attachment attachment;
  final Uint8List? localBytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = localBytes ?? ref.watch(attachmentBytesProvider(attachment)).value;
    return Container(
      width: 96,
      height: 112,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: bytes == null
          ? const Icon(Icons.image_rounded)
          : Image.memory(bytes, fit: BoxFit.cover, width: 96, height: 112),
    );
  }
}

/// Text field that highlights low-confidence AI values (BR-11).
class _CheckedField extends StatelessWidget {
  const _CheckedField({
    required this.label,
    required this.icon,
    required this.initialValue,
    required this.onChanged,
    required this.needsCheck,
    required this.onConfirm,
    this.error,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final IconData icon;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool needsCheck;
  final VoidCallback onConfirm;
  final String? error;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initialValue,
    onChanged: onChanged,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    textCapitalization: textCapitalization,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      errorText: error,
      fillColor: needsCheck ? KeeprColors.amber.withValues(alpha: 0.12) : null,
      helperText: needsCheck ? 'AI wasn’t sure. Please check this value.' : null,
      helperStyle: const TextStyle(color: KeeprColors.amber),
      suffixIcon: needsCheck
          ? IconButton(
              tooltip: 'Looks right',
              icon: const Icon(Icons.check_circle_outline_rounded, color: KeeprColors.amber),
              onPressed: onConfirm,
            )
          : null,
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.onChanged,
    required this.needsCheck,
    required this.onConfirm,
    this.error,
  });
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final bool needsCheck;
  final VoidCallback onConfirm;
  final String? error;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
      );
      if (picked != null) onChanged(picked);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: 'Purchase date',
        prefixIcon: const Icon(Icons.event_rounded),
        errorText: error,
        fillColor: needsCheck ? KeeprColors.amber.withValues(alpha: 0.12) : null,
        helperText: needsCheck ? 'AI wasn’t sure. Please check the date.' : null,
        helperStyle: const TextStyle(color: KeeprColors.amber),
        suffixIcon: needsCheck
            ? IconButton(
                tooltip: 'Looks right',
                icon: const Icon(Icons.check_circle_outline_rounded, color: KeeprColors.amber),
                onPressed: onConfirm,
              )
            : const Icon(Icons.expand_more_rounded),
      ),
      child: Text(formatDate(date)),
    ),
  );
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.warrantyEnd,
    required this.onEdit,
    required this.onDelete,
    this.error,
  });
  final LineItem item;
  final DateTime? warrantyEnd;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      onTap: onEdit,
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name.isEmpty ? 'Unnamed item' : item.name, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${item.quantity} × ${formatMoney(item.unitPrice)}'
                  '${item.serialNumber == null ? '' : '  ·  S/N ${item.serialNumber}'}',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                if (warrantyEnd != null)
                  Pill(
                    label: '${item.warranty!.months} mo warranty · until ${formatDate(warrantyEnd!)}',
                    color: KeeprColors.success,
                    icon: Icons.verified_user_rounded,
                    dense: true,
                  )
                else
                  Text('No warranty', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                if (error != null) Text(error!, style: text.bodySmall?.copyWith(color: scheme.error)),
              ],
            ),
          ),
          IconButton(tooltip: 'Remove item', onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
    );
  }
}
