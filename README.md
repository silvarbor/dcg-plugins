# dcg-plugins

Custom [dcg](https://github.com/Dicklesworthstone/destructive_command_guard)
packs for multi-agent coding setups, where several agents run against the same
repository at once.

dcg — Destructive Command Guard — is a pre-execution hook for Claude Code,
Codex CLI, Gemini CLI, Copilot CLI, Cursor, and Hermes. It inspects each shell
command an agent proposes and blocks the destructive ones. It ships with
built-in packs; these are custom packs layered on top.

Three packs, three unrelated concerns.

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

## `silvarbor.access_boundary` — outward actions an agent cannot recall

The other two packs protect the checkout. This one protects everybody else.
Each blocked action is reversible in *state* and irreversible in *effect*:
closing a pull request leaves the notification in every watcher's inbox,
unpublishing a package is time-limited on npm and impossible on PyPI, and a
repository made public is crawled before it can be made private again.

Blocked: `gh pr create` with no `--repo`, `gh repo edit --visibility`,
`gh secret set`, and registry publishes — `npm`/`pnpm`/`yarn`/`poetry`/`cargo`
`publish`, `twine upload`, `gem push`.

Allowed: anything that names its target, every read (`gh pr list`,
`gh pr view`, `gh secret list`), `gh pr merge`, and `gh release create`.
`gh repo delete` is not here because `platform.github` already covers it.

**The pull-request rule is the odd one, and it costs you a flag.** `gh`
resolves the base repository of a fork to its **parent**, so `gh pr create` in
a checkout with an `upstream` remote opens against that parent, and nothing in
the command says so. Three pull requests reached a third-party repository that
way. Whether the author may write to the target is not knowable from command
text; the *missing* `--repo` is. The rule checks only that a target was named
— a wrong `--repo` still passes, a wrong default no longer does. In an
ordinary repository the default is correct and the flag is pure friction. The
trade is deliberate: the failure is silent, it reaches strangers, and it
cannot be recalled.

Most of an access boundary is **not expressible in a pack at all**. A rule
matches static command text and cannot see the session's working directory, so
no pattern separates `git -C ~/someone-elses-repo` from `git -C .`. That was
verified rather than assumed: the same commands fed to dcg from three
different working directories produced nine identical verdicts. `find ~`,
`grep -r ~/` and their kind belong in agent instructions and in the harness's
own permission layer. This pack covers only the actions whose blast radius
does not depend on where the agent stands.

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
inspection, across dcg's official harness and a supplementary suite:

- **`tests/corpus/`** runs under `dcg corpus`, dcg's own regression harness, in
  the upstream `true_positives` / `false_positives` / `bypass_attempts`
  taxonomy. Every case asserts a `rule_id`, so a command denied by the *wrong*
  rule is a failure, and `tests/baseline.json` makes regressions a non-zero exit
  rather than a judgement call.
- **`test/cases/`** runs against `dcg explain`. `dcg corpus` deliberately
  evaluates pack matching without applying `allowlist.toml`, and has no
  `--config` flag, so the allowlist-dependent ALLOWs and the shared_checkout
  pack cannot be expressed there.

What each pack's cases cover:

- **`git_safety.worktree_isolated`** — cross-boundary operations expected DENY,
  worktree-local and routine operations expected ALLOW, and prose /
  neighbouring-command false-positive guards.
- **`git_safety.shared_checkout`** — every rule, every carve-out, and the prose
  guards, run against a throwaway config whose `custom_paths` points only at
  `disabled/` so the shared pack id cannot collide with the active pack.
- **`process_hygiene`** — subshell-wrapped, multi-line, prose, and carve-out
  forms.
- **`access_boundary`** — every blocked action, the `--repo` carve-out, prose
  guards, and one case per registry whose command name shares no keyword with
  the others.

`test/run.sh` prints the totals. They are not repeated in prose here, because
a number in a document is a number that goes stale.

All four pack files validate clean with zero warnings under `dcg pack
validate`. Last run against dcg 0.9.2.

Run them yourself:

```sh
test/run.sh          # corpus + policy suites
test/run.sh -v       # show every case
```

`.github/workflows/deterministic-verification.yml` runs the same suites on
every push and pull request, against a version-pinned and checksum-pinned dcg
release. It installs the packs the way this section of the README tells you to
and then asserts that dcg actually loaded them: a `custom_paths` glob matching
nothing costs you every rule while dcg still reports healthy, which `AGENTS.md`
covers under "Why a dangling symlink is dangerous".

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
