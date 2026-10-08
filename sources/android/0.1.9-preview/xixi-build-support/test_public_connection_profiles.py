import pathlib
import unittest

from public_test_connection import history_profile_bytes, project_profile


class PublicConnectionProfileTests(unittest.TestCase):
    def setUp(self):
        self.profile = {
            "schemaVersion": 1,
            "idServer": "videopmt.com:24443",
            "relayServer": "videopmt.com:21117",
            "publicKey": "xeGt6mV0n19F0pGH81NoSJNOUKRWqmXmmwObSEzENEg=",
        }

    def test_reviewed_domain_projects_only_public_fields(self):
        self.assertEqual(project_profile(dict(self.profile, password="not-public")), self.profile)

    def test_unreviewed_hosts_ports_and_schema_types_are_rejected(self):
        for endpoint in ["other.example:24443", "sub.videopmt.com:24443", "Videopmt.com:24443",
                         "videopmt.com.:24443", "https://videopmt.com:24443", "videopmt.com:443"]:
            with self.assertRaises(RuntimeError):
                project_profile(dict(self.profile, idServer=endpoint))
        for version in [True, 1.0, "1"]:
            with self.assertRaises(RuntimeError):
                project_profile(dict(self.profile, schemaVersion=version))

    def test_fixed_previous_identities_remain_separate_from_runtime_default(self):
        project = pathlib.Path(__file__).resolve().parents[2]
        history = history_profile_bytes(project)
        self.assertIn(b"64.176.235.139:24443", history)
        self.assertIn(b"64.176.235.139:443", history)
        self.assertNotIn(b"videopmt.com", history)


if __name__ == "__main__":
    unittest.main()
