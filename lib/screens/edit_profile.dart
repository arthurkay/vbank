import 'package:brick_core/query.dart';
import 'package:flutter/material.dart';

// --- MOCK CLASSES FOR RUNNABILITY (Must match profile_content.dart) ---
// Mocking the Profile model structure
class Profile {
  final String? id;
  final String? fullName;
  final bool isAdmin;
  Profile({this.id, this.fullName, this.isAdmin = false});
}

// Mocking the Repository for data persistence
class Repository {
  // Static variable to simulate a database cache
  static Profile? _cachedProfile = Profile(
    id: 'user_id_123',
    fullName: 'John Doe',
    isAdmin: true,
  );

  // Simulates fetching the user profile
  Future<List<T>> get<T>({Query? query}) async {
    if (T == Profile) {
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));
      return [_cachedProfile!] as List<T>;
    }
    return [];
  }

  // Simulates updating the user profile
  Future<T> upsert<T>(T model) async {
    if (T == Profile) {
      // Update the mock cache
      _cachedProfile = model as Profile;
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 700));
      return model;
    }
    throw Exception('Unsupported model type for upsert');
  }
}

// Mocking theme colors
const Color growthAccent = Color(0xFF4CAF50);
const Color darkText = Colors.black;

// ------------------------------------------------------------------------

class EditProfileScreen extends StatefulWidget {
  final Profile currentProfile;
  // This callback is used to tell the parent screen to reload its data after a successful save.
  final Function() onProfileUpdated;

  const EditProfileScreen({
    required this.currentProfile,
    required this.onProfileUpdated,
    super.key,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fullNameController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.currentProfile.fullName,
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (mounted) {
      setState(() {
        _isSaving = true;
      });
    }

    try {
      final newName = _fullNameController.text.trim();

      // Create an updated Profile object
      final updatedProfile = Profile(
        id: widget.currentProfile.id,
        fullName: newName,
        isAdmin: widget.currentProfile.isAdmin,
      );

      // Save the updated profile using the Repository
      await Repository().upsert<Profile>(updatedProfile);

      // Notify the parent screen (ProfileContent) to refresh its data
      widget.onProfileUpdated();

      if (mounted) {
        // Show success and navigate back
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile updated to $newName!'),
            backgroundColor: growthAccent,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Full Name Field (Editable)
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  hintText: 'Enter your full name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name cannot be empty';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // User ID Field (Read-Only)
              TextFormField(
                initialValue: widget.currentProfile.id,
                readOnly: true,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                decoration: const InputDecoration(
                  labelText: 'User ID (Not Editable)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),

              // You can add more fields here like 'Phone Number' or 'Group Role'
              const SizedBox(height: 40),

              // Save Button
              ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: growthAccent,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: darkText,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: darkText,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
