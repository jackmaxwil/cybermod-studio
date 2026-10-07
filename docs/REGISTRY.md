# Mod registry index

A registry is one JSON file listing mods that `cybermod search` finds and `cybermod mod add registry:<id>` installs.
Point cybermod at it with `cybermod config set registry.url https://.../index.json` (`file://` works for testing:
`cybermod config set registry.url "file://$PWD/docs/registry.example.json"`). Example: [registry.example.json](registry.example.json).

```json
{
  "schema": 1,
  "mods": [
    {
      "id": "better-lights",
      "name": "Better Lights",
      "version": "1.2.0",
      "author": "Neon",
      "description": "Brighter street lights.",
      "source": "github:neon/better-lights@v1.2.0",
      "sha256": "…64 hex digits…",
      "requires": ["archivexl", "some-other-registry-id"]
    }
  ]
}
```

| Field | Required | Meaning |
|---|---|---|
| `schema` | yes | `1`. cybermod refuses other values ("update cybermod") |
| `id` | yes | Unique; lowercase letters, digits and dashes. Becomes the installed mod's id |
| `name` | yes | Display name |
| `version` | yes | Shown by `search`; `mod outdated` compares it with the installed version |
| `author`, `description` | no | Shown and searched |
| `source` | yes | `https://…` link to the file, `github:owner/repo[@tag]` or `nexus:<mod>[/<file>]` (never a local path) |
| `sha256` | for `https://` sources | SHA-256 of the downloaded file; a mismatch stops the install. Recommended for the others too |
| `requires` | no | Other registry ids (installed first when missing) or `red4ext`, `archivexl`, `tweakxl` (come with `cybermod install`; a warning says so when missing) |

Validation is all-or-nothing: an index with any invalid entry is rejected with the list of problems.
