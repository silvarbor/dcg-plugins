# dcg-plugins

Custom [dcg](https://github.com/Dicklesworthstone/destructive_command_guard)
packs for multi-agent coding setups, where several agents run against the same
repository at once.

dcg — Destructive Command Guard — is a pre-execution hook for Claude Code,
Codex CLI, Gemini CLI, Copilot CLI, Cursor, and Hermes. It inspects each shell
command an agent proposes and blocks the destructive ones. It ships with
built-in packs; these are custom packs layered on top.

Two packs, two unrelated concerns.

## `silvarbor.git_safety` — the worktree boundary

Written for a worktree pool: every agent gets its own `git worktree`, all
sharing one common git dir and one remote.

**Charter: block only what escapes the worktree boundary.**

Anything a command can reach inside its own worktree — HEAD, the index, the
working tree — belongs to the calling agent and is nobody else's business.
Exactly two resources are shared, and only those are in scope:

1. **The common git dir** — `refs/stash`, the object store, reflogs,
   `refs/heads`, and repo config are shared by every worktree in the pool.
2. **The remote** — no per-agent isolation, and no client-side reflog to
   recover force-pushed history from.

That boundary was established empirically in a two-worktree lab repo rather
than assumed:

| Question                                    | Result                                                                         |
| ------------------------------------------- | ------------------------------------------------------------------------------ |
| Is `refs/stash` shared?                     | **Yes** — a stash pushed in worktree A appears in `git stash list` from B      |
| Can A delete a branch checked out in B?     | **No** — git refuses: `cannot delete branch 'x' used by worktree at .../B`     |
| Can A force-move a branch checked out in B? | **No** — git refuses with the same guard                                       |
| Does `git reset --hard` in A touch B?       | **No** — B's HEAD unchanged, B's working tree clean                            |
| Can A destroy B wholesale?                  | **Yes** — `git worktree remove --force ../B` deleted B *including staged work* |

Two conclusions follow, and they are the reason this pack looks different from
most git guards. `git reset` is worktree-local, so blocking it buys nothing and
costs real false positives — it is **allowed**, including `--hard`. And
`git worktree remove` is the one command that annihilates a peer agent
outright, so it is blocked at critical severity.

Blocked: `worktree remove`/`prune`, `stash drop`/`pop`/`clear`,
`gc --prune=now`/`prune`/`reflog expire`, `update-ref -d`/`--stdin`,
`remote remove`/`rm`/`set-url`, `push --force`/`-f`, `push +<refspec>`,
`push --mirror`.

Allowed: all of `reset`, path `checkout`/`restore`, `branch -d`/`-D`,
`push origin --delete`, `stash push`/`list`/`apply`, `worktree add`/`list`,
default-expiry `gc`, `push --force-with-lease`/`--force-if-includes`.

A companion pack for the opposite setup — several agents sharing **one**
working tree — sits in `packs/disabled/`. There the boundary does not exist,
so it blocks far more, including all of `reset` and the whole `stash` family.
The two carry the same pack id and are mutually exclusive; enabling one is a
file move.

## `silvarbor.process_hygiene` — process leaks under a harness

An agent harness spawns a helper process tree per shell call plus a monitor
that polls background tasks, and does not reliably reap them. Poll loops,
long-lived watchers, and backgrounded or loop-paced `sleep`s accumulate
monitored children across turns and concurrent agents until the per-user
process limit is hit: `posix_spawn` returns `EAGAIN`, the monitor's `pgrep`
keeps failing, and the agent is force-killed — taking any concurrent agent's
uncommitted work with it.

Blocked: `until` loops, `while`/`for` loops containing `sleep`, `while` loops
polling a network probe in the condition, `sleep N &`, and `gh run watch`.

Allowed: a bare one-shot `sleep N`, and `sleep N; <check>` / `sleep N && <cmd>`.
Wait out-of-band instead — hand the wait to the runtime timer, or start one
background command and let the harness notify on completion.

## Install

Clone anywhere, then point dcg's `custom_paths` at the `packs/` directory:

```toml
# ~/.config/dcg/config.toml
[packs]
custom_paths = [
  "/path/to/dcg-plugins/packs/*.yaml",
]
```

The glob does not descend into subdirectories, so `packs/disabled/` is not
loaded.

### The allowlist is not optional

**`silvarbor.git_safety` does not do what this README says unless you also
install `example/allowlist.toml`.** The charter permits `git reset`, path
checkout, restore, and branch deletion — but dcg's built-in `core.git` pack
blocks all four, and a custom pack cannot un-block what another pack blocks.
The allowlist entries are what actually permit them, and each one records the
evidence for the decision.

Install both, or the pack will read as permissive while `core.git` quietly
keeps denying. `example/config.toml` shows the rest of a working setup.

## Pattern conventions

Both git packs use the same two conventions for every pattern, destructive and
safe alike, so switching between them never changes matching behaviour.

**Anchor to a real command position:**

```
(?:^|[\n;&|(]|\b(?:then|else|do)\s+)\s*      command position
(?:[A-Za-z_][A-Za-z0-9_]*=[^\s]*\s+){0,4}    env assignments
(?:(?:sudo|command|nohup|time)\s+){0,2}      command wrappers
git\s+
```

An earlier prefix, `(?:^|[^[:alnum:]_-])`, accepted any non-word character
before the command — so prose *describing* a hazard matched as if it
*performed* one, and a session handoff document was blocked purely for
containing the words "worktree prune".

**Walk intervening tokens with a bounded class,** never `\S+` or `.*`:

```
bounded (use this):   (?:[^\s&;|`()<>]+\s+)*
unbounded (avoid):    (?:\S+\s+)*   and   .*
```

The greedy forms span `&&`, `;`, and `|` into unrelated commands:
`git log --oneline; ls stash clear` matched a stash rule built that way. In a
*safe* pattern the same overreach fails open rather than closed — a
`--force-with-lease` token anywhere later on the line satisfied the
verified-push carve-out for an unrelated unverified force push.

The two repetitions are bounded (`{0,4}`, `{0,2}`) rather than starred; as
nested quantifiers with `*`, a long non-matching command line drove enough
backtracking to overrun dcg's hook evaluation budget.

### Known limit: backtick-delimited prose

Neither convention rescues text like `` `git worktree prune` `` inside a
document. In shell, `` `cmd` `` **is** command substitution, so dcg extracts
the span and scans its contents as a command — and the extracted text starts at
`^`, so it matches legitimately. A markdown code span and a shell command
substitution are byte-identical; no pack-level regex can separate them, and a
guard that ignored backticks would miss a real bypass.

Pass prose bodies by redirect or file argument rather than inline:

```sh
some-tool session handoff < body.txt      # dcg sees only this line
```

Single quotes, double quotes, and unquoted prose are all fine.

## Verification

Every rule is covered by a case matrix run against the real binary, not by
inspection. 104 cases in total, all committed under `test/`:

- **`git_safety.worktree_isolated`** — 51 cases: 23 cross-boundary operations
  expected DENY, 22 worktree-local and routine operations expected ALLOW, and 6
  prose / neighbouring-command false-positive guards.
- **`git_safety.shared_checkout`** — 37 cases covering every rule, every
  carve-out, and the prose guards, run against a throwaway config whose
  `custom_paths` points only at `disabled/` so the shared pack id cannot
  collide with the active pack.
- **`process_hygiene`** — subshell-wrapped, multi-line, prose, and carve-out
  forms.

All three packs validate clean with zero warnings under `dcg pack validate`.
Last run against dcg 0.8.0.

Run them yourself:

```sh
test/run.sh          # all three suites
test/run.sh -v       # show every case
```

`AGENTS.md` covers working on the packs, including why this repo is a published
copy rather than the source of truth. `packs/readme.md` carries the full scope
tables, the reasoning behind each decision, and the notes on switching between
the two git packs.

## Status

These are the packs we actually run, extracted from a working setup rather than
written as a general-purpose distribution. They encode one specific topology —
a worktree pool under an agent harness. Read the charter before adopting them;
if your agents share a working tree, the pack in `packs/disabled/` is the one
you want, and if they are fully isolated the git pack may be more than you need.

Licensed under the Apache License 2.0 — see `LICENSE` and `NOTICE`. The packs
carry SPDX headers so provenance travels with them once they are copied into a
`~/.config/dcg` somewhere else.
