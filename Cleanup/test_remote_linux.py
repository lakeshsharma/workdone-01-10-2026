import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import remote_linux


class ProbeSafetyTests(unittest.TestCase):
    def test_embedded_command_protocol(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "workspace"
            root.mkdir()
            source = Path(remote_linux.__file__).read_bytes()
            code = 'import base64;exec(base64.b64decode("' + base64.b64encode(source).decode() + '"))'
            payload = base64.b64encode(json.dumps({"op": "browse", "root": str(root), "path": str(root)}).encode()).decode()
            result = subprocess.run([sys.executable, "-c", code, payload], capture_output=True, text=True, check=True)
            self.assertTrue(json.loads(result.stdout)["ok"])

    def test_browse_sizes_and_nested_selection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "workspace"
            nested = root / "job" / "build"
            nested.mkdir(parents=True)
            (nested / "data.bin").write_bytes(b"12345")
            listing = remote_linux.main({"op": "browse", "root": str(root), "path": str(root)})["listing"]
            self.assertEqual(listing["children"][0]["size"], 5)
            deeper = remote_linux.main({"op": "browse", "root": str(root), "path": str(root / "job")})["listing"]
            self.assertEqual(deeper["children"][0]["size"], 5)

    def test_refuses_root_escape_and_symlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "workspace"
            root.mkdir()
            outside = Path(temporary) / "outside"
            outside.mkdir()
            with self.assertRaises(ValueError):
                remote_linux.main({"op": "inspect", "root": str(root), "path": str(root)})
            with self.assertRaises(ValueError):
                remote_linux.main({"op": "inspect", "root": str(root), "path": str(outside)})
            try:
                (root / "link").symlink_to(outside, target_is_directory=True)
            except (OSError, NotImplementedError):
                self.skipTest("Symlink creation unavailable")
            with self.assertRaises(ValueError):
                remote_linux.main({"op": "inspect", "root": str(root), "path": str(root / "link")})

    def test_delete_requires_unchanged_snapshot(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "workspace"
            folder = root / "job"
            folder.mkdir(parents=True)
            (folder / "file").write_bytes(b"old")
            snapshot = remote_linux.main({"op": "inspect", "root": str(root), "path": str(folder)})["item"]
            (folder / "new").write_bytes(b"more")
            with self.assertRaises(ValueError):
                remote_linux.main({"op": "delete", "root": str(root), "path": str(folder), "expected": snapshot})
            self.assertTrue(folder.exists())
            current = remote_linux.main({"op": "inspect", "root": str(root), "path": str(folder)})["item"]
            remote_linux.main({"op": "delete", "root": str(root), "path": str(folder), "expected": current})
            self.assertFalse(folder.exists())

    def test_protected_descendant_blocks_parent_deletion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "workspace"
            folder = root / "job"
            protected = folder / "keep"
            protected.mkdir(parents=True)
            with self.assertRaises(ValueError):
                remote_linux.main({"op": "inspect", "root": str(root), "path": str(folder),
                                   "protected": [str(protected)]})


if __name__ == "__main__":
    unittest.main()
