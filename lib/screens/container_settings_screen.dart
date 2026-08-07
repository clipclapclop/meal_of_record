import 'package:flutter/material.dart';
import 'package:meal_of_record/models/food_container.dart';
import 'package:meal_of_record/services/database_service.dart';
import 'package:meal_of_record/widgets/container_edit_dialog.dart';
import 'package:meal_of_record/widgets/food_image_widget.dart';
import 'package:meal_of_record/widgets/screen_background.dart';

class ContainerSettingsScreen extends StatefulWidget {
  const ContainerSettingsScreen({super.key});

  @override
  State<ContainerSettingsScreen> createState() =>
      _ContainerSettingsScreenState();
}

class _ContainerSettingsScreenState extends State<ContainerSettingsScreen> {
  List<FoodContainer> _containers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContainers();
  }

  Future<void> _loadContainers() async {
    setState(() => _isLoading = true);
    final containers = await DatabaseService.instance.getAllContainers();
    if (mounted) {
      setState(() {
        _containers = containers;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleAdd() async {
    final result = await showDialog<FoodContainer>(
      context: context,
      builder: (context) => const ContainerEditDialog(),
    );

    if (result != null) {
      await DatabaseService.instance.saveContainer(result);
      _loadContainers();
    }
  }

  Future<void> _handleEdit(FoodContainer container) async {
    final result = await showDialog<FoodContainer>(
      context: context,
      builder: (context) => ContainerEditDialog(container: container),
    );

    if (result != null) {
      await DatabaseService.instance.saveContainer(result);
      _loadContainers();
    }
  }

  Future<void> _handleDelete(FoodContainer container) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Container?'),
        content: Text('Are you sure you want to delete "${container.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.deleteContainer(container.id);
      _loadContainers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Manage Containers'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _handleAdd,
          child: const Icon(Icons.add),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _containers.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 64,
                      color: Colors.white24,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No containers yet.\nAdd one to quickly subtract weights!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 60),
                itemCount: _containers.length,
                itemBuilder: (context, index) {
                  final container = _containers[index];
                  return Card(
                    color: Colors.white.withValues(alpha: 0.05),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: FoodImageWidget(
                            thumbnail: container.thumbnail,
                            size: 48,
                          ),
                        ),
                      ),
                      title: Text(container.name),
                      subtitle: Text(
                        '${container.weight.toStringAsFixed(0)} ${container.unit}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _handleEdit(container),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            color: Colors.red[300],
                            onPressed: () => _handleDelete(container),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
