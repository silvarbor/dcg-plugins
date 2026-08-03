# AGENTS.md — dcg-plugins

Custom packs for [dcg](https://github.com/Dicklesworthstone/destructive_command_guard),
the Destructive Command Guard. `README.md` explains what the packs do and why;
this file is about working on them.

## Read this before editing anything

**This repository is a published copy, not the source of truth.**

The packs are authored in the maintainer's dcg config repo (`~/.config/dcg`)
and copied here by `bin/publish-packs` in that repo. Everything under
`packs/`, `example/`, and `test/` is overwritten wholesale on the next publish.

An edit made here is not merely unshared — it is *silently reverted* the next
time anyone publishes, and because a pack that stops matching still validates
clean, the loss can go unnoticed. If you are the maintainer, edit in the config
repo. If you are not, open an issue or a PR and expect it to be applied
upstream first.

Files that genuinely live here and are never overwritten: `README.md`,
`AGENTS.md`, `.gitignore`, `dprint.jsonc`.

## Why the copy goes this direction

A dcg `custom_paths` glob that matches nothing is a **silent, total loss of
protection**. Measured against dcg 0.7.8 with a deliberately dead path (re-confirmed on
0.8.0):

```
silvarbor packs listed : 0
warnings emitted       : 0        <- nothing on stdout or stderr
dcg doctor             : "Checking pattern packs... OK"

git worktree remove ../peer  ->  ALLOW
git stash drop               ->  ALLOW
git reflog expire --all      ->  ALLOW
```

dcg reports healthy while every cross-boundary rule has vanished. So a live
config must never source its packs from a checkout that might not exist. Making
this repo the copy means the worst case is a stale mirror — visible and
harmless — rather than a disarmed guard.

## Testing

```sh
test/run.sh          # 104 cases across all three packs
test/run.sh -v       # show every case
test/run.sh process_hygiene
```

Requires `dcg` on `PATH`. The `worktree_isolated` and `process_hygiene` suites
run against **your** dcg config, so they double as an installation check:
several ALLOW expectations depend on `example/allowlist.toml` being installed,
and they will fail loudly if it is not. That is intended — the pack alone does
not produce the documented behaviour. The `shared_checkout` suite builds its
own throwaway config, since that pack shares a pack id with the active one and
the two must never load together.

`dcg pack validate` proves a pack parses. It does not prove a rule still
matches. Always run the matrix.

## Two things that will trip you up

**dcg hooks your own shell.** A command line containing `git worktree remove`
or a poll loop is blocked *for you*, including when you are testing the very
rule that blocks it. That is why the cases live in `test/cases/*.tsv` and reach
dcg through a variable rather than inline. The same applies to prose: in shell
`` `cmd` `` **is** command substitution, so a markdown code span containing a
guarded command is byte-identical to the real thing and no pack-level regex can
separate them. Pass document bodies by `<` redirect.

**dprint reformats on save.** `dprint.jsonc` excludes `**/*.toml` and
`packs/**/*.yaml` — the packs carry long *unquoted* regex scalars, and a
formatter that requoted or folded one would silently alter a security rule
while it still validated clean. Markdown is formatted and it rewrites inline
code spans, so anything containing a backtick belongs in a fenced block.

These exclusions only apply to `dprint` invoked without an explicit `--config`.
An editor or agent hook that passes `--config <global>` bypasses per-directory
resolution and reformats the excluded files anyway — and `dprint check` will
still report them out of scope while it happens, so it is not a reliable
signal. Prefer `(cd "$(dirname "$FILE")" && dprint fmt "$FILE")` in such hooks,
which resolves upward from the file and falls back to the global config on its
own.

## Pattern conventions

Every pattern, destructive and safe alike, anchors to a real command position
and walks intervening tokens with a bounded character class. Neither is
cosmetic — the reasoning, including the prose-matching bug and the fail-open
safe pattern that motivated them, is in `README.md` and `packs/readme.md`.
A new rule that does not follow both conventions will be wrong in one of those
two ways.
