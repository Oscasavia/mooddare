import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:mooddare/core/user_message.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/core/validation.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';

class EditProfileScreen extends StatefulWidget {
  final UserRepository? repository;
  final String? userId;
  const EditProfileScreen({super.key, this.repository, this.userId});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _username = TextEditingController(),
      _bio = TextEditingController();
  late final _repository = widget.repository ?? UserRepository();
  bool _loading = true, _loadFailed = false, _busy = false, _saving = false;
  String? _photo, _error;
  File? _image;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final uid = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Not signed in');
      final profile = await _repository.getUserModel(uid);
      if (profile == null) {
        throw const FormatException(
          'Could not find your profile. Please sign in again.',
        );
      }
      if (!mounted) return;
      _name.text = profile.name ?? '';
      _username.text = profile.username ?? '';
      _bio.text = profile.bio ?? '';
      _photo = profile.photoUrl;
    } catch (e) {
      if (mounted) {
        _loadFailed = true;
        _error = userMessage(e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 90,
      );
      if (file == null || !mounted) return;
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 800,
        maxHeight: 800,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
      );
      if (mounted && cropped != null) {
        setState(() => _image = File(cropped.path));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not open this photo. Please try another.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _loading || _loadFailed || !_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _saving = true;
      _error = null;
    });
    try {
      await _repository.saveProfile(
        username: _username.text,
        name: _name.text,
        bio: _bio.text,
        imageFile: _image,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              key: const ValueKey('profile_save'),
              onPressed: _loading || _loadFailed || _busy ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Saving profile',
                      ),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? AppEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load your profile',
              message: _error ?? 'Please try again.',
              actionLabel: 'Retry',
              onAction: _load,
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 48,
                        backgroundImage: _image != null
                            ? FileImage(_image!)
                            : _photo != null
                            ? NetworkImage(_photo!)
                            : null,
                        child: _image == null && _photo == null
                            ? const Icon(Icons.person_outline, size: 44)
                            : null,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _pick,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Change photo'),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _name,
                      enabled: !_busy,
                      maxLength: 50,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _username,
                      enabled: !_busy,
                      maxLength: 20,
                      validator: validateUsername,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixText: '@',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bio,
                      enabled: !_busy,
                      maxLength: 160,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'A little about you',
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    ),
  );
}
