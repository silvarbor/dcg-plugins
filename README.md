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
delete a peer worktree, bypass Git's worktree-aware ref checks, or force-update
remote refs:

- `git worktree remove`
- immediate object or reflog expiration
- non-dry-run `git prune`
- `git update-ref -d` and `git update-ref --stdin`
- a leading `+` push refspec
- `git push --mirror`

The built-in `core.git` pack continues to cover ordinary force pushes, stash
deletion, and destructive worktree-local commands. The companion allowlist
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
example, `git -C --help worktree remove` remains guarded.

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
`example/config.toml` shows the complete setup.

## Matching design

The packs use dcg 0.10 executable scoping. dcg resolves assignments, wrappers,
and executable paths before it applies a custom pattern. A rule for `gh` does
not deny another program merely because its argument text mentions `gh`.

Every active destructive pattern also starts at a command position. This
anchor limits matches to command positions, not phrases in the scoped
executable's arguments.

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
checks every expected and actual rule ID because dcg 0.10 can report a mismatch
as passed. `test/cases/` exercises effective policy and isolates the custom Git
pack to avoid built-in-rule precedence. Allowlist-driven results such as Git
reset and the shared help policy require this suite.

The active and disabled pack files validate without warnings under dcg 0.10.0.
CI pins that version and its release checksum. CI also asserts that dcg loads
both active pack IDs. An empty `custom_paths` glob removes all custom
protection while dcg still reports healthy.

See `AGENTS.md` for repository operations. See `packs/readme.md` for the full
rule scope.

This project uses the Apache License 2.0. See `LICENSE` and `NOTICE`.
