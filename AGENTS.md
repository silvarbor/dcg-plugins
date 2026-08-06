# AGENTS.md — dcg-plugins

Custom packs for [dcg](https://github.com/Dicklesworthstone/destructive_command_guard),
the Destructive Command Guard. `README.md` explains what the packs do and why;
this file is about working on them.

## This repo is where the packs actually live

The maintainer's dcg config at `~/.config/dcg` **symlinks** into this checkout:

```
~/.config/dcg/packs  ->  ~/Code/silvarbor/dcg-plugins/packs
~/.config/dcg/tests  ->  ~/Code/silvarbor/dcg-plugins/tests
~/.config/dcg/test   ->  ~/Code/silvarbor/dcg-plugins/test
```

Editing a pack here edits the live guard directly. There is no publish step and
no second copy to fall out of sync, which also means a bad edit takes effect
immediately — run the tests before you commit.

`example/config.toml` and `example/allowlist.toml` are the exception. They are
generated from the maintainer's real config with an explanatory header
prepended, so edits to them here are overwritten by `bin/publish-examples`
upstream. Everything else in this repo is authoritative.

## Why a dangling symlink is dangerous

A dcg `custom_paths` glob that matches nothing is a **silent, total loss of
protection**:

```
silvarbor packs listed : 0
warnings emitted       : 0        <- nothing on stdout or stderr
dcg doctor             : "Checking pattern packs... OK"

git worktree remove ../peer  ->  ALLOW
git stash drop               ->  ALLOW
git reflog expire --all      ->  ALLOW
```

dcg reports healthy while every rule has vanished. Moving or renaming this
checkout does exactly that to anyone symlinked into it, with no error anywhere.

The mitigation is a startup canary that asserts a known-destructive command
still DENYs — `bin/verify-guard.sh` in the config repo, wired into shell
startup, throttled to once an hour, stamping only on success so a broken guard
nags every new shell. If you adopt these packs by symlink, adopt that too.

## Testing

```sh
dcg corpus -d tests/corpus --baseline tests/baseline.json   # the official path
test/run.sh          # both suites (135 cases)
test/run.sh corpus   # corpus only
test/run.sh -v       # show every case
```

Two suites, because one tool cannot express both:

- **`tests/corpus/`** (92) runs under `dcg corpus`, dcg's own regression
  harness, in the upstream `true_positives` / `false_positives` /
  `bypass_attempts` taxonomy. Each case asserts a `rule_id`, so a command
  denied by the *wrong* rule is a failure, and `tests/baseline.json` turns
  regressions into a non-zero exit.
- **`test/cases/`** (43) runs against `dcg explain`. `dcg corpus` evaluates pack
  matching *without* applying `allowlist.toml` and has no `--config` flag, so
  neither the allowlist-dependent ALLOWs nor the shared_checkout pack can be
  expressed there.

That second point matters if you adopt these packs: **a corpus run alone will
not tell you the allowlist is installed**, and without it the git pack does not
behave as this repo documents.

`dcg pack validate` proves a pack parses, not that a rule still matches. Always
run the matrices. Verified against dcg 0.9.2.

CI runs both suites on every push and pull request. It pins the dcg version and
the release tarball's checksum in
`.github/workflows/deterministic-verification.yml`, because a newer dcg can
change a built-in pack's verdict with no change in this repo, and because
`tests/baseline.json` records the binary that produced it. Bump the version, the
checksum and the baseline together.

## Three things that will trip you up

**dcg hooks your own shell.** A command line containing `git worktree remove`
or a poll loop is blocked *for you*, including when testing the rule that
blocks it. That is why cases live in files and reach dcg through a variable.
`dcg test --stdin` exists for the same reason. Same for prose: in shell
`` `cmd` `` **is** command substitution, so a markdown code span containing a
guarded command is byte-identical to the real thing. Pass document bodies by
`<` redirect.

**dprint reformats on save.** `dprint.jsonc` excludes `**/*.toml` and
`packs/**/*.yaml` — the packs carry long *unquoted* regex scalars, and a
formatter that requoted or folded one would silently alter a security rule
while it still validated clean. Markdown is formatted and rewrites inline code
spans, so anything containing a backtick belongs in a fenced block.

These exclusions only apply when dprint resolves config per directory. A hook
passing an explicit `--config` bypasses that and reformats the excluded files
anyway — and `dprint check` still reports them out of scope while it happens,
so it is not a reliable signal. Prefer
`(cd "$(dirname "$FILE")" && dprint fmt "$FILE")`.

**A pack's `keywords` list is a pre-filter, not documentation.** dcg evaluates
it *before* any pattern, so a command containing none of the listed words never
reaches the pack at all. A correct regex over a missing keyword returns ALLOW
while the pack validates clean and loads clean, with no warning anywhere. Every
command name a pattern can match belongs in `keywords`. This cost
`silvarbor.access_boundary` two live ecosystems — `packs/readme.md` records
which ones and how they were caught.

## Pattern conventions

Every pattern, destructive and safe alike, anchors to a real command position
and walks intervening tokens with a bounded character class. Neither is
cosmetic — the reasoning, including the prose-matching bug and the fail-open
safe pattern that motivated them, is in `README.md` and `packs/readme.md`. A
new rule that does not follow both will be wrong in one of those two ways.
