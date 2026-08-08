import 'dart:io';
import 'package:flutter/material.dart';
import 'package:meal_of_record/models/food_container.dart';
import 'package:meal_of_record/services/image_storage_service.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meal_of_record/screens/square_camera_screen.dart';

class ContainerEditDialog extends StatefulWidget {
  final FoodContainer? container;

  const ContainerEditDialog({super.key, this.container});

  @override
  State<ContainerEditDialog> createState() => _ContainerEditDialogState();
}

class _ContainerEditDialogState extends State<ContainerEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _weightController;
  String? _thumbnail;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.container?.name ?? '');
    _weightController = TextEditingController(
      text: widget.container?.weight.toString() ?? '',
    );
    _thumbnail = widget.container?.thumbnail;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Image'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (_thumbnail != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Image'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'remove') {
      // Note: we don't delete the file immediately in case user cancels dialog.
      // Garbage collection handles unused images eventually, or we could handle it better.
      // For now, just clearing reference.
      setState(() {
        _thumbnail = null;
      });
      return;
    }

    if (!mounted) return;

    final String? pickedPath;
    if (choice == 'camera') {
      pickedPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const SquareCameraScreen()),
      );
    } else {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      pickedPath = pickedFile?.path;
    }

    if (pickedPath == null) return;

    try {
      final guid = await ImageStorageService.instance.saveImage(
        File(pickedPath),
      );
      setState(() {
        _thumbnail = '${ImageStorageService.localPrefix}$guid';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving image: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.container == null ? 'Add Container' : 'Edit Container',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[600]!),
                  ),
                  child: _thumbnail != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: FoodImageWidget(
                            thumbnail: _thumbnail,
                            size: 100,
                          ),
                        )
                      : const Icon(Icons.add_a_photo, size: 40),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Container Name',
                  hintText: 'e.g. Blue Bowl',
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _weightController,
                decoration: const InputDecoration(
                  labelText: 'Weight (g)',
                  hintText: 'e.g. 50',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Required';
                  if (double.tryParse(val) == null) return 'Invalid number';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final newContainer = FoodContainer(
                id: widget.container?.id ?? 0,
                name: _nameController.text.trim(),
                weight: double.parse(_weightController.text),
                unit: 'g',
                thumbnail: _thumbnail,
              );
              Navigator.pop(context, newContainer);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
