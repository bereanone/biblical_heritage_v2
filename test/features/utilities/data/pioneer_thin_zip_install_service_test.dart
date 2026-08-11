import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/pioneer_thin_zip_install_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('thin zip downloads are restricted to github hosts over https', () {
    expect(
      PioneerThinZipInstallService.isTrustedDownloadUri(
        PioneerThinZipInstallService.thinZipUri,
      ),
      isTrue,
    );
    expect(
      PioneerThinZipInstallService.isTrustedDownloadUri(
        Uri.parse(
          'https://objects.githubusercontent.com/some/redirect/pioneerthin.zip',
        ),
      ),
      isTrue,
    );
    expect(
      PioneerThinZipInstallService.isTrustedDownloadUri(
        Uri.parse('http://github.com/bereanone/biblical_heritage_v2/x.zip'),
      ),
      isFalse,
    );
    expect(
      PioneerThinZipInstallService.isTrustedDownloadUri(
        Uri.parse('https://evil.example.com/pioneerthin.zip'),
      ),
      isFalse,
    );
  });
}
