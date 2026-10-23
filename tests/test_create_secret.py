"""bin/create-secret contracts, against a stubbed kubeseal; no cluster needed."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Stands in for kubeseal: hands out a cert, "seals" by echoing a fixed
# ciphertext, and validates per $KUBESEAL_VALIDATE.
KUBESEAL_STUB = """#!/bin/sh
case " $* " in
  *" --fetch-cert "*) echo fake-cert ;;
  *" --raw "*) cat >/dev/null; echo SEALED ;;
  *" --validate "*) cat >/dev/null; [ "$KUBESEAL_VALIDATE" = ok ] ;;
  *) exit 2 ;;
esac
"""


@unittest.skipUnless(all(shutil.which(b) for b in ("jsonnet", "jsonnetfmt", "jq")),
                     "needs jsonnet, jsonnetfmt and jq")
class CreateSecretTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        tmp = Path(self.tmp.name)
        # A copy of the repo's script and jsonnet, so the real secrets files are
        # never touched.
        self.repo = tmp / "repo"
        shutil.copytree(ROOT / "bin", self.repo / "bin")
        shutil.copytree(ROOT / "kubernetes/jsonnet", self.repo / "kubernetes/jsonnet")
        # The template ships without an owner, which won't render; a generated
        # repo always has one.
        config = self.repo / "kubernetes/jsonnet/common/config.libsonnet"
        config.write_text(config.read_text().replace("owner: ''", "owner: 'test.owner'", 1))
        # A generated repo's real secrets (from Homestead or create-secret) would
        # leak into the exact-list assertions, so each test starts from none.
        for env_dir in ("development", "production"):
            (self.repo / f"kubernetes/jsonnet/{env_dir}/secrets.libsonnet").write_text(
                '{ secrets: { sources: { sealedSecrets: { items: [] } } } }\n')
        stubs = tmp / "stubs"
        stubs.mkdir()
        (stubs / "kubeseal").write_text(KUBESEAL_STUB)
        (stubs / "kubeseal").chmod(0o755)
        # A fresh HOME keeps the stub's cert out of the real ~/.cache/frontier.
        # asdf's shims find their installs under HOME, so point them at the real one.
        self.env = {**os.environ, "HOME": str(tmp / "home"),
                    "ASDF_DATA_DIR": os.environ.get("ASDF_DATA_DIR", str(Path.home() / ".asdf")),
                    "PATH": f"{stubs}{os.pathsep}{os.environ['PATH']}"}

    def create(self, tier, validate="ok", overwrite=False):
        # tier, name, overwrite? (asked only if it exists), value file (none),
        # value, env var? (default yes), its name (default), mount as a file?
        # (default no)
        answers = f"{tier}\nmy-secret\n" + ("y\n" if overwrite else "") + "\nhunter2\n\n\n\n"
        return subprocess.run([str(self.repo / "bin/create-secret")], input=answers, text=True,
                              capture_output=True, env={**self.env, "KUBESEAL_VALIDATE": validate})

    def items(self, env_dir):
        out = subprocess.check_output(["jsonnet", f"{env_dir}/secrets.libsonnet"],
                                      cwd=self.repo / "kubernetes/jsonnet", text=True, env=self.env)
        return json.loads(out)["secrets"]["sources"]["sealedSecrets"]["items"]

    def test_valid_secret_is_written_in_each_environment(self):
        for tier, env_dir in (("d", "development"), ("p", "production")):
            with self.subTest(env=env_dir):
                result = self.create(tier)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.items(env_dir),
                                 [{"name": "my-secret", "ciphertext": "SEALED", "envVar": "MY_SECRET"}])
                self.assertFalse((self.repo / f"kubernetes/jsonnet/{env_dir}/secrets.libsonnet.bak").exists())

    def test_other_items_keep_their_homestead_metadata(self):
        secrets = self.repo / "kubernetes/jsonnet/development/secrets.libsonnet"
        meta = {"expiresAt": "2027-01-15", "updatedAt": "2026-10-14T19:02:11Z", "updatedBy": "ada@withpersona.com"}
        secrets.write_text(json.dumps({"secrets": {"sources": {"sealedSecrets": {"items": [
            {"name": "other", "ciphertext": "OLD", **meta},
            {"name": "my-secret", "ciphertext": "OLD", **meta},
        ]}}}}))
        result = self.create("d", overwrite=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.items("development"), [
            {"name": "other", "ciphertext": "OLD", **meta},
            # Re-sealed: its old expiry described the old value.
            {"name": "my-secret", "ciphertext": "SEALED", "envVar": "MY_SECRET"},
        ])

    def test_secret_the_controller_cannot_decrypt_is_not_written(self):
        result = self.create("d", validate="fail")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not decrypt", result.stderr)
        self.assertEqual(self.items("development"), [])


if __name__ == "__main__":
    unittest.main()
