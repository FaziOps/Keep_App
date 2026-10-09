import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/domain/money.dart';
import '../../../core/utils/format.dart' show shortReference;
import '../../receipts/domain/entities/receipt.dart';
import '../../receipts/domain/services/protection_rules.dart';
import '../domain/claim_pack.dart';

/// Renders the claim pack as an A4 PDF on device (FR-CLM-01).
class PdfClaimPackRenderer implements ClaimPackRenderer {
  const PdfClaimPackRenderer();

  static const _accent = PdfColor.fromInt(0xFF0F766E);
  static const _muted = PdfColor.fromInt(0xFF64748B);
  static final _date = DateFormat('d MMM yyyy');

  /// The built-in PDF fonts only cover Latin-1.
  static String _t(String s) {
    final normalized = s
        .replaceAll(RegExp('[–—]'), '-')
        .replaceAll(RegExp('[‘’]'), "'")
        .replaceAll(RegExp('[“”]'), '"')
        .replaceAll('…', '...');
    return String.fromCharCodes(normalized.runes.map((r) => r == 0x0A || (r >= 0x20 && r <= 0xFF) ? r : 0x3F));
  }

  static String _money(Money m) => '${m.currency} ${NumberFormat('#,##0.00').format(m.major)}';

  @override
  Future<Uint8List> render(ClaimPackRequest req) async {
    final r = req.receipt;
    final now = req.generatedAt;
    final claimed = req.itemId == null ? r.items : r.items.where((i) => i.id == req.itemId).toList();
    final subject = claimed.length == 1 ? claimed.first.name : r.merchant;
    final doc = pw.Document(title: 'Warranty claim - $subject', author: req.claimantName);

    pw.Widget label(String text) =>
        pw.Text(text.toUpperCase(), style: const pw.TextStyle(fontSize: 8, color: _muted, letterSpacing: 0.8));

    pw.Widget kv(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(k, style: const pw.TextStyle(color: _muted, fontSize: 10)),
          ),
          pw.Expanded(
            child: pw.Text(_t(v), style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );

    String statusText(LineItem item) {
      final end = r.warrantyEndFor(item);
      return switch (ProtectionRules.statusFor(end, now)) {
        WarrantyStatus.none => 'No warranty',
        WarrantyStatus.expired => 'Expired ${_date.format(end!)}',
        WarrantyStatus.expiringSoon || WarrantyStatus.active => 'Valid until ${_date.format(end!)}',
      };
    }

    final coveredUntil = claimed
        .map(r.warrantyEndFor)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'KEEPR',
                style: const pw.TextStyle(
                  color: _accent,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
              pw.Text('Warranty claim pack', style: const pw.TextStyle(color: _muted, fontSize: 10)),
            ],
          ),
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated ${_date.format(now)} with Keepr', style: const pw.TextStyle(color: _muted, fontSize: 8)),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(color: _muted, fontSize: 8),
            ),
          ],
        ),
        build: (ctx) => [
          pw.SizedBox(height: 16),
          pw.Text(
            _t('Warranty claim: $subject'),
            style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _t('Purchased from ${r.merchant} on ${_date.format(r.purchaseDate)}'),
            style: const pw.TextStyle(color: _muted),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF0FDFA),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                label('Purchase summary'),
                pw.SizedBox(height: 6),
                kv('Claimant', req.claimantName + (req.claimantEmail == null ? '' : ' (${req.claimantEmail})')),
                kv('Seller', r.merchant),
                kv('Purchase date', _date.format(r.purchaseDate)),
                kv('Amount paid', _money(r.total)),
                if (r.paymentMethod != null) kv('Payment method', r.paymentMethod!),
                kv('Keepr reference', shortReference(r.id)),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          label('Items'),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Qty', 'Price', 'Serial no.', 'Warranty'],
            data: [
              for (final i in claimed)
                [_t(i.name), '${i.quantity}', _money(i.unitPrice), _t(i.serialNumber ?? '-'), statusText(i)],
            ],
            headerStyle: const pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: _accent),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.all(6),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
          pw.SizedBox(height: 18),
          label('Description of the problem'),
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(_t(req.issueDescription), style: const pw.TextStyle(fontSize: 10, lineSpacing: 3)),
          ),
          pw.SizedBox(height: 22),
          label('Claim letter'),
          pw.SizedBox(height: 8),
          pw.Text(_t('To the Customer Service team at ${r.merchant},'), style: const pw.TextStyle(fontSize: 10.5)),
          pw.SizedBox(height: 8),
          pw.Text(
            _t(
              'I purchased ${claimed.length == 1 ? 'the ${claimed.first.name}' : 'the items listed above'} from you on '
              '${_date.format(r.purchaseDate)} for ${_money(r.total)}. '
              '${coveredUntil != null && !coveredUntil.isBefore(now) ? 'The purchase is covered by warranty until ${_date.format(coveredUntil)}. ' : ''}'
              'The product has developed the problem described above. I am requesting a repair or replacement '
              'under the terms of the warranty. '
              '${req.images.isEmpty ? 'The purchase details above are taken from my original receipt.' : 'A copy of the original receipt and supporting photos are attached to this document.'}',
            ),
            style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Thank you for your help.', style: const pw.TextStyle(fontSize: 10.5)),
          pw.SizedBox(height: 24),
          pw.Text(_t(req.claimantName), style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          if (req.claimantEmail != null)
            pw.Text(_t(req.claimantEmail!), style: const pw.TextStyle(fontSize: 9, color: _muted)),
          pw.Text(_date.format(now), style: const pw.TextStyle(fontSize: 9, color: _muted)),
        ],
      ),
    );

    for (var i = 0; i < req.images.length; i++) {
      final image = pw.MemoryImage(req.images[i]);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Attachment ${i + 1} of ${req.images.length}',
                style: const pw.TextStyle(color: _accent, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 12),
              pw.Expanded(
                child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
              ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }
}
