import base64
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

script = Path(__file__).resolve().parents[1] / 'generate_apple_billing_config.py'
spec = importlib.util.spec_from_file_location('billing_config', script)
billing_config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(billing_config)


def encode(*values):
    return ','.join(base64.b64encode(v.encode()).decode() for v in values)


class BillingConfigTests(unittest.TestCase):
    def test_dart_flag_parity(self):
        for value in ['true', 'false', '', 'TRUE', '1']:
            with self.subTest(value=value):
                self.assertEqual(billing_config.billing_enabled(encode(
                    'STUDYBIBLE_APPLE_BILLING=' + value)), value == 'true')
        self.assertFalse(billing_config.billing_enabled(''))

    def test_malformed_build_input_fails_instead_of_disabling_billing(self):
        with self.assertRaises(Exception):
            billing_config.billing_enabled('not*base64')

    def test_bundle_contains_only_the_billing_switch(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'Runner.app' / 'StudyBibleBilling.plist'
            billing_config.generate(output, encode('OTHER_SETTING=private',
                'STUDYBIBLE_APPLE_BILLING=true'))
            self.assertEqual(plistlib.loads(output.read_bytes()), {'enabled': True})


if __name__ == '__main__':
    unittest.main()
