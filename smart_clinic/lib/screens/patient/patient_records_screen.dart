import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../config/api_config.dart';
import '../../services/medical_service.dart';
import '../../services/api_service.dart';
import '../../models/medical_record.dart';
import '../../models/prescription.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/bottom_nav.dart';

class PatientRecordsScreen extends StatefulWidget {
  const PatientRecordsScreen({super.key});

  @override
  State<PatientRecordsScreen> createState() => _PatientRecordsScreenState();
}

class _PatientRecordsScreenState extends State<PatientRecordsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MedicalService _service = MedicalService();
  List<MedicalRecord> _records = [];
  List<Prescription> _prescriptions = [];
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _records = await _service.getPatientRecords();
      _prescriptions = await _service.getPrescriptions();
      final filesResponse = await ApiService.instance.get('/patients/documents');
      if (filesResponse is List) {
        _files = filesResponse.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('medical_records')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: AppLocalizations.tr('diagnoses')),
            Tab(text: AppLocalizations.tr('prescriptions')),
            Tab(text: AppLocalizations.tr('files')),
          ],
        ),
      ),
      body: _isLoading
          ? const LoadingWidget()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRecordsList(),
                _buildPrescriptionsList(),
                _buildFilesList(),
              ],
            ),
      bottomNavigationBar: const BottomNav(currentIndex: 3, role: 'patient'),
    );
  }

  Widget _buildRecordsList() {
    if (_records.isEmpty) {
      return EmptyState(icon: Icons.medical_information, message: AppLocalizations.tr('no_records'));
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _records.length,
        itemBuilder: (ctx, i) {
          final r = _records[i];
          return Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _severityColor(r.severity).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.medical_information, color: _severityColor(r.severity)),
              ),
              title: Text(r.diagnosis ?? AppLocalizations.tr('diagnosis')),
              subtitle: Text([
                if (r.doctorName != null && r.doctorName!.trim().isNotEmpty) r.doctorName!,
                if (r.visitDate != null && r.visitDate!.trim().isNotEmpty) r.visitDate!,
              ].join(' · ')),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _severityColor(r.severity).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  AppLocalizations.tr(r.severity ?? 'mild'),
                  style: TextStyle(color: _severityColor(r.severity), fontSize: 12),
                ),
              ),
              onTap: () => Navigator.pushNamed(context, AppRoutes.patientRecordDetail, arguments: r),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPrescriptionsList() {
    if (_prescriptions.isEmpty) {
      return EmptyState(icon: Icons.medication, message: AppLocalizations.tr('no_data'));
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _prescriptions.length,
        itemBuilder: (ctx, i) {
          final p = _prescriptions[i];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.medication)),
              title: Text('${AppLocalizations.tr('prescriptions')} #${p.id ?? i + 1}'),
              subtitle: Text('${p.doctorName ?? ''} - ${p.createdAt ?? ''}'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF388E3C).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  AppLocalizations.tr(p.status ?? 'active'),
                  style: const TextStyle(color: Color(0xFF388E3C), fontSize: 12),
                ),
              ),
              onTap: () => Navigator.pushNamed(context, AppRoutes.patientPrescriptionDetail, arguments: p),
            ),
          );
        },
      ),
    );
  }

  Future<void> _uploadFile() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    try {
      final uri = Uri.parse('${ApiConfig.url}/patients/documents/upload');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${ApiService.instance.currentToken}';
      request.fields['category'] = 'other';
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
        contentType: MediaType('application', 'octet-stream'),
      ));

      final response = await request.send();
      if (response.statusCode == 200) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('file_uploaded')), backgroundColor: const Color(0xFF388E3C)),
        );
        _loadData();
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Upload failed (${response.statusCode})'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildFilesList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _uploadFile,
              icon: const Icon(Icons.upload_file),
              label: Text(AppLocalizations.tr('upload_files')),
            ),
          ),
        ),
        Expanded(
          child: _files.isEmpty
              ? EmptyState(icon: Icons.folder_open, message: AppLocalizations.tr('no_data'))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.open_in_new, color: Theme.of(context).colorScheme.primary),
                                onPressed: () => _openFile(f['file_url']),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFD32F2F)),
                                onPressed: () async {
                                  try {
                                    await ApiService.instance.delete('/patients/documents/${f['id']}');
                                    _loadData();
                                  } catch (_) {}
                                },
                              ),
                            ],
                          ),
                          onTap: () => _openFile(f['file_url']),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _openFile(String? fileUrl) async {
    if (fileUrl == null) return;
    final url = '${ApiConfig.url}$fileUrl';
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open file'), backgroundColor: Colors.red),
        );
      }
    }
  }

  IconData _fileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png')) return Icons.image;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description;
    return Icons.insert_drive_file;
  }

  Color _severityColor(String? severity) {
    switch (severity) {
      case 'severe':
        return const Color(0xFFD32F2F);
      case 'moderate':
        return const Color(0xFFF57C00);
      default:
        return const Color(0xFF388E3C);
    }
  }
}
