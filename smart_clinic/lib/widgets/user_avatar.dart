import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../utils/photo_url_utils.dart';

class UserAvatar extends StatefulWidget {
  final String? name;
  final String? photoUrl;
  final double radius;
  final bool loadFromApi;

  const UserAvatar({
    super.key,
    this.name,
    this.photoUrl,
    this.radius = 28,
    this.loadFromApi = true,
  });

  @override
  State<UserAvatar> createState() => UserAvatarState();
}

class UserAvatarState extends State<UserAvatar> {
  String? _photoUrl;
  bool _imageFailed = false;

  @override
  void initState() {
    super.initState();
    _photoUrl = PhotoUrlUtils.normalizePath(widget.photoUrl);
    if (widget.loadFromApi) _loadPhoto();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.photoUrl != oldWidget.photoUrl) {
      _photoUrl = PhotoUrlUtils.normalizePath(widget.photoUrl);
      _imageFailed = false;
    }
  }

  Future<void> refresh() => _loadPhoto();

  Future<void> _loadPhoto() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final response = await ApiService.instance.get('/patients/profile');
      if (mounted && response['photo_url'] != null) {
        final url = response['photo_url'] as String;
        setState(() {
          _photoUrl = url;
          _imageFailed = false;
        });
        await auth.updateProfilePhoto(url);
      }
    } catch (_) {}
  }

  String? _resolvedPath(String? authPhoto) {
    return PhotoUrlUtils.normalizePath(_photoUrl) ??
        PhotoUrlUtils.normalizePath(authPhoto) ??
        PhotoUrlUtils.normalizePath(widget.photoUrl);
  }

  @override
  Widget build(BuildContext context) {
    final authPhoto = context.watch<AuthProvider>().currentUser?.profilePhoto;
    final path = widget.loadFromApi ? _resolvedPath(authPhoto) : PhotoUrlUtils.normalizePath(widget.photoUrl ?? _photoUrl);
    final initial = (widget.name?.isNotEmpty == true) ? widget.name![0].toUpperCase() : '?';
    final colors = Theme.of(context).colorScheme;

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: colors.primary,
      child: path == null || _imageFailed
          ? Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.radius * 0.78,
                fontWeight: FontWeight.bold,
              ),
            )
          : ClipOval(
              child: Image.network(
                PhotoUrlUtils.fullUrl(path),
                width: widget.radius * 2,
                height: widget.radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_imageFailed) setState(() => _imageFailed = true);
                  });
                  return Text(
                    initial,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.radius * 0.78,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ),
    );
  }
}
