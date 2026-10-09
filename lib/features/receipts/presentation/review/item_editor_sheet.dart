import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/domain/money.dart';
import '../../../../core/utils/format.dart';
import '../../domain/entities/receipt.dart';

/// Bottom sheet to add or edit a line item and its warranty.
Future<LineItem?> showItemEditor(BuildContext context, LineItem item) => showModalBottomSheet<LineItem>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ItemEditor(item: item),
);

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({required this.item});
  final LineItem item;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _price = TextEditingController(text: moneyInputText(widget.item.unitPrice.minor));
  late final _serial = TextEditingController(text: widget.item.serialNumber ?? '');
  late final _provider = TextEditingController(text: widget.item.warranty?.provider ?? '');
  late final _customMonths = TextEditingController();
  late int _quantity = widget.item.quantity;
  late int _months = widget.item.warranty?.months ?? 0;
  late bool _extended = widget.item.warranty?.isExtended ?? false;
  String? _nameError;
  String? _monthsError;

  static const _presets = [0, 6, 12, 24, 36];

  @override
  void initState() {
    super.initState();
    if (!_presets.contains(_months)) _customMonths.text = '$_months';
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _serial, _provider, _customMonths]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final custom = int.tryParse(_customMonths.text);
    final months = custom ?? _months;
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Enter the item name' : null;
      _monthsError = months < 0 || months > 120 ? 'Use 0–120 months' : null;
    });
    if (_nameError != null || _monthsError != null) return;
    Navigator.pop(
      context,
      widget.item.copyWith(
        name: _name.text.trim(),
        quantity: _quantity,
        unitPrice: Money(parseMoneyInput(_price.text) ?? 0, widget.item.unitPrice.currency),
        serialNumber: _serial.text.trim().isEmpty ? null : _serial.text.trim(),
        warranty: months == 0
            ? null
            : Warranty(
                months: months,
                provider: _provider.text.trim().isEmpty ? null : _provider.text.trim(),
                isExtended: _extended,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final custom = _customMonths.text.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item.name.isEmpty ? 'Add item' : 'Edit item', style: text.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: widget.item.name.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Item name', errorText: _nameError),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: InputDecoration(
                      labelText: 'Unit price',
                      prefixText: '${currencySymbol(widget.item.unitPrice.currency)} ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _Stepper(value: _quantity, onChanged: (v) => setState(() => _quantity = v)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serial,
              decoration: const InputDecoration(
                labelText: 'Serial / IMEI (optional)',
                prefixIcon: Icon(Icons.qr_code_rounded),
              ),
            ),
            const SizedBox(height: 20),
            Text('Warranty', style: text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _presets)
                  ChoiceChip(
                    label: Text(
                      m == 0
                          ? 'None'
                          : m % 12 == 0
                          ? '${m ~/ 12} yr'
                          : '$m mo',
                    ),
                    selected: !custom && _months == m,
                    onSelected: (_) => setState(() {
                      _months = m;
                      _customMonths.clear();
                    }),
                  ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _customMonths,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(isDense: true, hintText: 'Months', errorText: _monthsError),
                  ),
                ),
              ],
            ),
            if (_months > 0 || custom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _provider,
                decoration: const InputDecoration(labelText: 'Warranty provider (optional)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Extended warranty'),
                value: _extended,
                onChanged: (v) => setState(() => _extended = v),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Fewer',
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        IconButton(tooltip: 'More', onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_rounded)),
      ],
    ),
  );
}
