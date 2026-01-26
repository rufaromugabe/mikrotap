import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/voucher.dart';

class VoucherPdfService {
  static Future<pw.Document> buildDoc(List<Voucher> vouchers, {String? dnsName}) async {
    final hotspotDns = dnsName ?? 'hotspot.mikrotap.com';
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
              children: vouchers.map((v) => _card(v, hotspotDns)).toList(),
            ),
          ];
        },
      ),
    );

    return doc;
  }

  static pw.Widget _card(Voucher v, String dnsName) {
    final isPin = v.username == v.password;
    final usedBytes = ((v.usageBytesIn ?? 0) + (v.usageBytesOut ?? 0));
    
    // Generate login URL
    final loginUrl = 'https://$dnsName/login?username=${Uri.encodeComponent(v.username)}&password=${Uri.encodeComponent(v.password)}';
    
    final lines = <String>[
      if (!isPin) 'Pass: ${v.password}',
      if (v.price != null) 'Price: \$${v.price}',
      if (v.soldByName != null) 'By: ${v.soldByName}',
      if (v.firstUsedAt != null)
        'Started: ${_formatDate(v.firstUsedAt!)}'
      else
        'Created: ${_formatDate(v.createdAt)}',
      if (usedBytes > 0) 'Used: ${_humanBytes(usedBytes)}',
    ];

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
          pw.Text(
            isPin ? 'PIN: ${v.username}' : 'User: ${v.username}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          if (lines.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            ...lines.map((line) => pw.Text(line, style: const pw.TextStyle(fontSize: 9))),
          ],
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: loginUrl,
              width: 80,
              height: 80,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  static String _humanBytes(int n) {
    const kb = 1024;
    const mb = 1024 * 1024;
    const gb = 1024 * 1024 * 1024;

    if (n >= gb) {
      return '${(n / gb).toStringAsFixed(2)} GB';
    } else if (n >= mb) {
      return '${(n / mb).toStringAsFixed(2)} MB';
    } else if (n >= kb) {
      return '${(n / kb).toStringAsFixed(2)} KB';
    }
    return '$n B';
  }
}

