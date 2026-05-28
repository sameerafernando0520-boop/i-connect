import 'dart:io';

void main() {
  final files = [
    'lib/screens/admin/admin_register_machine_page.dart',
    'lib/screens/admin/admin_settings_page.dart',
    'lib/screens/admin/tier_management_page.dart',
    'lib/screens/admin/referral_rules_page.dart',
    'lib/screens/admin/create_schedule_page.dart',
    'lib/screens/admin/broadcast_notifications.dart'
  ];

  for (final path in files) {
    var file = File(path);
    if (!file.existsSync()) continue;
    var content = file.readAsStringSync();
    if(content.contains('activeColor: ')) {
      content = content.replaceAll('activeColor: ', 'activeTrackColor: ');
      file.writeAsStringSync(content);
      print('Fixed activeColor in $path');
    }
  }
}
