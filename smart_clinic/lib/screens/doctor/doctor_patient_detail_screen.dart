import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../config/api_config.dart';
import '../../config/sensor_colors.dart';
import '../../services/api_service.dart';
import '../../services/medical_service.dart';
import '../../services/sensor_service.dart';
import '../../models/medical_record.dart';
import '../../models/prescription.dart';
import '../../models/sensor_reading.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';
import '../../services/report_download_service.dart';
import '../../widgets/sensor_waveform_chart.dart';
import '../../widgets/sensor_vitals_icons_row.dart';
import '../../widgets/user_avatar.dart';
import '../../utils/ui_helpers.dart';

class DoctorPatientDetailScreen extends StatefulWidget {
  const DoctorPatientDetailScreen({super.key});

  @override
  State<DoctorPatientDetailScreen> createState() => _DoctorPatientDetailScreenState();
}

class _DoctorPatientDetailScreenState extends State<DoctorPatientDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MedicalService _medicalService = MedicalService();
  final SensorService _sensorService = SensorService();
  Map<String, dynamic>? _patient;
  List<MedicalRecord> _records = [];
  List<Prescription> _prescriptions = [];
  List<Map<String, dynamic>> _files = [];
  List<SensorReading> _sensorHistory = [];
  bool _isLoading = true;
  bool _showInactive = true;
  bool _savingMedicalInfo = false;
  final _bloodTypeController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _chronicDiseasesController = TextEditingController();
  final _existingConditionsController = TextEditingController();
  Timer? _sensorRefreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _patient = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _loadData();
    });
    _sensorRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _tabController.index == 2) {
        unawaited(_refreshSensorHistory());
      }
    });
  }

  Future<void> _refreshSensorHistory() async {
    if (_patientId == null) return;
    try {
      final history = await _sensorService.getHistory(patientId: _patientId);
      if (mounted) setState(() => _sensorHistory = history);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sensorRefreshTimer?.cancel();
    _tabController.dispose();
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _chronicDiseasesController.dispose();
    _existingConditionsController.dispose();
    super.dispose();
  }

  String? get _patientId => _patient?['profile_id']?.toString() ?? _patient?['id']?.toString();

  Future<void> _loadData() async {
    if (_patientId == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      try {
        final profileResponse = await ApiService.instance.get('/patients/profile?patient_id=$_patientId');
        final profileData = Map<String, dynamic>.from(profileResponse);
        final nestedProfile = profileData['profile'];
        _patient = {
          ...?_patient,
          ...profileData,
          'profile': nestedProfile is Map
              ? Map<String, dynamic>.from(nestedProfile)
              : profileData,
        };
      } catch (_) {}
      _syncMedicalInfoControllers();
      _records = await _medicalService.getPatientRecords(patientId: _patientId, includeInactive: true);
      _prescriptions = await _medicalService.getPrescriptions(patientId: _patientId, includeInactive: true);
      _sensorHistory = await _sensorService.getHistory(patientId: _patientId);
      try {
        final filesResponse = await ApiService.instance.get('/patients/documents?patient_id=$_patientId');
        if (filesResponse is List) {
          _files = filesResponse.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  List<MedicalRecord> get _visibleRecords =>
      _showInactive ? _records : _records.where((r) => r.isActive).toList();

  List<Prescription> get _visiblePrescriptions =>
      _showInactive ? _prescriptions : _prescriptions.where((p) => p.status == 'active').toList();

  String _prescriptionLabel(Prescription p) {
    if (p.items != null && p.items!.isNotEmpty) {
      return p.items!.map((i) => i.medicationName ?? '').where((n) => n.isNotEmpty).join(', ');
    }
    return '${AppLocalizations.tr('prescriptions')} #${(p.id ?? '').substring(0, 8)}';
  }

  Future<void> _toggleRecord(MedicalRecord record) async {
    if (record.id == null) return;
    final activate = !record.isActive;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(activate ? AppLocalizations.tr('activate') : AppLocalizations.tr('deactivate')),
        content: Text(
          activate
              ? AppLocalizations.tr('activate_diagnosis_confirm')
              : AppLocalizations.tr('deactivate_diagnosis_confirm'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.tr('confirm'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _medicalService.setRecordActive(record.id!, activate);
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('success'));
      _loadData();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _deleteRecord(MedicalRecord record) async {
    if (record.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('delete')),
        content: Text(AppLocalizations.tr('delete_diagnosis_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.tr('delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _medicalService.deleteRecord(record.id!);
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('success'));
      _loadData();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _togglePrescription(Prescription p) async {
    if (p.id == null) return;
    if (p.status == 'active') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.tr('deactivate')),
          content: Text(AppLocalizations.tr('deactivate_prescription_confirm')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.tr('deactivate'))),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        await _medicalService.updatePrescriptionStatus(p.id!, 'cancelled');
        if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('success'));
        _loadData();
      } catch (e) {
        if (mounted) showErrorSnackBar(context, e);
      }
      return;
    }

    DateTime? activeUntil;
    var useExpiry = false;
    final now = DateTime.now();
    var pickedDate = now.add(const Duration(days: 7));
    var pickedTime = TimeOfDay.fromDateTime(now.add(const Duration(hours: 1)));

    final activate = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(AppLocalizations.tr('activate_prescription')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.tr('activate_prescription_desc')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppLocalizations.tr('set_active_until')),
                  value: useExpiry,
                  onChanged: (v) => setLocal(() => useExpiry = v),
                ),
                if (useExpiry) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppLocalizations.tr('active_until_date')),
                    subtitle: Text('${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: pickedDate,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                      );
                      if (d != null) setLocal(() => pickedDate = d);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppLocalizations.tr('active_until_time')),
                    subtitle: Text(pickedTime.format(ctx)),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final t = await showTimePicker(context: ctx, initialTime: pickedTime);
                      if (t != null) setLocal(() => pickedTime = t);
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.tr('activate'))),
          ],
        ),
      ),
    );
    if (activate != true) return;

    if (useExpiry) {
      activeUntil = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      if (!activeUntil.isAfter(DateTime.now())) {
        if (mounted) showErrorSnackBar(context, AppLocalizations.tr('active_until_future'));
        return;
      }
    }

    try {
      await _medicalService.updatePrescriptionStatus(p.id!, 'active', activeUntil: activeUntil);
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('success'));
      _loadData();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _deletePrescription(Prescription p) async {
    if (p.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('delete')),
        content: Text(AppLocalizations.tr('delete_prescription_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.tr('delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _medicalService.deletePrescription(p.id!);
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('success'));
      _loadData();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _downloadPatientActivityReport(String format) async {
    if (_patientId == null) return;
    try {
      await ReportDownloadService.download(
        '/reports/doctor-activity',
        filename: 'doctor_activity_patient',
        queryParams: {'patient_id': _patientId!},
        format: format,
      );
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('report_download_info'));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _showActivityReport() async {
    try {
      final report = await _medicalService.getDoctorActivityReport(patientId: _patientId);
      if (!mounted) return;
      final entries = (report['entries'] as List?) ?? [];
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.tr('activity_report')),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: entries.isEmpty
                ? Center(child: Text(AppLocalizations.tr('no_data')))
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (_, i) {
                      final e = Map<String, dynamic>.from(entries[i] as Map);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e['timestamp'] ?? ''} · ${e['action'] ?? ''}',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text('${e['entity_type'] ?? ''}: ${e['details'] ?? ''}'),
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _downloadPatientActivityReport('pdf');
              },
              child: Text(AppLocalizations.tr('format_pdf')),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _downloadPatientActivityReport('csv');
              },
              child: Text(AppLocalizations.tr('format_csv')),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _downloadPatientActivityReport('xlsx');
              },
              child: Text(AppLocalizations.tr('format_xlsx')),
            ),
            TextButton(
              onPressed: () {
                final buffer = StringBuffer();
                buffer.writeln('${report['doctor_name'] ?? 'Doctor'} — ${AppLocalizations.tr('activity_report')}');
                if (report['patient_name'] != null) buffer.writeln('${AppLocalizations.tr('patient')}: ${report['patient_name']}');
                buffer.writeln('');
                for (final raw in entries) {
                  final e = Map<String, dynamic>.from(raw as Map);
                  buffer.writeln('[${e['timestamp']}] ${e['action']} (${e['entity_type']})');
                  buffer.writeln('  ${e['details']}');
                  buffer.writeln('');
                }
                Clipboard.setData(ClipboardData(text: buffer.toString()));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.tr('copied'))));
              },
              child: Text(AppLocalizations.tr('copy')),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.tr('close'))),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _patient != null ? '${_patient!['first_name'] ?? ''} ${_patient!['last_name'] ?? ''}'.trim() : '';
    final profile = _patient?['profile'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.summarize_outlined),
            tooltip: AppLocalizations.tr('activity_report'),
            onPressed: _showActivityReport,
          ),
          IconButton(
            icon: const Icon(Icons.sensors),
            tooltip: AppLocalizations.tr('measure_vitals'),
            onPressed: () => Navigator.pushNamed(
              context,
              AppRoutes.doctorSensors,
              arguments: {'patient_id': _patientId, 'patient_name': name},
            ),
          ),
          IconButton(
            icon: const Icon(Icons.note_add),
            tooltip: AppLocalizations.tr('add_record'),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.doctorCreateRecord, arguments: {'patient': _patient}),
          ),
          IconButton(
            icon: const Icon(Icons.medication),
            tooltip: AppLocalizations.tr('add_prescription'),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.doctorCreatePrescription, arguments: _patient),
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : _patientId == null
              ? Center(child: Text(AppLocalizations.tr('error')))
              : Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        UserAvatar(
                          name: name,
                          photoUrl: profile?['photo_url']?.toString(),
                          patientId: _patientId,
                          radius: 30,
                          loadFromApi: false,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: Theme.of(context).textTheme.titleLarge),
                              if (profile?['gender'] != null || profile?['blood_type'] != null)
                                Text('${AppLocalizations.trValue(profile?['gender'])} - ${profile?['blood_type'] ?? ''}', style: Theme.of(context).textTheme.bodyMedium),
                              if (profile?['allergies'] != null && (profile!['allergies'] as String).isNotEmpty)
                                Text('${AppLocalizations.tr('allergies')}: ${profile['allergies']}', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(child: Text(AppLocalizations.tr('show_inactive'), style: Theme.of(context).textTheme.bodyMedium)),
                      Switch(value: _showInactive, onChanged: (v) => setState(() => _showInactive = v)),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  tabs: [
                    Tab(text: AppLocalizations.tr('diagnoses')),
                    Tab(text: AppLocalizations.tr('prescriptions')),
                    Tab(text: AppLocalizations.tr('sensors')),
                    Tab(text: AppLocalizations.tr('files')),
                    Tab(text: AppLocalizations.tr('medical_info')),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRecords(),
                      _buildPrescriptions(),
                      _buildSensors(),
                      _buildFiles(),
                      _buildMedicalInfo(profile),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRecords() {
    if (_visibleRecords.isEmpty) return EmptyState(icon: Icons.medical_information, message: AppLocalizations.tr('no_records'));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _visibleRecords.length,
      itemBuilder: (ctx, i) {
        final r = _visibleRecords[i];
        final inactive = !r.isActive;
        return Card(
          color: inactive ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
          child: ListTile(
            title: Text(
              r.diagnosis ?? '',
              style: TextStyle(
                decoration: inactive ? TextDecoration.lineThrough : null,
                color: inactive ? Colors.grey : null,
              ),
            ),
            subtitle: Text('${r.visitDate ?? r.createdAt ?? ''} - ${AppLocalizations.tr(r.severity ?? 'mild')}'),
            trailing: PopupMenuButton<String>(
              onSelected: (action) async {
                switch (action) {
                  case 'view':
                    Navigator.pushNamed(context, AppRoutes.doctorRecordDetail, arguments: r);
                  case 'edit':
                    final changed = await Navigator.pushNamed<bool>(
                      context,
                      AppRoutes.doctorConsultation,
                      arguments: {'patient': _patient, 'record_id': r.id},
                    );
                    if (changed == true && mounted) _loadData();
                  case 'toggle':
                    await _toggleRecord(r);
                  case 'delete':
                    await _deleteRecord(r);
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'view', child: Text(AppLocalizations.tr('view'))),
                PopupMenuItem(value: 'edit', child: Text(AppLocalizations.tr('edit'))),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(r.isActive ? AppLocalizations.tr('deactivate') : AppLocalizations.tr('activate')),
                ),
                PopupMenuItem(value: 'delete', child: Text(AppLocalizations.tr('delete'))),
              ],
            ),
            onTap: () => Navigator.pushNamed(context, AppRoutes.doctorRecordDetail, arguments: r),
          ),
        );
      },
    );
  }

  Widget _buildPrescriptions() {
    if (_visiblePrescriptions.isEmpty) return EmptyState(icon: Icons.medication, message: AppLocalizations.tr('no_data'));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _visiblePrescriptions.length,
      itemBuilder: (ctx, i) {
        final p = _visiblePrescriptions[i];
        final inactive = p.status != 'active';
        return Card(
          color: inactive ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
          child: ListTile(
            leading: Icon(Icons.medication, color: inactive ? Colors.grey : Theme.of(context).colorScheme.primary),
            title: Text(
              _prescriptionLabel(p),
              style: TextStyle(
                decoration: inactive ? TextDecoration.lineThrough : null,
                color: inactive ? Colors.grey : null,
              ),
            ),
            subtitle: Text(
              [
                AppLocalizations.tr(p.status ?? 'active'),
                if (p.activeUntil != null && p.activeUntil!.isNotEmpty)
                  '${AppLocalizations.tr('until')} ${p.activeUntil!.replaceFirst('T', ' ').split('.').first}',
                p.createdAt ?? '',
              ].where((s) => s.isNotEmpty).join(' · '),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) async {
                switch (action) {
                  case 'view':
                    Navigator.pushNamed(context, AppRoutes.doctorPrescriptionDetail, arguments: p);
                  case 'toggle':
                    await _togglePrescription(p);
                  case 'delete':
                    await _deletePrescription(p);
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'view', child: Text(AppLocalizations.tr('view'))),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(p.status == 'active' ? AppLocalizations.tr('deactivate') : AppLocalizations.tr('activate')),
                ),
                PopupMenuItem(value: 'delete', child: Text(AppLocalizations.tr('delete'))),
              ],
            ),
            onTap: () => Navigator.pushNamed(context, AppRoutes.doctorPrescriptionDetail, arguments: p),
          ),
        );
      },
    );
  }

  Widget _buildSensors() {
    if (_sensorHistory.isEmpty) return EmptyState(icon: Icons.sensors, message: AppLocalizations.tr('no_readings'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _sensorHistory.length,
      itemBuilder: (ctx, i) {
        final r = _sensorHistory[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(r.timestamp ?? '', style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SensorVitalsIconsRow(
                  heartRate: r.heartRate,
                  temperature: r.temperature,
                  gsr: r.gsr,
                  ecg: r.ecg,
                  emg: r.emg,
                ),
                const SizedBox(height: 12),
                SensorWaveformChart(
                  title: AppLocalizations.tr('ecg'),
                  shortLabel: 'ECG',
                  samples: r.waveformSamples('ecg'),
                  currentValue: r.ecg,
                  color: SensorPlotterColors.ecg,
                  height: 120,
                ),
                const SizedBox(height: 8),
                SensorWaveformChart(
                  title: AppLocalizations.tr('emg'),
                  shortLabel: 'EMG',
                  samples: r.waveformSamples('emg'),
                  currentValue: r.emg,
                  color: SensorPlotterColors.emg,
                  height: 120,
                ),
                const SizedBox(height: 8),
                SensorWaveformChart(
                  title: AppLocalizations.tr('gsr_waveform'),
                  shortLabel: 'GSR',
                  samples: r.waveformSamples('gsr'),
                  currentValue: r.gsr,
                  color: SensorPlotterColors.gsr,
                  height: 120,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFiles() {
    if (_files.isEmpty) return EmptyState(icon: Icons.folder_open, message: AppLocalizations.tr('no_data'));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _files.length,
      itemBuilder: (ctx, i) {
        final f = _files[i];
        final fileName = f['file_name'] ?? 'File';
        final category = f['category'] ?? 'other';
        final uploadDate = f['upload_date'] ?? '';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(_fileIcon(fileName), color: Theme.of(context).colorScheme.primary),
            ),
            title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('$category - $uploadDate'),
            trailing: Icon(Icons.open_in_new, color: Theme.of(context).colorScheme.primary, size: 20),
            onTap: () => _openFile(f['file_url']),
          ),
        );
      },
    );
  }

  Future<void> _openFile(String? fileUrl) async {
    if (fileUrl == null) return;
    final url = '${ApiConfig.url}$fileUrl';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  IconData _fileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png')) return Icons.image;
    return Icons.insert_drive_file;
  }

  Widget _buildMedicalInfo(Map<String, dynamic>? profile) {
    if (profile == null) return EmptyState(icon: Icons.info, message: AppLocalizations.tr('no_data'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _bloodTypeController,
          decoration: InputDecoration(
            labelText: AppLocalizations.tr('blood_type'),
            prefixIcon: const Icon(Icons.bloodtype),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _allergiesController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: AppLocalizations.tr('allergies'),
            prefixIcon: const Icon(Icons.warning_amber),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _chronicDiseasesController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: AppLocalizations.tr('chronic_diseases'),
            prefixIcon: const Icon(Icons.medical_services),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _existingConditionsController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: AppLocalizations.tr('existing_conditions'),
            prefixIcon: const Icon(Icons.health_and_safety),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _savingMedicalInfo ? null : _saveMedicalInfo,
            icon: _savingMedicalInfo
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(AppLocalizations.tr('save_changes')),
          ),
        ),
      ],
    );
  }

  void _syncMedicalInfoControllers() {
    final profile = _patient?['profile'] is Map
        ? Map<String, dynamic>.from(_patient!['profile'] as Map)
        : _patient;
    if (profile == null) return;
    _bloodTypeController.text = profile['blood_type']?.toString() ?? '';
    _allergiesController.text = profile['allergies']?.toString() ?? '';
    _chronicDiseasesController.text = profile['chronic_diseases']?.toString() ?? '';
    _existingConditionsController.text = profile['existing_conditions']?.toString() ?? '';
  }

  Future<void> _saveMedicalInfo() async {
    if (_patientId == null) return;
    setState(() => _savingMedicalInfo = true);
    try {
      await ApiService.instance.put('/patients/profile/$_patientId', {
        'blood_type': _bloodTypeController.text.trim(),
        'allergies': _allergiesController.text.trim(),
        'chronic_diseases': _chronicDiseasesController.text.trim(),
        'existing_conditions': _existingConditionsController.text.trim(),
      });
      if (mounted) {
        showSuccessSnackBar(context, AppLocalizations.tr('profile_updated'));
        await _loadData();
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _savingMedicalInfo = false);
    }
  }
}
