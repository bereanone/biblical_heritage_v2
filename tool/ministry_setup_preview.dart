import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:studybible2/features/entry/presentation/study_bible_about_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:studybible2/features/partners/data/ministry_enrollment_service.dart';
import 'package:studybible2/features/partners/data/ministry_profile.dart';
import 'package:studybible2/features/partners/presentation/ministry_enrollment_gate.dart';
import 'package:studybible2/features/partners/presentation/ministry_welcome_screen.dart';
import 'package:studybible2/features/utilities/presentation/utilities_screen.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/ministry_setup_test.json');
  final origin = File('${dir.path}/install_origin_test.json');
  final service = MinistryEnrollmentService(
    read: () async => await file.exists() ? file.readAsString() : null,
    write: (value) async {
      await file.writeAsString(value, flush: true);
    },
    seed:
        (_) async {}, // No library or hashtags are provisioned in this preview.
    loadInstallState: () async => await origin.exists()
        ? Map<String, Object?>.from(
            jsonDecode(await origin.readAsString()) as Map,
          )
        : <String, Object?>{},
    saveInstallState: (value) async {
      await origin.writeAsString(jsonEncode(value), flush: true);
    },
  );
  await service.captureInstallBeforeBootstrap();
  runApp(
    MaterialApp(
      title: 'StudyBible Ministry Test',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF805817),
      ),
      home: MinistryEnrollmentGate(
        service: service,
        child: PreviewWelcome(service),
      ),
    ),
  );
}

class PreviewWelcome extends StatelessWidget {
  const PreviewWelcome(this.service, {super.key});
  final MinistryEnrollmentService service;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<MinistryEnrollment?>(
    valueListenable: service.state,
    builder: (context, value, child) => MinistryWelcomeScreen(
      profile: value?.profile ?? MinistryProfile.biblicalHeritage,
      onExplore: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ministry setup test'),
          content: const Text(
            'Bible and library reading remain in your normal StudyBible app. This separate copy tests setup, branding, persistence and website links only.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
      onAbout: () => showStudyBibleAboutDialog(context),
      onUtilities: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UtilitiesScreen(
            themeMode: AppThemeMode.sepia,
            onThemeChanged: (_) {},
            enrollmentService: service,
          ),
        ),
      ),
    ),
  );
}
