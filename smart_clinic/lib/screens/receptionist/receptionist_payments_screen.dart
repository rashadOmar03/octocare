import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../../l10n/localization.dart';
import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../models/payment.dart';
import '../../models/appointment.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/receptionist_scaffold.dart';
import '../../services/receptionist_service.dart';
import '../../utils/ui_helpers.dart';
import '../../utils/time_format.dart';

class ReceptionistPaymentsScreen extends StatefulWidget {
  const ReceptionistPaymentsScreen({super.key});

  @override
  State<ReceptionistPaymentsScreen> createState() => _ReceptionistPaymentsScreenState();
}

class _ReceptionistPaymentsScreenState extends State<ReceptionistPaymentsScreen> {
  final _receptionistService = ReceptionistService();
  List<Payment> _payments = [];
  bool _isLoading = true;
  double _todayCollected = 0;
  double _consultationFee = 100;
  String? _loadError;
  String? _statusFilter;
  bool _todayOnly = true;
  String? _pendingAppointmentId;
  bool _pendingOpenDialog = false;
  bool _dialogHandled = false;

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pendingAppointmentId == null && !_dialogHandled) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _pendingAppointmentId = args['appointment_id']?.toString();
        _pendingOpenDialog = args['open_dialog'] == true;
      }
    }
  }

  void _maybeOpenPaymentDialog() {
    if (!_pendingOpenDialog || _dialogHandled) return;
    _dialogHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showPaymentDialog(preselectedAppointmentId: _pendingAppointmentId);
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final clinic = await _receptionistService.getClinicInfo();
      final dashboard = await _receptionistService.getDashboard();
      _consultationFee = clinic.defaultFee;
      _todayCollected = dashboard.todayRevenue;
      var endpoint = '/receptionist/payments';
      final params = <String>[];
      if (_todayOnly) params.add('date=$_todayStr');
      if (_statusFilter != null && _statusFilter!.isNotEmpty) params.add('status=$_statusFilter');
      if (params.isNotEmpty) endpoint += '?${params.join('&')}';
      final response = await ApiService.instance.get(endpoint);
      final List<dynamic> data = response is List ? response : (response['results'] ?? []);
      _payments = data.map((e) => Payment.fromJson(e)).toList();
    } catch (e) {
      _loadError = extractApiError(e);
    }
    if (mounted) {
      setState(() => _isLoading = false);
      _maybeOpenPaymentDialog();
    }
  }

  String _methodLabel(String? method) {
    switch (method) {
      case 'instapay':
        return AppLocalizations.tr('instapay');
      case 'cash':
        return AppLocalizations.tr('cash');
      default:
        return method ?? '';
    }
  }

  Future<Uint8List?> _readProofBytes(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return file.bytes;
    }
    final stream = file.readStream;
    if (stream != null) {
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }
      if (chunks.isNotEmpty) {
        return Uint8List.fromList(chunks);
      }
    }
    return null;
  }

  void _showPaymentDialog({String? preselectedAppointmentId}) async {
    List<Appointment> payable = [];
    try {
      final response = await ApiService.instance.get('/receptionist/payable-appointments');
      final List<dynamic> data = response is List ? response : (response['results'] ?? []);
      payable = List<Appointment>.from(
        (data as List).map((e) => Appointment.fromJson(Map<String, dynamic>.from(e as Map))),
      );
    } catch (_) {}

    if (!mounted) return;
    if (payable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.tr('no_unpaid_appointments'))));
      return;
    }

    Appointment? selectedAppointment;
    if (preselectedAppointmentId != null) {
      for (final apt in payable) {
        if (apt.id == preselectedAppointmentId) {
          selectedAppointment = apt;
          break;
        }
      }
    }
    String method = 'cash';
    PlatformFile? proofFile;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.tr('record_payment')),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.tr('select_appointment'), style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Appointment>(
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    hint: Text(AppLocalizations.tr('select_appointment')),
                    value: selectedAppointment,
                    items: payable
                        .map(
                          (a) => DropdownMenuItem(
                            value: a,
                            child: Text(
                              '${a.patientName} — ${a.date} ${TimeFormat.format24To12(a.timeSlot)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedAppointment = v),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppLocalizations.tr('consultation_fee')),
                    trailing: Text(
                      '$_consultationFee ${AppLocalizations.tr('egp')}',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(AppLocalizations.tr('payment_method'), style: Theme.of(ctx).textTheme.labelLarge),
                  RadioListTile<String>(
                    title: Text(AppLocalizations.tr('cash')),
                    value: 'cash',
                    groupValue: method,
                    onChanged: (v) => setDialogState(() => method = v ?? 'cash'),
                  ),
                  RadioListTile<String>(
                    title: Text(AppLocalizations.tr('instapay')),
                    value: 'instapay',
                    groupValue: method,
                    onChanged: (v) => setDialogState(() => method = v ?? 'instapay'),
                  ),
                  if (method == 'instapay') ...[
                    const SizedBox(height: 8),
                    Text(AppLocalizations.tr('instapay_proof_required_note'), style: Theme.of(ctx).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
                        if (result != null && result.files.isNotEmpty) {
                          setDialogState(() => proofFile = result.files.first);
                        }
                      },
                      icon: const Icon(Icons.upload_file),
                      label: Text(proofFile?.name ?? AppLocalizations.tr('upload_instapay_screenshot')),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: Text(AppLocalizations.tr('cancel'))),
            ElevatedButton(
              onPressed: saving || selectedAppointment?.id == null
                  ? null
                  : () async {
                      Uint8List? proofBytes;
                      if (method == 'instapay') {
                        if (proofFile == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(AppLocalizations.tr('instapay_proof_required'))),
                          );
                          return;
                        }
                        proofBytes = await _readProofBytes(proofFile!);
                        if (proofBytes == null || proofBytes.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(AppLocalizations.tr('instapay_proof_required'))),
                          );
                          return;
                        }
                      }
                      setDialogState(() => saving = true);
                      try {
                        if (method == 'instapay' && proofBytes != null) {
                          final name = proofFile!.name.isNotEmpty ? proofFile!.name : 'instapay_proof.png';
                          await ApiService.instance.post('/receptionist/payments/instapay', {
                            'appointment_id': selectedAppointment!.id,
                            'proof_base64': base64Encode(proofBytes),
                            'proof_filename': name,
                          });
                        } else {
                          final request = http.MultipartRequest(
                            'POST',
                            Uri.parse('${ApiConfig.url}/receptionist/payments'),
                          );
                          request.headers['Authorization'] = 'Bearer ${ApiService.instance.currentToken}';
                          request.fields['appointment_id'] = selectedAppointment!.id!;
                          request.fields['payment_method'] = method;
                          final streamed = await request.send();
                          final body = await streamed.stream.bytesToString();
                          if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
                            String message = AppLocalizations.tr('error');
                            try {
                              final decoded = json.decode(body);
                              if (decoded is Map && decoded['detail'] != null) {
                                message = decoded['detail'].toString();
                              }
                            } catch (_) {}
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                            }
                            setDialogState(() => saving = false);
                            return;
                          }
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadData();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(AppLocalizations.tr('payment_recorded')),
                              backgroundColor: const Color(0xFF388E3C),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      }
                      if (ctx.mounted) setDialogState(() => saving = false);
                    },
              child: saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(AppLocalizations.tr('save')),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentDetail(Payment payment) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(payment.invoiceRef ?? AppLocalizations.tr('payment_record')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${AppLocalizations.tr('patient')}: ${payment.patientName ?? ''}'),
              Text('${AppLocalizations.tr('doctor')}: ${payment.doctorName ?? ''}'),
              Text('${AppLocalizations.tr('date')}: ${payment.appointmentDate ?? payment.date ?? ''}'),
              Text('${AppLocalizations.tr('time')}: ${TimeFormat.format24To12(payment.timeSlot ?? '')}'),
              Text('${AppLocalizations.tr('amount')}: ${payment.amount?.toStringAsFixed(0) ?? '100'} ${AppLocalizations.tr('egp')}'),
              Text('${AppLocalizations.tr('payment_method')}: ${_methodLabel(payment.method)}'),
              Text('${AppLocalizations.tr('status')}: ${payment.status == 'refunded' ? AppLocalizations.tr('refunded') : (payment.status ?? '')}'),
              if (payment.refundReason != null) Text('${AppLocalizations.tr('refund_reason')}: ${payment.refundReason}'),
              if (payment.refundProofUrl != null && payment.refundProofUrl!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(AppLocalizations.tr('refund_proof')),
                const SizedBox(height: 8),
                Image.network('${ApiConfig.url}${payment.refundProofUrl}', height: 180, fit: BoxFit.contain),
              ],
              if (payment.proofUrl != null) ...[
                const SizedBox(height: 12),
                Text(AppLocalizations.tr('instapay_screenshot')),
                const SizedBox(height: 8),
                Image.network('${ApiConfig.url}${payment.proofUrl}', height: 180, fit: BoxFit.contain),
              ],
            ],
          ),
        ),
        actions: [
          if (payment.status == 'paid')
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showRefundDialog(payment);
              },
              child: Text(AppLocalizations.tr('refund_payment')),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.tr('close'))),
        ],
      ),
    );
  }

  void _showRefundDialog(Payment payment) {
    final reasonController = TextEditingController();
    PlatformFile? proofFile;
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.tr('refund_payment')),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(labelText: AppLocalizations.tr('refund_reason')),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Text(AppLocalizations.tr('refund_proof_optional_note'), style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Text(AppLocalizations.tr('upload_refund_proof'), style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
                      if (result != null && result.files.isNotEmpty) {
                        setDialogState(() => proofFile = result.files.first);
                      }
                    },
                    icon: const Icon(Icons.upload_file),
                    label: Text(proofFile?.name ?? AppLocalizations.tr('upload_refund_screenshot')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: Text(AppLocalizations.tr('cancel'))),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (reasonController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppLocalizations.tr('required'))),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        String? proofBase64;
                        var proofFilename = 'refund_proof.png';
                        if (proofFile != null) {
                          final bytes = await _readProofBytes(proofFile!);
                          if (bytes != null && bytes.isNotEmpty) {
                            proofBase64 = base64Encode(bytes);
                            proofFilename = proofFile!.name.isNotEmpty ? proofFile!.name : proofFilename;
                          }
                        }
                        await ApiService.instance.post('/receptionist/payments/${payment.id}/refund', {
                          'reason': reasonController.text.trim(),
                          if (proofBase64 != null) 'proof_base64': proofBase64,
                          'proof_filename': proofFilename,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadData();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(AppLocalizations.tr('refund_recorded')), backgroundColor: const Color(0xFF388E3C)),
                          );
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                      if (ctx.mounted) setDialogState(() => saving = false);
                    },
              child: saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(AppLocalizations.tr('confirm')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReceptionistScaffold(
      title: AppLocalizations.tr('payments'),
      bottomNavIndex: 3,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showPaymentDialog,
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.tr('record_payment')),
      ),
      body: _isLoading
          ? const LoadingWidget()
          : Column(
              children: [
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    color: const Color(0xFF388E3C).withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(AppLocalizations.tr('today_revenue'), style: Theme.of(context).textTheme.bodySmall),
                                Text(
                                  '${_todayCollected.toStringAsFixed(0)} ${AppLocalizations.tr('egp')}',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        color: const Color(0xFF388E3C),
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '$_consultationFee ${AppLocalizations.tr('egp')} / ${AppLocalizations.tr('visit')}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      FilterChip(
                        label: Text(_todayOnly ? AppLocalizations.tr('today_only') : AppLocalizations.tr('all_dates')),
                        selected: _todayOnly,
                        onSelected: (_) {
                          setState(() => _todayOnly = !_todayOnly);
                          _loadData();
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _statusFilter,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.tr('filter_status'),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: [
                            DropdownMenuItem(value: null, child: Text(AppLocalizations.tr('all_statuses'))),
                            DropdownMenuItem(value: 'paid', child: Text(AppLocalizations.tr('paid'))),
                            DropdownMenuItem(value: 'refunded', child: Text(AppLocalizations.tr('refunded'))),
                          ],
                          onChanged: (v) {
                            setState(() => _statusFilter = v);
                            _loadData();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _payments.isEmpty
                      ? EmptyState(icon: Icons.payment, message: AppLocalizations.tr('no_data'))
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _payments.length,
                            itemBuilder: (ctx, i) {
                              final p = _payments[i];
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF388E3C).withValues(alpha: 0.1),
                                    child: const Icon(Icons.receipt_long, color: Color(0xFF388E3C)),
                                  ),
                                  title: Text(p.patientName ?? p.invoiceRef ?? ''),
                                  subtitle: Text(
                                    '${_methodLabel(p.method)} — ${p.status == 'refunded' ? AppLocalizations.tr('refunded') : AppLocalizations.tr('paid')} — ${p.appointmentDate ?? ''}',
                                  ),
                                  trailing: Text(
                                    '${p.amount?.toStringAsFixed(0) ?? _consultationFee.toStringAsFixed(0)} ${AppLocalizations.tr('egp')}',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  onTap: () => _showPaymentDetail(p),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
