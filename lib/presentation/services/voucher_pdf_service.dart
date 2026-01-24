import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/voucher.dart';

class VoucherPdfService {
  static Future<pw.Document> buildDoc(List<Voucher> vouchers) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          return [
            pw.Text('MikroTap vouchers', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: vouchers.map(_card).toList(),
            ),
          ];
        },
      ),
    );

    return doc;
  }

  static pw.Widget _card(Voucher v) {
    return pw.Container(
      width: 170,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey700),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Voucher', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('User: ${v.username}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Pass: ${v.password}', style: const pw.TextStyle(fontSize: 10)),
          if (v.profile != null && v.profile!.isNotEmpty)
            pw.Text('Profile: ${v.profile}', style: const pw.TextStyle(fontSize: 10)),
          if (v.expiresAt != null)
            pw.Text('Expires: ${v.expiresAt}', style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

