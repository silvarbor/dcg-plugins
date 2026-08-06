# DCG custom packs

Custom DCG packs for multi-agent workflows. Three concerns: cross-boundary
protection for git (the `git_safety` packs), process-hygiene protection
against process-leaking shell constructs (the `process_hygiene` pack), and
protection against outward actions that cannot be undone (the
`access_boundary` pack).

## Layout

```
packs/
├── silvarbor.git_safety.worktree_isolated.yaml     # active
├── silvarbor.process_hygiene.yaml                  # active
├── silvarbor.access_boundary.yaml                  # active
├── disabled/
│   └── silvarbor.git_safety.shared_checkout.yaml   # staged, not loaded
└── readme.md                                       # this file
```

DCG auto-loads `*.yaml` files from this directory via the `custom_paths`
glob in the dcg `config.toml`. The glob does not cross into subdirectories,
so files under `disabled/` are not picked up. The two `git_safety` packs
are mutually exclusive — exactly one is active at a time — and
`process_hygiene` is always active alongside whichever git pack is loaded.

Both git packs carry the pack id `silvarbor.git_safety`; they are distinguished
by filename and by which directory they sit in, never loaded together.

## The charter

**Block only what escapes the worktree boundary.**

Anything a command can reach inside its own worktree — HEAD, the index,
the working tree — belongs to the calling agent and is not this pack's
business. Exactly two resources are shared and therefore in scope:

1. **The common git dir** — `refs/stash`, the object store, reflogs,
   `refs/heads`, and repo config are shared by every worktree in the pool.
2. **The remote** — no per-agent isolation, and no client-side reflog for
   force-pushed history.

## The two packs

| Pack file                                | Enable when                             | Blocks                                                                                                 |
| ---------------------------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `silvarbor.git_safety.worktree_isolated` | Each agent runs in its own git worktree | Cross-worktree and remote operations only (see the scope table below)                                  |
| `silvarbor.git_safety.shared_checkout`   | Multiple agents share a working tree    | Everything: stash, `checkout --`, restore, all `git reset`, `clean -f`, `branch -d/-D`, `push --force` |

The shared-checkout pack blocks far more because a shared tree has no
boundary to contain anything — one agent's `reset --hard` really does
overwrite another agent's uncommitted work there.

## What the boundary actually contains

Verified empirically in a two-worktree lab repo rather than assumed:

| Question                                    | Result                                                                         |
| ------------------------------------------- | ------------------------------------------------------------------------------ |
| Is `refs/stash` shared?                     | **Yes** — a stash pushed in worktree A appears in `git stash list` from B      |
| Can A delete a branch checked out in B?     | **No** — git refuses: `cannot delete branch 'x' used by worktree at .../B`     |
| Can A force-move a branch checked out in B? | **No** — git refuses with the same guard                                       |
| Does `git reset --hard` in A touch B?       | **No** — B's HEAD unchanged, B's working tree clean                            |
| Can A destroy B wholesale?                  | **Yes** — `git worktree remove --force ../B` deleted B *including staged work* |

Two consequences drive the rule set. `git reset` is worktree-local and is
therefore **allowed**. `git worktree remove` is the one command that
annihilates a peer agent outright, so it is blocked at critical severity.

## Scope table — active pack

| Operation                                             | Crosses the boundary?                                   | Guard                                                       |
| ----------------------------------------------------- | ------------------------------------------------------- | ----------------------------------------------------------- |
| `git worktree remove` / `prune`                       | Deletes a peer worktree and its uncommitted work        | Blocked                                                     |
| `git stash drop` / `pop` / `clear`                    | Removes entries from the shared `refs/stash`            | Blocked                                                     |
| `git gc --prune=now` / `prune` / `reflog expire`      | Destroys the shared object store and reflogs            | Blocked                                                     |
| `git update-ref -d` / `--stdin`                       | Deletes shared refs, bypassing git's worktree guard     | Blocked                                                     |
| `git remote remove` / `rm` / `set-url`                | Repoints or drops the remote for every worktree         | Blocked                                                     |
| `git push --force` / `-f`                             | Rewrites remote history unverified                      | Blocked                                                     |
| `git push +<refspec>` / `--mirror`                    | Force-updates the remote with no `--force` flag present | Blocked                                                     |
| `git reset` (all modes, incl. `--hard`)               | No — HEAD, index, and tree are per-worktree             | Allowed                                                     |
| `git checkout -- <path>` / `git restore`              | No — changes only the caller's index and working tree   | Allowed                                                     |
| `git branch -d` / `-D`                                | No — git refuses when checked out elsewhere; reflogged  | Allowed                                                     |
| `git push origin --delete <branch>`                   | Routine remote cleanup                                  | Allowed                                                     |
| `git stash push` / `list` / `show` / `apply`          | Adds or reads; destroys no stash data                   | Allowed                                                     |
| `git worktree add` / `list`                           | Creating and reading never destroy                      | Allowed                                                     |
| `git gc` (default expiry) / `prune-packed`            | Honours the two-week expiry; recent objects survive     | Allowed                                                     |
| `git push --force-with-lease` / `--force-if-includes` | Verified force                                          | Allowed                                                     |
| `git clean -f` / `-fdx`                               | No — worktree-local, but irreversible with no reflog    | Blocked by `core.git` (deliberate exception to the charter) |

`git clean -f` is the one deliberate departure from the charter: it cannot
cross a worktree boundary, but it deletes untracked files with no object
store fallback, so the built-in `core.git:clean-force` rule stays on.

## Pattern conventions

Both git packs follow the same two conventions, and both apply them to
`safe_patterns` as well as `destructive_patterns`. Keeping the two packs
in lockstep means swapping between them never changes matching behaviour.

**1. Anchor to a real command position.** The prefix is:

```
(?:^|[\n;&|(]|\b(?:then|else|do)\s+)\s*      command position
(?:[A-Za-z_][A-Za-z0-9_]*=[^\s]*\s+){0,4}    env assignments
(?:(?:sudo|command|nohup|time)\s+){0,2}      command wrappers
git\s+
```

The older prefix `(?:^|[^[:alnum:]_-])` accepted any non-word character
before `git`, so prose *describing* a hazard matched as if it *performed*
one. A handoff document about worktree pruning was blocked on 2026-07-27
purely for containing the words. The anchor requires the match to sit
where a command could actually begin.

A quote lookbehind such as ``(?<![`'"])`` is **not** part of the prefix and
was removed after being shown redundant: once a command-position character
plus `\s*` has been consumed, the character immediately before `git` can
only be whitespace or the separator itself, never a quote or backtick.

The two repetitions are bounded (`{0,4}`, `{0,2}`) rather than starred.
With `*` they are nested quantifiers, and a long non-matching command line
drove enough backtracking to overrun the hook evaluation budget. See the
`config.toml` entry under Related files for the measurements and for
why the timeout override that accompanied this fix is no longer needed.

**2. Walk intervening tokens with the bounded class, not the greedy one:**

```
bounded (use this):   (?:[^\s&;|`()<>]+\s+)*
unbounded (avoid):    (?:\S+\s+)*   and   .*
```

`\S+` and `.*` span `&&`, `;`, and `|` into unrelated commands — the
harmless `git log --oneline; ls stash clear` matched a stash rule built
that way. This is the same defect `allowlist.toml` cites when disabling
several built-in `core.git` rules, so custom rules must not reintroduce it.

The overreach is worse in a *safe* pattern, because there it fails **open**
rather than closed. The carve-out `\bgit\s+push\b.*--force-(?:with-lease|if-includes)\b`
was satisfied by a `--force-with-lease` token appearing anywhere later on
the line — after a `;`, inside an `echo` — whitelisting an unrelated
unverified force push. Nothing was ever actually permitted, because
`core.git:push-force-long` denies that line independently, but a carve-out
must not depend on another pack for its correctness. Both packs now use the
bounded walker in every safe pattern.

### Known limit: backtick-delimited prose

Neither convention can rescue text like `` `git worktree prune` `` inside
a document. In shell, `` `cmd` `` **is** command substitution, so dcg
extracts the span and scans its contents as a command; the extracted text
begins at `^` and matches legitimately. A markdown code span and a shell
command substitution are byte-identical, so no pack-level regex can tell
them apart — and a guard that ignored backticks would miss a real bypass.

Pass prose bodies to a tool by redirect or file argument rather than
inline on the command line:

```sh
some-tool session handoff < body.txt      # dcg sees only this line
```

Single quotes, double quotes, and unquoted prose are all fine after the
anchoring fix; only backticks and `$(...)` are scanned as commands.

### Residual false positives from built-in rules

The conventions above apply only to this pack. Three `core.git` rules are
still active with the old unanchored prefix, so prose mentioning them can
still block: `push-force-long`, `push-force-short`, and `clean-force`.
Allowlisting them would remove real protection, so they are left as-is.

## Switching to the shared-checkout pack

```sh
mv ~/.config/dcg/packs/silvarbor.git_safety.worktree_isolated.yaml ~/.config/dcg/packs/disabled/
mv ~/.config/dcg/packs/disabled/silvarbor.git_safety.shared_checkout.yaml ~/.config/dcg/packs/
```

Also revisit `allowlist.toml`: its entries switch off the built-in
`core.git` rules for reset, checkout, restore, and branch deletion on the
grounds that the worktree boundary contains them. Under a shared checkout
that reasoning does not hold. The shared-checkout pack carries its own
rules for checkout, restore, and reset, so those stay covered — but the
`core.git:reset-hard`, `reset-merge`, and `branch-force-delete` entries
should be removed so nothing is silently permitted.

Both packs block `git push --force`, so the swap never reduces remote
protection. The disabled pack is kept current rather than left to rot: it
carries the same anchoring and bounded-walker conventions as the active
one, so enabling it is a file move and nothing else. It is verified the
same way — every rule, every carve-out, and the prose false-positive
guards, run against a throwaway config whose `custom_paths` points only at
`disabled/`.

## Process-hygiene pack

`silvarbor.process_hygiene` blocks the shell constructs that leak unreaped
processes under an agent harness. The harness spawns a helper process tree
per shell call plus a monitor that polls background tasks, and does not
reliably reap them; poll loops, `gh run watch`, and backgrounded or
loop-paced `sleep`s accumulate monitored children across turns and
concurrent agents until `posix_spawn` returns `EAGAIN` and the agent is
force-killed.

| Blocks                                   | Rule               |
| ---------------------------------------- | ------------------ |
| `until ...; do ...; done` (any)          | `poll-loop-until`  |
| `while`/`for` loop containing `sleep`    | `poll-loop-sleep`  |
| `while` loop polling a probe in the cond | `poll-loop-probe`  |
| `sleep N &` (backgrounded)               | `background-sleep` |
| `gh run watch`                           | `gh-run-watch`     |

A bare one-shot `sleep N` (and `sleep N; <check>` / `sleep N && <cmd>`)
stays allowed — the documented short-wait carve-out. Wait out-of-band
instead: hand the wait to the runtime timer, or start a single background
command and let the harness notify on completion.

### Anchoring, and the subshell bypass

The same command-position anchoring applies here. `background-sleep` and
`gh-run-watch` carry the full prefix (command position, env assignments,
wrappers) so that prose and `grep` patterns mentioning them do not block.
The three poll-loop rules use the shorter keyword anchor
`(?:^|[\n;&|(]|\bthen\b|\bdo\b)\s*`, because a loop keyword can legally
follow `then` or `do` without an intervening separator.

Adding `\n` and `(` to that anchor closed a live bypass. The earlier form
listed only `; && || & |`, so wrapping a loop in a subshell —
`(while true; do sleep 5; done)` — put `while` after an unlisted `(` and
the rule missed it entirely. Multi-line loops written across newlines
escaped the same way. Both forms now match.

### Why `gh run watch` is blocked and `gh pr checks --watch` is not

Stated plainly because the asymmetry is a policy choice, not a technical
one: `gh pr checks --watch` is *also* a single long-lived foreground
watcher holding the harness process tree open. Measured against "unreaped
process tree" alone the two are equivalent, and neither forks per
iteration — the rule does not rest on that distinction. Three differences
justify permitting one and blocking the other:

- **Poll rate** — `gh run watch` defaults to `-i 3`; `gh pr checks --watch`
  defaults to 10 and the manage-pr skill mandates `--interval 30`, roughly
  a tenth of the API traffic.
- **Termination** — `--fail-fast` ends the wait at the first failing check.
  `--exit-status` only sets the exit code, so `gh run watch` runs to
  completion either way.
- **Fan-out** — `gh run watch` follows one run, so a PR with N workflows
  needs N concurrent watchers; `gh pr checks --watch` covers the whole
  rollup in one process. This is the only one of the three that is
  genuinely a process-count argument.

`gh pr checks --watch --fail-fast --interval 30` is therefore the single
bounded foreground wait this policy standardizes on. It is deliberately
left unenforced: the skills mandate the interval, the pack does not check
it. Enforcing a numeric flag bound would need a regex that reads an
argument value, which is more fragile than every other rule here.

## Access-boundary pack

`silvarbor.access_boundary` blocks the outward actions a harnessed agent
cannot undo. Each is reversible in *state* and irreversible in *effect*:
closing a pull request leaves the notification in every watcher's inbox,
unpublishing a package is time-limited on npm and impossible on PyPI, and a
repository made public is crawled before it can be made private again.

| Blocks                                                           | Rule                           |
| ---------------------------------------------------------------- | ------------------------------ |
| `gh pr create` with no `--repo`                                  | `gh-pr-create-implicit-target` |
| `gh repo edit --visibility`                                      | `gh-repo-visibility-change`    |
| `gh secret set`                                                  | `gh-secret-write`              |
| npm/pnpm/yarn/poetry/cargo `publish`, `twine upload`, `gem push` | `registry-publish`             |

`gh repo delete` is **not** here — `platform.github:gh-repo-delete` already
covers it, and duplicating a built-in produces two messages for one action.

### The charter, and what a pack cannot enforce

An agent's permitted area is the working directory the harness declares for
the session. Most of that boundary is **not expressible in a pack**: a rule
matches a static regex against command text and cannot see the session's cwd,
so no pattern can compare a path argument against it. Verified empirically —
the same three cwd-sensitive commands were fed to dcg 0.9.0 with cwd set to
`/tmp/sandbox`, `/Users/shz`, and a repository checkout; all nine verdicts
were identical.

So `find ~`, `grep -r ~/`, and `git -C <elsewhere>` are out of scope here and
live in agent instructions and Claude Code's `permissions.deny`. What is in
scope is the set of actions whose blast radius does not depend on cwd at all.

### Why the pull-request rule exists

On 2026-08-05 three pull requests were opened against a third-party upstream
from a fork. No command named the target. `gh` resolves the base repository
of a fork to its **parent**, so `gh pr create` in a checkout with an
`upstream` remote opens against the parent, and nothing in the command says
so. The operator had `READ` there and `ADMIN` on the fork.

The permission level is not knowable from command text. The **missing**
`--repo` is. The rule checks only that a target was named — a wrong `--repo`
still passes, a wrong default no longer does.

Stated plainly because it is a policy choice, not a technical one: this costs
friction in every ordinary repository, where `gh pr create` is unremarkable
and the default base is correct. Every PR now needs one extra flag. The trade
is deliberate — the failure is silent, reaches strangers, and cannot be
recalled, while the fix documents itself.

### Keywords are a pre-filter, not documentation

`keywords` is evaluated **before** any pattern. A command containing none of
them never reaches this pack. `twine upload` and `gem push` silently matched
nothing until `twine`, `gem`, and `upload` were listed, while `npm publish`
and `cargo publish` worked from the start because both carry a listed word.
Nothing warns about this: the pack validates clean, loads clean, and returns
ALLOW. Every command name a pattern can match must appear in `keywords`, and
`tests/corpus/true_positives/access_boundary.toml` carries a case per
keyword-only ecosystem to catch a regression.

### Residual false positive in a built-in rule

`platform.github:gh-repo-delete` carries the old unanchored prefix and matches
prose. A shell loop containing the string `"gh repo delete acme/x"` as a
double-quoted list element was blocked on 2026-08-05 while probing existing
coverage. This is the same class as the three `core.git` rules noted above,
and the same reasoning applies: allowlisting it would remove real protection,
so it is left as-is. Pass command text by file rather than inline, as
`test/run.sh` does.

## Related files

- **`config.toml`** — dcg config; `custom_paths` includes this directory.
  Lives at `~/.config/dcg/config.toml`; the plugins repo ships a copy of it
  under `example/`.
  It sets no `hook_timeout_ms`. It briefly pinned 500 while the default was
  200ms: dcg 0.7.1's shell-grammar parser costs roughly 7–8× on command
  lines carrying nested `$(...)` — a 992-char line measures 3.1ms plain
  against 26ms with 16 substitutions — and long agent command lines were
  overrunning the budget. dcg 0.8.0 raised the default to 1000, so the
  override was dropped; keeping it would now *cap* the budget below the
  shipped default. Env override if ever needed: `DCG_HOOK_TIMEOUT_MS`.

  The bounded quantifiers in the pack prefixes remain the pack-attributable
  half of that fix (~25ms) and are not affected by the default change. Note
  also that dcg fails closed on a substitution *count* cap ("too many
  substitutions for bounded static analysis") which no config key controls —
  no timeout value affects it.
- **`allowlist.toml`** — rule-specific policy overrides, alongside
  `config.toml` and mirrored under `example/`. Switches off the
  built-in `core.git` rules for operations the worktree boundary already
  contains (reset, path checkout, restore, branch deletion) and hands the
  stash rules to the cross-worktree custom rule. Each entry records why
  the operation cannot cross the boundary.
- **`pending_exceptions.jsonl`** — dcg writes queued one-off exception
  requests next to your config. Gitignored in both repos: it captures full
  command lines including arguments and cwd.
