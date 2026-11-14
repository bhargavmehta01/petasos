# Home panels

Home shows small glanceable **panels** that your agents, skills and cron jobs
publish. It is the same convention as the Hermes Home dashboard plugin
(`home-dashboard` 1.6+): one JSON file per panel at

```
$HERMES_HOME/panels/<id>.json            (default ~/.hermes/panels/)
$HERMES_HOME/profiles/<name>/panels/<id>.json
```

The phone cannot read the host's files, and Petasos will **never** ask the
agent for panels through a hidden chat. Panels reach the phone over HTTP from
one of these sources (Profile → Home panels):

1. **Custom URL** (wins if set). Any URL that returns panel JSON, with an
   optional Bearer token. Accepted bodies: `{"panels":[…]}`, `{"data":[…]}`,
   or a bare JSON list.
2. **Hermes dashboard**: `GET <dashboard>/api/plugins/home-dashboard/panels`,
   using the dashboard login saved on the connection. Needs the
   `home-dashboard` plugin installed on the dashboard.

With neither set, Home shows a short explainer and a "Set up panels" button.

## Panel JSON

Unknown keys are ignored. Invalid panels are skipped, never fatal.

| key | type | notes |
|---|---|---|
| `id` | string | required. `[a-z0-9][a-z0-9._-]{0,63}`, equal to the file name |
| `title` | string | required, ≤ 80 chars |
| `kind` | `stat` \| `list` \| `table` \| `text` \| `progress` | required. `progress` is a Petasos addition |
| `subtitle` | string | one line under the title |
| `updated_at` | ISO 8601 (or epoch seconds/ms) | drives "updated X ago" |
| `value` | number \| string | the big number for `stat`; 0–1 or 0–100 for `progress` |
| `unit` | string | shown after `value` |
| `trend` | string \| number | e.g. `"+1.37 today"`. Leading `+` is green, `-` is red. Alias: `delta` (dashboard v1) |
| `items` | `[{label, value?, url?}]` | for `list`, ≤ 50 |
| `columns`, `rows` | `string[]`, `(string\|number\|null)[][]` | for `table`, ≤ 8 × 50 (Home shows 6 rows) |
| `text` | string | for `text`, newlines kept |
| `progress` | number | optional explicit 0–1 (or 0–100) for `progress` |
| `url` | http(s) URL | tapping the panel opens it. Alias: `link` (dashboard v1) |
| `source` | string | shown in the footer |
| `profile` | string | shown in the footer (the dashboard fills this) |
| `stale_after_minutes` | number | after this the panel dims and says *stale* |

Only `http(s)` links are kept. Keep panels to things you are fine seeing on a
lock-screen-adjacent surface: no secrets, keys, account numbers or medical data.

### Examples

```json
{"id":"daily-cost","title":"API spend · month","kind":"stat","value":18.42,
 "unit":"USD","trend":"+1.37 today","updated_at":"2026-11-03T13:15:00Z",
 "source":"costs.py","stale_after_minutes":1560}
```

```json
{"id":"backup","title":"Backups","kind":"progress","value":100,
 "subtitle":"B2 offsite copy OK","updated_at":"2026-11-03T08:00:00Z"}
```

```json
{"id":"model-router","title":"Model router tiers","kind":"list",
 "items":[{"label":"OpenRouter flex","value":"on"},{"label":"Last canary","value":"pass"}],
 "updated_at":"2026-11-03T14:07:00Z"}
```

Write files atomically (temp file in the same folder, then `mv`) so a reader
never sees half a file.

## Exposing panels without the dashboard plugin

Any static server on your tailnet works for the Custom URL. For example, a tiny
cron that merges the folder into one file and serves it with Tailscale:

```bash
jq -s '{panels: .}' ~/.hermes/panels/*.json > ~/.hermes/panels-index.json
tailscale serve --bg --set-path /panels.json ~/.hermes/panels-index.json
```

Then set the Custom URL to `https://<host>.<tailnet>.ts.net/panels.json`.

Code: `lib/hermes_mobile/data/panels.dart` (model + sources) and `PanelsGrid` in
`lib/hermes_mobile/screens/home_screen.dart`. Tests: `test/hermes_mobile/hermes_mobile_panels_test.dart`.
