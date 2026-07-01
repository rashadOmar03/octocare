import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.photoUrl;
    if (widget.loadFromApi) _loadPhoto();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.photoUrl != oldWidget.photoUrl) {
      _photoUrl = widget.photoUrl;
    }
  }

  Future<void> refresh() => _loadPhoto();

  Future<void> _loadPhoto() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final role = auth.userRole;
      if (role != 'patient') {
        final photo = auth.currentUser?.profilePhoto;
        if (photo != null && mounted) {
          setState(() => _photoUrl = photo);
        }
        return;
      }
      final response = await ApiService.instance.get('/patients/profile');
      if (mounted && response['photo_url'] != null) {
        final url = response['photo_url'] as String;
        setState(() => _photoUrl = url);
        await auth.updateProfilePhoto(url);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final String? resolvedUrl;
    if (widget.loadFromApi) {
      final authPhoto = context.watch<AuthProvider>().currentUser?.profilePhoto;
      resolvedUrl = _photoUrl ?? authPhoto ?? widget.photoUrl;
    } else {
      resolvedUrl = widget.photoUrl ?? _photoUrl;
    }
    final initial = (widget.name?.isNotEmpty == true) ? widget.name![0].toUpperCase() : '?';

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: Theme.of(context).colorScheme.primary,
      backgroundImage: resolvedUrl != null ? NetworkImage('${ApiConfig.url}$resolvedUrl') : null,
      child: resolvedUrl == null
          ? Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.radius * 0.78,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }
}
