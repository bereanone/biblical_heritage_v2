import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

module_spec = importlib.util.spec_from_file_location('cloud_restore', Path(__file__).resolve().parents[2] / 'tool/restore_cloud_data.py')
cloud_restore = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(cloud_restore)


class CloudDataRestoreTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'checkout'
        self.root.mkdir()
        self.archives = self.base / 'archives'
        self.archives.mkdir()
        self.content = b'approved narration and exact text\n'
        checksum = hashlib.sha256(self.content).hexdigest()
        archive = self.archives / 'part.zip'
        with zipfile.ZipFile(archive, 'w') as zipped:
            zipped.writestr('objects/' + checksum, self.content)
        self.manifest = {'schema': 1, 'files': [{'path': 'assets/example.bin', 'bytes': len(self.content), 'sha256': checksum, 'archive': 'part.zip', 'mode': 0o644}], 'archives': [{'name': 'part.zip', 'bytes': archive.stat().st_size, 'sha256': cloud_restore.digest(archive)}]}

    def test_restore_then_verify_and_repeat_preserve_bytes(self):
        self.assertEqual(cloud_restore.restore(self.manifest, self.root, self.archives), {'verified': 0, 'restored': 1})
        self.assertEqual((self.root / 'assets/example.bin').read_bytes(), self.content)
        self.assertEqual(cloud_restore.restore(self.manifest, self.root, None, True), {'verified': 1, 'restored': 0})
        self.assertEqual(cloud_restore.restore(self.manifest, self.root, None), {'verified': 1, 'restored': 0})

    def test_differing_local_content_is_never_overwritten(self):
        target = self.root / 'assets/example.bin'
        target.parent.mkdir()
        target.write_bytes(b'keep my local work')
        with self.assertRaisesRegex(ValueError, 'Existing files differ'):
            cloud_restore.restore(self.manifest, self.root, self.archives)
        self.assertEqual(target.read_bytes(), b'keep my local work')

    def test_corrupt_archive_is_rejected_before_writes(self):
        (self.archives / 'part.zip').write_bytes(b'broken')
        with self.assertRaisesRegex(ValueError, 'Archive checksum mismatch'):
            cloud_restore.restore(self.manifest, self.root, self.archives)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_manifest_cannot_escape_checkout(self):
        self.manifest['files'][0]['path'] = '../outside.bin'
        with self.assertRaisesRegex(ValueError, 'Unsafe data path'):
            cloud_restore.restore(self.manifest, self.root, self.archives)
        self.assertFalse((self.base / 'outside.bin').exists())

    def test_symlinked_destination_is_rejected(self):
        outside = self.base / 'elsewhere'
        outside.mkdir()
        (self.root / 'assets').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            cloud_restore.restore(self.manifest, self.root, self.archives)
        self.assertEqual(list(outside.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
