"""Read official EllesmereUI patch dates without evaluating JavaScript."""

import argparse
from datetime import date, datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import urljoin, urlsplit

PAGE = "https://ellesmereui.com/patch-notes"
HOSTS = {"ellesmereui.com", "www.ellesmereui.com"}
VERSION = re.compile(r"v?([0-9]+(?:\.[0-9]+)+)")
REDIRECTS = {301, 302, 303, 307, 308}
TRANSIENT_HTTP = {408, 429, 500, 502, 503, 504}


class PatchError(Exception):
    def __init__(self, code, **details):
        self.details = {"error": code, **details}
        super().__init__(code)


def official_url(base, reference, error, **details):
    try:
        url = urljoin(base, reference)
        target = urlsplit(url)
        valid = (
            target.scheme == "https" and target.hostname in HOSTS
            and target.port in (None, 443) and target.username is None
            and not target.fragment and "\\" not in reference
            and not any(ord(char) <= 32 or ord(char) == 127 for char in reference)
        )
    except ValueError:
        valid = False
    if not valid:
        raise PatchError(error, **details)
    return url


def download(curl, url, stage):
    with tempfile.TemporaryDirectory() as directory:
        body = Path(directory) / "body"
        for hop in range(6):
            for attempt in range(2):
                command = [
                    curl, "-q", "--silent", "--proto", "=https", "--globoff",
                    "--connect-timeout", "8", "--max-time", "20",
                    "--max-filesize", "16777216", "--output", str(body),
                    "--write-out", "%{http_code}\n%{http_connect}\n%{redirect_url}",
                    "--url", url,
                ]
                try:
                    result = subprocess.run(
                        command, capture_output=True, text=True, encoding="utf-8",
                        errors="replace", timeout=25, check=False,
                    )
                except subprocess.TimeoutExpired:
                    if attempt == 0:
                        continue
                    raise PatchError("TIMEOUT", stage=stage) from None
                except OSError:
                    raise PatchError("CURL_UNAVAILABLE", stage=stage) from None
                fields = result.stdout.split("\n", 2)
                http, connect = [int(x) if x.isdecimal() else 0 for x in (fields + ["", ""])[:2]]
                details = dict(stage=stage, http=http, connect=connect, curl_exit=result.returncode)
                if connect and connect != 200:
                    if attempt == 0 and connect in TRANSIENT_HTTP:
                        continue
                    code = "NETWORK_POLICY_BLOCK_OR_PROXY_DENIAL" if connect == 403 else "CONNECT_FAILED"
                    raise PatchError(code, **details)
                if result.returncode:
                    code = {
                        5: "DNS", 6: "DNS", 28: "TIMEOUT", 35: "TLS",
                        51: "TLS", 53: "TLS", 54: "TLS", 58: "TLS", 59: "TLS",
                        60: "TLS", 66: "TLS", 77: "TLS", 83: "TLS", 90: "TLS", 91: "TLS",
                    }.get(result.returncode, "TRANSPORT_ERROR")
                    if attempt == 0 and result.returncode in {5, 6, 7, 18, 28, 52, 55, 56, 92}:
                        continue
                    raise PatchError(code, **details)
                if attempt == 0 and http in TRANSIENT_HTTP:
                    continue
                break
            if 200 <= http < 300 and body.is_file():
                return url, body.read_bytes()
            if not 300 <= http < 400:
                raise PatchError("ORIGIN_HTTP", **details)
            location = fields[2] if len(fields) == 3 else ""
            if hop == 5 or http not in REDIRECTS or not location:
                raise PatchError("INVALID_REDIRECT", **details)
            url = official_url(url, location, "INVALID_REDIRECT", **details)


class DataScripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.sources = []

    def handle_starttag(self, tag, attrs):
        if tag == "script":
            for key, value in attrs:
                if key == "src" and value and re.search(r"(?:^|/)data/patch-notes\.js(?:[?#]|$)", value):
                    self.sources.append(value)


def discover(page, html):
    parser = DataScripts()
    parser.feed(html.decode("utf-8", errors="replace"))
    if len(parser.sources) != 1:
        raise PatchError("DATA_RESOURCE_NOT_IDENTIFIABLE", stage="page")
    return official_url(page, parser.sources[0], "UNEXPECTED_ORIGIN", stage="page")


def reject_json_constant(value):
    raise ValueError(value)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON key")
        result[key] = value
    return result


def parse_resource(body):
    try:
        text = body.decode("utf-8-sig")
    except UnicodeError:
        raise PatchError("INVALID_JSON", stage="data") from None
    wrapper = re.fullmatch(
        r"\s*(?:/\*.*?\*/\s*)?window\.EUI_PATCHES\s*=\s*(.*?)\s*;\s*", text, re.S,
    )
    if not wrapper or not wrapper[1].startswith("["):
        raise PatchError("UNEXPECTED_DATA_STRUCTURE", stage="data")
    try:
        rows = json.loads(wrapper[1], parse_constant=reject_json_constant, object_pairs_hook=unique_object)
    except (ValueError, RecursionError):
        raise PatchError("INVALID_JSON", stage="data") from None
    if not rows or any(
        not isinstance(row, dict) or not isinstance(row.get("version"), str)
        or not VERSION.fullmatch(row["version"]) for row in rows
    ):
        raise PatchError("UNEXPECTED_DATA_STRUCTURE", stage="data")
    return rows


def version_key(version):
    match = VERSION.fullmatch(version)
    if not match:
        raise PatchError("INVALID_VERSION")
    return match[1]


def resolve_date(rows, version):
    key = version_key(version)
    matches = [row for row in rows if version_key(row["version"]) == key]
    if len(matches) != 1:
        raise PatchError("DUPLICATE_VERSION" if matches else "VERSION_NOT_FOUND")
    iso = matches[0].get("date")
    if iso is None or iso == "":
        raise PatchError("MISSING_DATE")
    if not isinstance(iso, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", iso):
        raise PatchError("INVALID_DATE")
    try:
        day = date.fromisoformat(iso)
    except ValueError:
        raise PatchError("INVALID_DATE") from None
    return {"version": key, "iso": iso, "formatted": f"{day.day:02d}/{day.month:02d}/{day.year:04d}"}


def collect(curl):
    page, html = download(curl, PAGE, "page")
    source = discover(page, html)
    data_url, body = download(curl, source, "data")
    return parse_resource(body), {
        "page_url": PAGE,
        "final_page_url": page,
        "data_url": data_url,
        "method": "official_data_json",
        "queried_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "sha256": hashlib.sha256(body).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("versions", nargs="*", help="Exact release versions, optionally prefixed with v")
    parser.add_argument("--latest", type=int, default=0, help="Also check this many records in site order")
    args = parser.parse_args()
    if not args.versions and args.latest <= 0:
        parser.error("supply versions or a positive --latest count")
    try:
        curl = shutil.which("curl.exe") or shutil.which("curl")
        if not curl:
            raise PatchError("CURL_UNAVAILABLE")
        rows, evidence = collect(curl)
    except PatchError as exc:
        print(json.dumps({"status": "FAIL", **exc.details}))
        return 1
    results = []
    latest = [row["version"] for row in rows[:max(0, args.latest)]]
    versions = dict.fromkeys(
        version[1:] if VERSION.fullmatch(version) and version.startswith("v") else version
        for version in latest + args.versions
    )
    for version in versions:
        try:
            results.append({"status": "PASS", **resolve_date(rows, version)})
        except PatchError as exc:
            results.append({"status": "FAIL", "version": version, **exc.details})
    success = all(row["status"] == "PASS" for row in results)
    print(json.dumps({"status": "PASS" if success else "FAIL", **evidence, "dates": results}))
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
