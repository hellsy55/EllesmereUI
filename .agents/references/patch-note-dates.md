# Official Patch Notes release dates

## Preflight before integration

After freezing the upstream release, compare the exact What's New versions in
the planned Retail inputs and destination, including any pending origin
fast-forward. Read `EllesmereUI._WHATSNEW_PATCHES` in
`EllesmereUIOptions/EUI__General_Options.lua`. Identify all expected new versions
from the planned Git delta, including Latest. Keep the pre-integration version
and date snapshot. Skip the network on no-ops and changes without new versions.
Retain the existing historical restoration and Lua runtime preflight.

For new versions run one batched lookup before branch mutation, using the frozen
runtime from the maintenance context. Pass each exact version as its own argument.

```text
<python_runtime> -B .tools/official_patch_dates.py <version> [<version> ...]
```

The helper uses the existing curl executable (including curl.exe on Windows),
the system trust configuration and inherited proxy policy. It parses the official
HTML, discovers the Patch Notes data script, resolves its src against the final
page URL, preserves the query string and validates HTTPS and the official hosts
before every request. It decodes the JSON array assigned to window.EUI_PATCHES
without executing it. Only a leading display v is optional in version matching.
It validates calendar dates and returns both ISO and DD/MM/YYYY. Reuse successful
results within the current update. Confirm the actual integrated version set
after integration and any approved conflict resolution. Look up any unexpected
new version before editing dates or proceeding to validation and publication.

Use the structured error, stage, and available curl exit, CONNECT and origin codes
for diagnosis. A zero CONNECT means no CONNECT status was received, which is
normal on a successful direct connection. CONNECT 403 is a proxy denial, with
allowlist attribution requiring policy evidence. Distinguish page and data
failures, redirects, DNS, TLS, timeout, origin HTTP, discovery, payload structure,
JSON and per-version failures. The helper bounds redirects and retries transient
failures once per request. Keep credentials, cookies, headers and raw proxy output
out of the report. Ignore blocked accessory traffic when the needed data is valid.
The Cloudflare Insights beacon requires no grant for this procedure.

## Browser fallback and application

On a failed official lookup, use an allowed, already available browser. Navigate
to the official page with normal TLS and network policy, set or verify en-US for
deterministic parsing, and wait for populated release entries. Read each
`#pnList .pn-head` pair from its own `.pn-ver` and `time`. Use Show older releases
as needed until the exact versions appear or the list ends. If the layout changes,
inspect the DOM and accept only an unambiguous version and date in the same
release entry. Record the browser locale and exact displayed text. Parse en-US
English month names explicitly and validate the calendar date without a time-zone
conversion. Refuse ambiguous entries, unexpected locale or unrecognized formats.

Apply validated dates to new versions only. Verify supplied incoming dates
against the evidence first. Restore established historical dates if integration
drops or alters them. Leave other historical entries untouched. When neither
official method verifies a date, pause before mutation if known at preflight,
or before editing, commit or publication if discovered later. Preserve the
option to wait or explicitly proceed undated. Any proposed fallback date requires
express authorization covering the version, value, source and destinations.
Record the decision and label the value as an authorized fallback. Never infer
a date from Git, tags, GitHub Releases, CurseForge, downloads, file timestamps,
cache, neighboring entries or the current date.

Verify exact version/date association and idempotence. Run applicable Lua
guardrails and the locale key check before staged review. Sync B validates the
same Retail mapping by version in PTR and preserves PTR customizations. It does
not resolve dates independently. A full historical audit is diagnostic only.
For an authorized historical correction, verify both frozen destination trees
and the official entry, using the same source and date validation rules.

## Required update footer

Always include this footer in the final update report, including no-ops and
blocked updates. Use PASS, FAIL, PARTIAL, NOT APPLICABLE, NOT ATTEMPTED or
NOT VERIFIED where applicable. Include a per-version table for multiple new
versions. For every version record its frozen upstream SHA, official page URL,
final data URL if available, method, UTC lookup time, SHA-256 if available,
validation result, official ISO date, applied DD/MM/YYYY, provenance and
applicable destinations. For authorized fallback record the proposed date,
source, versions, destinations and authorization decision. Do not persist raw
notes in the repository. Retain the existing Token Savings report.

### Patch Notes — Official Release Dates

- Network preflight:
- Official website:
- Official data resource:
- Extraction method:
- Upstream version:
- Upstream SHA:
- Official release date:
- Applied release date:
- Date provenance:
- Retail validation:
- PTR validation:
- Fallback used:
- Fallback authorization:
- Additional network domains required:

Maintain this reference, the helper, its tests and eui-update together on
new-features and propagate through the normal approved Sync B. Local and Cloud
consume these files from a verified fork checkout containing them.
