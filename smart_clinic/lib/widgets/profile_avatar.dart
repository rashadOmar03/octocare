import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';

class ProfileAvatar extends StatelessWidget {
  final String? photoUrl;
  final String? name;
  final double radius;
  final VoidCallback? onPhotoChanged;

  const ProfileAvatar({
    super.key,
    this.photoUrl,
    this.name,
    this.radius = 40,
    this.onPhotoChanged,
  });

  Future<void> _uploadPhoto(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;

    final file = result.files.first;
    try {
      final uri = Uri.parse('${ApiConfig.url}/patients/profile/photo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${ApiService.instance.currentToken}';
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
        contentType: MediaType('image', file.extension ?? 'jpeg'),
      ));
      final response = await request.send();
      if (response.statusCode == 200) {
        final body = await response.stream.bytesToString();
        final data = json.decode(body) as Map<String, dynamic>;
        final url = data['photo_url'] as String?;
        if (url != null) {
          await auth.updateProfilePhoto(url);
        }
        onPhotoChanged?.call();
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authPhoto = context.watch<AuthProvider>().currentUser?.profilePhoto;
    final resolvedUrl = photoUrl ?? authPhoto;
    final initial = (name?.isNotEmpty == true) ? name![0].toUpperCase() : '?';

    return GestureDetector(
      onTap: () => _uploadPhoto(context),
      child: Stack(
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: Theme.of(context).colorScheme.primary,
            backgroundImage: resolvedUrl != null ? NetworkImage('${ApiConfig.url}$resolvedUrl') : null,
            child: resolvedUrl == null
                ? Text(initial, style: TextStyle(fontSize: radius * 0.8, color: Colors.white, fontWeight: FontWeight.bold))
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
