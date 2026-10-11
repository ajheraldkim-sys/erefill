import 'dart:io';

void main() {
  final file = File(
    'lib/features/onboarding/screens/welcome_onboarding_screen.dart',
  );
  var content = file.readAsStringSync();

  // Remove the bad AnnotatedRegion wrap if it exists
  content = content.replaceAll(
    'return const AnnotatedRegion<SystemUiOverlayStyle>(\n      value: SystemUiOverlayStyle.light,\n      child: Scaffold(',
    'return Scaffold(',
  );
  // Remove the extra closing parenthesis
  content = content.replaceAll('    ));\n  }\n}', '    );\n  }\n}');

  // Apply correctly
  content = content.replaceFirst(
    'return Scaffold(',
    'return AnnotatedRegion<SystemUiOverlayStyle>(\n      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),\n      child: Scaffold(',
  );

  content = content.replaceFirst('    );\n  }\n}', '    ));\n  }\n}');

  if (!content.contains("import 'package:flutter/services.dart';")) {
    content = "import 'package:flutter/services.dart';\n$content";
  }

  file.writeAsStringSync(content);
}
