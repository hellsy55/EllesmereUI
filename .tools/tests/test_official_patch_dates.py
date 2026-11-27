"""Exercise release-date resolution and transport diagnostics without network."""

import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import official_patch_dates as dates


class OfficialPatchDates(unittest.TestCase):
    def assert_error(self, code, call, *args):
        with self.assertRaises(dates.PatchError) as failure:
            call(*args)
        self.assertEqual(str(failure.exception), code)

    def test_discovery_preserves_query(self):
        url = dates.discover(
            "https://www.ellesmereui.com/archive/patch-notes",
            b'<script defer src="../data/patch-notes.js?v=new&amp;x=%2F"></script>',
        )
        self.assertEqual(url, "https://www.ellesmereui.com/data/patch-notes.js?v=new&x=%2F")

    def test_wrong_origin_and_missing_resource(self):
        for origin in ("http://ellesmereui.com", "https://ellesmereui.com.evil.test",
                       "https://user@ellesmereui.com", "https://ellesmereui.com:8443"):
            html = f'<script src="{origin}/data/patch-notes.js"></script>'.encode()
            self.assert_error("UNEXPECTED_ORIGIN", dates.discover, dates.PAGE, html)
        self.assert_error("DATA_RESOURCE_NOT_IDENTIFIABLE", dates.discover, dates.PAGE, b"<html>")

    def test_exact_version_and_calendar(self):
        rows = [{"version": "9.9.30", "date": "2026-11-30"},
                {"version": "9.9.3", "date": "2024-02-29"}]
        body = f"/* generated */ window.EUI_PATCHES = {json.dumps(rows)};".encode()
        self.assertEqual(dates.resolve_date(dates.parse_resource(body), "v9.9.3")["formatted"], "29/02/2024")
        self.assert_error("VERSION_NOT_FOUND", dates.resolve_date, rows, "9.9.31")
        self.assert_error("DUPLICATE_VERSION", dates.resolve_date, rows + [{"version": "v9.9.3"}], "9.9.3")

    def test_invalid_dates_and_payload(self):
        for value in ("2026-02-29", "2026-2-09", "2026-13-01", 123):
            self.assert_error("INVALID_DATE", dates.resolve_date, [{"version": "9.9.3", "date": value}], "9.9.3")
        self.assert_error("MISSING_DATE", dates.resolve_date, [{"version": "9.9.3"}], "9.9.3")
        self.assert_error("INVALID_JSON", dates.parse_resource, b'window.EUI_PATCHES = [{bad}];')
        self.assert_error("INVALID_JSON", dates.parse_resource, b'window.EUI_PATCHES = [{"version":"1.2","version":"1.3"}];')
        self.assert_error("UNEXPECTED_DATA_STRUCTURE", dates.parse_resource, b'window.other = [];')
        self.assert_error("UNEXPECTED_DATA_STRUCTURE", dates.parse_resource, b'window.EUI_PATCHES = [{}];')

    @patch("official_patch_dates.subprocess.run")
    def test_transport_failures(self, run):
        cases = [(56, "000\n403\n", "NETWORK_POLICY_BLOCK_OR_PROXY_DENIAL", 1),
                 (56, "000\n407\n", "CONNECT_FAILED", 1),
                 (6, "000\n000\n", "DNS", 2),
                 (60, "000\n200\n", "TLS", 1),
                 (28, "000\n000\n", "TIMEOUT", 2),
                 (0, "404\n200\n", "ORIGIN_HTTP", 1),
                 (0, "503\n200\n", "ORIGIN_HTTP", 2),
                 (0, "302\n000\nhttps://example.com/data", "INVALID_REDIRECT", 1)]
        for exit_code, output, error, attempts in cases:
            with self.subTest(error=error):
                run.reset_mock()
                run.return_value = subprocess.CompletedProcess([], exit_code, output, "secret")
                with self.assertRaises(dates.PatchError) as failure:
                    dates.download("curl", dates.PAGE, "data")
                self.assertEqual(str(failure.exception), error)
                self.assertEqual(failure.exception.details["stage"], "data")
                self.assertNotIn("secret", str(failure.exception.details))
                self.assertEqual(run.call_count, attempts)

    @patch("official_patch_dates.subprocess.run")
    def test_redirect_and_direct_connection(self, run):
        def respond(command, **kwargs):
            if command[-1] == dates.PAGE:
                return subprocess.CompletedProcess(command, 0, "301\n000\nhttps://www.ellesmereui.com/patch-notes", "")
            Path(command[command.index("--output") + 1]).write_bytes(b"direct")
            return subprocess.CompletedProcess(command, 0, "200\n000\n", "")
        run.side_effect = respond
        self.assertEqual(dates.download("curl", dates.PAGE, "page"),
                         ("https://www.ellesmereui.com/patch-notes", b"direct"))
        self.assertEqual(run.call_count, 2)


if __name__ == "__main__":
    unittest.main()
