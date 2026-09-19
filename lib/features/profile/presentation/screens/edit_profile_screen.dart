import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:mooddare/core/user_message.dart';
import 'package:mooddare/core/validation.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _username = TextEditingController(),
      _bio = TextEditingController();
  bool _loading = true, _busy = false;
  String? _photo, _error;
  File? _image;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Not signed in');
      final doc = await UserRepository().getUser(uid);
      if (!mounted) return;
      final data = doc.data() ?? {};
      _name.text = data['name'] as String? ?? '';
      _username.text = data['username'] as String? ?? '';
      _bio.text = data['bio'] as String? ?? '';
      _photo = data['photoUrl'] as String?;
    } catch (e) {
      if (mounted) _error = userMessage(e);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await UserRepository().saveProfile(
        username: _username.text,
        name: _name.text,
        bio: _bio.text,
        imageFile: _image,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
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
      appBar: AppBar(title: const Text('Edit profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? 'Saving…' : 'Save changes'),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}
