import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../utils/photo_url_utils.dart';

class ProfileAvatar extends StatefulWidget {
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

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  int? _cacheBust;
  bool _imageFailed = false;

  @override
  void didUpdateWidget(ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      _imageFailed = false;
    }
  }

  Future<void> _uploadPhoto() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;

    final file = result.files.first;
    final uploadName = PhotoUrlUtils.ensureUploadFilename(file.name, file.extension);
    final ext = file.extension?.toLowerCase() ?? 'jpeg';

    try {
      final uri = Uri.parse('${ApiConfig.url}/patients/profile/photo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${ApiService.instance.currentToken}';
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: uploadName,
        contentType: MediaType('image', ext == 'jpg' ? 'jpeg' : ext),
      ));
      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = json.decode(body) as Map<String, dynamic>;
        final url = data['photo_url'] as String?;
        if (url != null) {
          await auth.updateProfilePhoto(url);
          if (mounted) {
            setState(() {
              _cacheBust = DateTime.now().millisecondsSinceEpoch;
              _imageFailed = false;
            });
          }
          widget.onPhotoChanged?.call();
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('Photo updated'), backgroundColor: Color(0xFF388E3C)),
          );
        }
        return;
      }

      String message = 'Upload failed (${response.statusCode})';
      try {
        final error = json.decode(body);
        if (error is Map && error['detail'] != null) {
          message = error['detail'].toString();
        }
      } catch (_) {}
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: errorColor),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: errorColor),
      );
    }
  }

  String? _resolvedPath(String? authPhoto) {
    return PhotoUrlUtils.normalizePath(widget.photoUrl) ?? PhotoUrlUtils.normalizePath(authPhoto);
  }

  Widget _buildAvatarContent(String? path, String initial, ColorScheme colors) {
    if (path == null || _imageFailed) {
      return Text(
        initial,
        style: TextStyle(fontSize: widget.radius * 0.8, color: Colors.white, fontWeight: FontWeight.bold),
      );
    }

    return ClipOval(
      child: Image.network(
        PhotoUrlUtils.fullUrl(path, cacheBust: _cacheBust),
        width: widget.radius * 2,
        height: widget.radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_imageFailed) setState(() => _imageFailed = true);
          });
          return Text(
            initial,
            style: TextStyle(fontSize: widget.radius * 0.8, color: Colors.white, fontWeight: FontWeight.bold),
          );
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: SizedBox(
              width: widget.radius,
              height: widget.radius,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authPhoto = context.watch<AuthProvider>().currentUser?.profilePhoto;
    final path = _resolvedPath(authPhoto);
    final initial = (widget.name?.isNotEmpty == true) ? widget.name![0].toUpperCase() : '?';
    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _uploadPhoto,
      child: Stack(
        children: [
          CircleAvatar(
            radius: widget.radius,
            backgroundColor: colors.primary,
            child: _buildAvatarContent(path, initial, colors),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.primary,
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
