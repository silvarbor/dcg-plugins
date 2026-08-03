# AGENTS.md — dcg-plugins

Custom packs for [dcg](https://github.com/Dicklesworthstone/destructive_command_guard),
the Destructive Command Guard. `README.md` explains what the packs do and why;
this file is about working on them.

## Read this before editing anything

**This repository is a published copy, not the source of truth.**

The packs are authored in the maintainer's dcg config repo (`~/.config/dcg`)
and copied here by `bin/publish-packs` there. Everything under `packs/`,
`example/`, `test/`, and `tests/` is overwritten wholesale on the next publish.

An edit made here is not merely unshared — it is *silently reverted* on the
next publish, and because a pack that stops matching still validates clean, the
loss can go unnoticed. Open an issue or a PR and expect it to be applied
upstream first.

Files that live here and are never overwritten: `README.md`, `AGENTS.md`,
`CLAUDE.md`, `LICENSE`, `NOTICE`, `.gitignore`, `dprint.jsonc`.

## Why the copy goes this direction

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

dcg reports healthy while every cross-boundary rule has vanished. A live config
must therefore never source its packs from a checkout that might not exist.
Making this repo the copy means the worst case is a stale mirror — visible and
harmless — rather than a disarmed guard.

## Testing

```sh
dcg corpus -d tests/corpus --baseline tests/baseline.json   # the official path
test/run.sh          # both suites (104 cases)
test/run.sh corpus   # corpus only
test/run.sh -v       # show every case
```

Two suites, because one tool cannot express both:

- **`tests/corpus/`** (61) runs under `dcg corpus`, dcg's own regression
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
run the matrices. Verified against dcg 0.9.0.

## Two things that will trip you up

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

## Pattern conventions

Every pattern, destructive and safe alike, anchors to a real command position
and walks intervening tokens with a bounded character class. Neither is
cosmetic — the reasoning, including the prose-matching bug and the fail-open
safe pattern that motivated them, is in `README.md` and `packs/readme.md`. A
new rule that does not follow both will be wrong in one of those two ways.
