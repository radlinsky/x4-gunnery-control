---
name: release
description: >
  Guides a full release of X4 Gunnery Control: reviews unreleased changes,
  proposes a version number, bumps CHANGELOG.md and content.xml, runs
  validation, commits, tags, and provides the exact terminal commands to
  publish on Nexus (via GitHub CI) and Steam Workshop.
---

# Release Agent

Walk every step of the release process in order. Stop and show the user what
you found or what you are about to do before any write or irreversible action.
Never skip the pre-flight gate; the camera gate is the hardest thing to re-test
after a tag is pushed.

---

## Step 1 — Read the current state

Read these two files and display the relevant sections to the user:

1. `CHANGELOG.md` — show the full `## [Unreleased]` section verbatim.
2. `content.xml` — show the current `version` attribute value and `date`.

Derive the current display version: divide the integer in `content.xml` by 100.
For example `version="20"` → `0.20`.

---

## Step 2 — Confirm pre-flight

Before touching any file, ask the user to confirm all of the following:

- `./scripts/validate.sh` passes clean on the current branch.
- The in-game **camera release gate** from `TESTING.md` has passed for the
  supported bridge matrix on this build.
- The branch to be released is merged to `main` (or the release commit is
  already on `main`).

Do not proceed until the user confirms. If they haven't run the gate, remind
them that a tag pushed without it cannot be undone cleanly.

---

## Step 3 — Propose the version number

Based on the `[Unreleased]` changes, suggest a version:

- **MINOR bump** (e.g. `0.20` → `0.21`) — the default for feature releases and
  bug-fix releases where the save format and API surface are compatible.
- **MAJOR bump** (e.g. `0.21` → `1.00`) — only when there is a deliberate,
  user-visible break in the save format, the public API, or the in-game
  behaviour contract.

Version format rules: `MAJOR.MINOR` where MINOR is always two digits (`0.21`,
`1.00`, `2.50`). The `content.xml` integer is `MAJOR * 100 + MINOR` — never
just a counter.

Show your reasoning and ask the user to confirm or override the version before
editing anything.

---

## Step 4 — Update the version files

Once the version (e.g. `0.21`) and today's date are confirmed, make these edits
**in a single operation**:

1. **`CHANGELOG.md`** — rename the top heading from  
   `## [Unreleased]`  
   to  
   `## [0.21] - 2026-08-07`  
   (substitute the confirmed version and today's ISO date).

2. **`content.xml`** — update the `version` integer and `date` attribute:
   - `version` = `MAJOR * 100 + MINOR` (e.g. `21` for `0.21`)
   - `date` = today's ISO date (e.g. `2026-08-07`)

After editing, read both files back and show the changed lines to the user.

---

## Step 5 — Review release notes

Read `release/RELEASE_NOTES.md` and ask the user:

> Does this release add features or change user-visible behaviour that aren't
> reflected here?

If yes, open the file so the user can edit it, then remind them to keep
`release/workshop-description.bbcode` in step (the Workshop description is
the same text in BBCode format; it's edited on the Workshop website, with the
in-repo file as the paste-ready copy).

If no changes are needed, move on.

---

## Step 6 — Run validation

Run the full validation suite:

```bash
./scripts/validate.sh
```

The last line must be `validation passed`. If it is not, show the failure and
stop. Do not commit a red tree.

---

## Step 7 — Commit the bump

Show the user the exact git diff and ask them to confirm before committing:

```bash
git diff
```

Then stage and commit only the version-bump files (and `release/RELEASE_NOTES.md`
if it was updated):

```bash
git add CHANGELOG.md content.xml
# add release/RELEASE_NOTES.md and release/workshop-description.bbcode if changed
git diff --cached
git commit -m "Release v0.21"
```

Substitute the confirmed version. Do not amend or force-push existing commits.

---

## Step 8 — Tag and push (triggers GitHub release + Nexus zip)

**This is irreversible once pushed.** Show the commands and ask for explicit
confirmation before running them:

```bash
git push origin main
git tag v0.21
git push origin v0.21
```

After the push, explain what happens automatically:

- `.github/workflows/release.yml` fires on the `v*` tag.
- It runs `validate.sh`, builds `dist/x4_gunnery_control-v0.21.zip`, and
  publishes it as a **GitHub release** with the body from
  `release/RELEASE_NOTES.md`.
- The Nexus upload is **manual**: once CI finishes, download the zip from the
  GitHub release page and upload it to the Nexus mod page.

Provide the direct link pattern:
`https://github.com/<owner>/x4-gunnery-control/releases/tag/v0.21`

---

## Step 9 — Steam Workshop release

The Workshop release requires:
- Running on Windows with Steam open and logged in.
- `WorkshopTool.exe` from **X Tools** (Steam app 282160) — not the `XTools_1.11.zip`
  in the repo root.
- The `ws_3778864325` Workshop item already exists (`release/workshop-id.txt`).

Provide the single command that stages and publishes in one step:

```bat
REM Run this from a Windows terminal (CMD or PowerShell) — Steam must be running
.\scripts\release-workshop.sh 0.21 "Describe what changed in this release"
```

Remind the user:
- Replace the changenote with a short plain-English summary of this release.
- The script aborts if WorkshopTool is not found; set `X4GC_WORKSHOPTOOL` to
  override the path, or `X4GC_DRY_RUN=1` to print the command without publishing.
- `WorkshopTool` does **not** update the title or long description; edit those
  on the Workshop website if needed. Keep `release/workshop-description.bbcode`
  in step as the paste-ready copy.

---

## Step 10 — Post-release checklist

After both platforms are live:

- [ ] GitHub release is published and the zip is attached.
- [ ] Nexus file uploaded and set as the main download.
- [ ] Steam Workshop item updated (check the page to confirm the new version
  appears in the mod's file info).
- [ ] `release/workshop-description.bbcode` reflects the current feature set if
  the description was updated on the website.
- [ ] Open a new `## [Unreleased]` section at the top of `CHANGELOG.md` on
  `main` so the next feature branch has somewhere to record changes.

```bash
# Add the empty unreleased heading after confirming the release is live
# Edit CHANGELOG.md manually or ask the agent to prepend the heading
```
