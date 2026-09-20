# dcg-plugins

Custom [dcg](https://github.com/Dicklesworthstone/destructive_command_guard)
packs for multi-agent coding setups. dcg inspects shell commands before they
run and blocks destructive operations.

This repository provides two active packs:

- `silvarbor.git_safety` protects resources shared by a Git worktree pool.
- `silvarbor.access_boundary` protects external systems from actions that are
  difficult or impossible to recall.

`packs/disabled/` retains the former process-hygiene pack for reference. This
repository provides no active sleep, polling-loop, or watcher rules.

## Git safety

Each agent gets a separate Git worktree. HEAD, the index, and the working tree
belong to that agent; the common Git directory and remotes remain shared.

The custom pack blocks only six forms. They can destroy shared recovery data,
force-delete a peer worktree, bypass Git's worktree-aware ref checks, or force-update
remote refs:

- `git worktree remove --force`
- immediate object or reflog expiration
- non-dry-run `git prune`
- `git update-ref -d` and `git update-ref --stdin`
- a leading `+` push refspec
- `git push --mirror`

The built-in `core.git` pack continues to cover ordinary force pushes,
`git stash clear`, and destructive worktree-local commands; it warns on
`git stash drop` and lets it run. The companion allowlist
permits reset, path checkout, restore, and branch deletion because those
operations cannot cross the worktree boundary.

The custom pack deliberately allows routine operations that proved too noisy
to guard: `git worktree prune`, `git stash pop`, and remote configuration
changes. It also allows `git push --force-with-lease` and
`--force-if-includes`.

## Access boundary

The access pack blocks three classes of outward action:

- `gh repo edit --visibility`
- `gh secret set`
- package publication through npm, pnpm, Yarn, Poetry, Cargo, Twine, or RubyGems

The pack allows supported registry dry runs.

dcg ships `platform.github:gh-repo-visibility-change`, and on the plain command
that built-in rule takes attribution, so the corpus asserts the upstream rule
ID. The custom rule stays because the built-in pack treats every `--help` token
as a safe pattern since dcg 0.14.1, which lets `gh repo edit --description
--help --visibility public` through while `gh` reads that `--help` as the
description's value and changes visibility. A pack's safe patterns suppress
only its own rules, so the denial comes from the custom rule; the policy suite
asserts that attribution. The rule's token walk is bounded and stops at a shell
metacharacter, quoted or not, so an intervening argument carrying one escapes
the custom rule. The built-in rule still denies that shape on its own; only
the combination of such an argument and a `--help` value escapes both rules,
and the known-limits suite keeps that residue visible.

The custom policy does not block pull-request commands. In particular, `gh pr
create` does not require `--repo`. GitHub CLI can infer repository context from
the checkout. Separate forks through repository layout and agent instructions.

A static command pack cannot express most path boundaries. dcg cannot
compare a path argument with the session's permitted directory, so filesystem
scope belongs in the harness permission layer and agent instructions.

## Help policy

`allowlist.toml` allows help commands centrally because a pack-local safe
pattern cannot override a rule from another pack. The policy supports:

- shell `help [<topic>]`
- immediate `help` subcommands for Cargo, chezmoi, dcg, RubyGems, GitHub CLI,
  Git, npm, pnpm, Poetry, spx, Twine, and Yarn
- option-free command paths ending in an unquoted `--help`
- trailing `--help` for guarded GitHub and Git commands with declared option
  arity
- the `git help` subcommand after global options with declared argument counts
- help piped to `less`, `more`, or `cat`, or followed by a final `&`

Known value-taking options consume a following `--help` token as data. For
example, `git -C --help worktree remove --force ../peer` remains guarded.

Redirects are not part of the help allowlist. The rest of dcg therefore still
evaluates their destination; a help command cannot use the broad exception to
write to a protected file. dcg also continues to guard destructive
neighbouring commands.

## Install

Point dcg's `custom_paths` at this repository:

```toml
[packs]
custom_paths = [
  "/path/to/dcg-plugins/packs/*.yaml",
]
```

The glob does not descend into `packs/disabled/`.

Install `example/allowlist.toml` as well. Without it, dcg's built-in Git rules
still deny worktree-local operations that this policy intentionally permits.
Keep the `[policy.rules]` table from `example/config.toml` too. Its one entry
relaxes `core.filesystem:redirect-truncate-dynamic-path` to a warning, and
`test/cases/resolved_modes.tsv` pins that entry: without it the row is a
denial. The table is also the only place a built-in rule's mode changes: dcg
resolves a medium-severity rule such as `core.git:stash-drop` to a warning
that lets the command run, this policy accepts that default, and a custom pack
cannot raise a built-in rule's severity. An override to `deny` in that table
is the one way to change it. `example/config.toml` shows the complete setup.

## Matching design

Every active destructive pattern starts at a command position. The anchor walks
assignments, wrappers, and an executable path itself, so a rule for `gh` does
not deny another program merely because its argument text mentions `gh`.

No rule declares `executables`. dcg resolves that scope in the evaluator rather
than in the pattern, and the resolution gives up once more than 96 wrapper
tokens precede the command: past that point every scoped rule is dropped and
the command is ALLOWed, with nothing on stdout or stderr and no rule named in
the verdict. dcg 0.11 gave up on long assignment prefixes too; 0.14 resolves
those and still fails open on `command command … git`. The pattern anchor
already pins the command name, so the declaration was redundant where it worked
and a silent fail-open where it did not. `test/cases/performance.tsv` pins both
prefix kinds at 128 tokens so the gap cannot return unnoticed.

Rules require subcommands at their declared grammar positions. They do not
search later argument values for a command-shaped phrase.

Patterns still walk tokens with a bounded class that stops at shell operators:

```text
(?:[^\s&;|`()<>]+\s+)*
```

`.*` and `\S+` can cross `;`, `&&`, or a pipeline into an unrelated command.
That is especially dangerous in a safe pattern, where overmatching fails open.

The `keywords` field is a pre-filter, not documentation. Every executable a
pattern can match must appear there or dcg skips the pack without warning.

## Verification

Run both suites after every rule or allowlist change:

```sh
test/run.sh
```

`tests/corpus/` uses dcg's native regression harness. The runner independently
checks every expected and actual rule ID because dcg 0.14 still reports a
wrong-rule denial as passed. `test/cases/` exercises effective policy and
asserts which rule claims each custom-pack case. Allowlist-driven results such
as Git reset, the shared help policy, and resolved modes such as the `WARN` on
`git stash drop` require this suite: the corpus applies neither
`allowlist.toml` nor `[policy.rules]`, and a medium-severity built-in rule such
as `core.git:stash-drop` warns in the hook and lets the command run unless the
config overrides it to `deny`. Its performance matrix
also enforces a 200 ms evaluation budget on 65-entry stress chains, and pins
matching again at 128 entries, past the evaluator's scope-resolution ceiling.

The active and disabled pack files validate without warnings under dcg 0.14.4.
CI pins that version and its release checksum. CI also asserts that dcg loads
both active pack IDs. An empty `custom_paths` glob removes all custom
protection while dcg still reports healthy.

See `AGENTS.md` for repository operations. See `packs/readme.md` for the full
rule scope.

This project uses the Apache License 2.0. See `LICENSE` and `NOTICE`.
