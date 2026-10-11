import re

with open('lib/features/dashboard/owner/owner_menu_screen.dart', 'r') as f:
    content = f.read()

# Remove StreamSubscription? _settingsSub;
content = re.sub(r'StreamSubscription\?\s+_settingsSub;\n', '', content)
# Remove _settingsSub?.cancel();
content = re.sub(r'_settingsSub\?\.cancel\(\);\n', '', content)

# Remove _settingsSub listener block
content = re.sub(r'\s+_settingsSub = supabase[\s\S]*?_updateSettingsFromData[\s\S]*?\}\);\n', '', content)

# Remove Pricing & Settings variables
content = re.sub(r'// Pricing & Settings\s+double _baseDeliveryFee = 0;\s+double _pricePerGallon = 0;\s+double _riderCommissionPerGallon = 0;\n', '', content)

# Remove _updateSettingsFromData
content = re.sub(r'\s+void _updateSettingsFromData\([\s\S]*?\}\);\n  }\n', '\n', content)

# Remove _savePricingSettings
content = re.sub(r'\s+Future<void> _savePricingSettings\([\s\S]*?}\n\s+}\n', '\n', content)

# Remove _showEditPricing
content = re.sub(r'\s+void _showEditPricing\([\s\S]*?_savePricingSettings\(\);\n\s+if \(context\.mounted\) Navigator\.pop\(context\);\n\s+\}\),\n\s+\],\n\s+\),\n\s+\),\n\s+\);\n\s+\}\n', '\n', content)

# Remove from _loadAllData: settingsFuture and settings
content = re.sub(r'\s+final settingsFuture = supabase\s+\.from\(\'owner_settings\'\)\s+\.select\(\)\s+\.eq\(\'owner_id\', user\.id\)\s+\.maybeSingle\(\);\n', '', content)
content = re.sub(r'final results = await Future\.wait\(\[profileFuture, settingsFuture\]\);', 'final results = await Future.wait([profileFuture]);', content)
content = re.sub(r'final settings = results\[1\];\n', '', content)
content = re.sub(r'\s+if \(settings != null\) \{\n\s+_updateSettingsFromData\(settings\);\n\s+\}\n', '', content)

# In build method, replace _showEditPricing tap with navigation to OwnerSettingsScreen
replacement = '''onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const OwnerSettingsScreen()),
                                  );
                                },'''
content = re.sub(r'onTap: _showEditPricing,', replacement, content)

with open('lib/features/dashboard/owner/owner_menu_screen.dart', 'w') as f:
    f.write(content)
