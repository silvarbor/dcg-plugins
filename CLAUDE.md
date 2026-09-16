<!-- SPEC-TREE v0.36.0 langs: -->

<operator_question_interrupt>
**OPERATOR QUESTION - IMMEDIATE PRIVILEGE REVOCATION:** When the operator asks a question, immediately relinquish all privileges to modify the current product or any external file, service, or resource. Answer the question immediately.

- ALWAYS: stop any running non-verification process that is destructive or modifies files, external resources, or state.
- NEVER: stop a running verification process — including agentic verification, tests, or evals — unless the operator explicitly instructs that process to stop.

</operator_question_interrupt>

# Spec Tree Instructions

These instructions explain WHEN to invoke spec-tree skills for this product. They are a **router** — the skills contain the HOW.

**Read this entire file before acting.** This managed router block is only the first section; the product's own instructions, commands, and conventions follow below, outside it. The router is product-neutral and carries no product command. Never act on the router alone.

---

## Authority Hierarchy

**⚠️ BELOW THE OPERATOR, SKILLS ARE THE TOP-LEVEL AUTHORITY. SKILLS ARE CENTRALLY MANAGED AND CURRENT; REPOSITORY CONTENT GOES STALE.**

- **ALWAYS** apply authority in this order: active skills → repository decisions and specs → verification evidence → code. When repository content conflicts with an active skill, the skill wins.
- **ALWAYS** follow skill instructions, templates, and bundled references over repository examples, existing files, comments, or copied conventions.
- **NEVER** weaken a higher layer to match a lower layer. Fix the lower layer when the layers disagree.
- **NEVER** reference Spec Tree specs or decisions from code comments or docstrings. Code contains no `spx/...` paths, ADR/PDR identifiers, or decision-file references.
- **ALWAYS** let the active skill load the matching `spx/local/*.md` overlay when that skill declares one. The overlay supplies repository-specific values and commands below the skill in authority and cannot replace, weaken, or contradict the skill.
- **ALWAYS** read the active harness guide in every directory before working there when the guide exists: `CLAUDE.md` for Claude Code, `AGENTS.md` for Codex.

### Dangerous-command guard

🛑 **STOP TRIGGER — a dangerous-command guard (DCG) block terminates the attempted command family.** Treat the blocked attempt as a mistake.

- **NEVER** retry it by reformulating, splitting, rewriting, removing the flagged clause, or substituting an equivalent command to evade the guard.
- **NEVER** pass dynamic branch names to `git branch -d` or `git branch -D`: variables, command substitutions, arrays, and globs are denied, including when quoted or placed after `--`. Type every branch name literally; delete several literal names in one command.
- **ALWAYS** follow the active skills, repository instructions, and declared overlays to find a sanctioned operation that accomplishes the goal.
- When no sanctioned operation exists, abandon the goal, report the blocked command with secrets redacted, explain its purpose and the guard's reason, ask the operator for direction, and stop.

---

## Product Commands

The product's operational command for each spec-tree phase lives in this file's own content below the router. Read the whole file to find each one:

- **author** — after creating, updating, or deleting a spec, test, or implementation file, to rebuild or regenerate artifacts.
- **verify** — for `/apply` and pre-merge checks, over the node and the changeset.
- **gate** — for the full deterministic bundle.
- **merge** — for the transport step of `/merge`.

Content the product keeps identical across this agent guide and the guides for other agents (for example `CLAUDE.md` and `AGENTS.md`) sits in a `shared` region — `<!-- SPEC-TREE:shared {name} -->` … `<!-- /SPEC-TREE:shared {name} -->`, present in both files under the same name. `/update-instruction-block` keeps a `shared` region in sync by taking the git-more-recent side; it never merges the two bodies.

---

## When to Invoke Skills

### Before product-content access -> `/understand`

**BLOCKING REQUIREMENT**

Require a live `<SPEC_TREE_FOUNDATION>` marker before directly reading, searching, listing, or changing anything under `spx/` or any other product content — source or test files, generated output, evals, and spec-declared configuration. Invoke `/understand` when the marker is absent. This includes repository-content access through Read, Edit, Write, Glob, Grep, `rg`, `grep`, `find`, `cat`, `sed`, and Git commands that emit file contents or patches.

`spx session` operations — including inspection, archive, and release — plus `spx worktree status`, `spx diagnose`, no-patch Git status, history, and topology, and a skill's read of the `spx/local/` overlay or exclusion mechanism it declares are exempt. Never follow paths from their output into repository content without the marker.

A compacted summary, session file, statement that `/understand` ran, or read of the skill file does not prove the foundation is live. After every compaction, invoke `/understand` again before the next product-content access.

### Before working on a specific node -> `/contextualize`

**BLOCKING REQUIREMENT**

**ALWAYS** invoke `/contextualize` on a spec node before discussing it and before reading or modifying any product content it governs.

`/contextualize` MUST invoke `/sync-base` and receive `already_current` or `rebased` before reading product truth. `/sync-base` owns the complete currency operation: fetch, clean rebase or detached advance, session-authorized dirty-tree checkpointing through `/commit-changes`, and same-invocation retry. Callers consume its final result; they never duplicate branch creation, commit, stash, or retry logic, and they never reinterpret `dirty_tree` as a rebase conflict.

**🛑 STOP TRIGGER — after every compaction event:** the set of contextualized nodes is empty. **NEVER** read or modify product content whose governing spec node has not been contextualized since that compaction, and **NEVER** discuss a node before contextualizing it. Product content is every product artifact a spec node governs or must govern: source, tests, evals, generated output, specs, decisions, coordination notes, and spec-declared configuration. Operational configuration — the `spx/local/` overlays and the exclusion mechanism, read by the skill that declares them without the marker — and the agent harness's own instruction and settings files it is told to read, tool and command output, the session store, and scratch space are not product content. Product content's governing node is found by search under the live foundation marker: a path under `spx/<node>/` belongs to that node; any other path belongs to the node whose `spx/**/tests/` file names it and whose spec links that test, or whose spec or decision names that path in an `[audit]` assertion; several matching nodes resolve to their lowest common ancestor. Product content with no governing spec is not read or modified; record the gap. An operational continuation — PR inspection, check wait, merge, deploy, release, `spx session` operations, occupancy proof — touches no product content and triggers neither `/understand` nor `/contextualize`.

### When creating specs or nodes -> `/author`

Create product decisions (ADRs/PDRs), specs, enabler nodes, outcome nodes.

### When composing or breaking down nodes -> `/decompose`

Compose top-level children with `/decompose spx/`. Decompose an existing node when it has too many assertions (>7), contains independent concerns, or has `PLAN.md`/`ISSUES.md` structure intent.

### When restructuring the tree -> `/refactor`

Move nodes, re-scope assertions, extract shared enablers, consolidate duplicates.

### When checking consistency -> `/align`

Review, audit, or quality check specs. Find contradictions or gaps.

### Before tests, evals, builds, or validation -> `/wait-for-load`

🛑 **STOP TRIGGER — Before any test, eval, build, or validation command, ALWAYS invoke `/wait-for-load`.**
**ALWAYS** wait for `ready: true`, then run the selected command unchanged.
**NEVER** use host load to reduce scope, workers, limits, deadlines, or verification.

### When shipping work to the default branch -> `/merge` (transport dispatcher)

**BLOCKING REQUIREMENT**

Every change destined for the default branch routes through `/merge`, the transport dispatcher — it classifies the changeset, selects the transport, and delegates. `spx/local/merging.md` is the one place repository-specific merge behavior belongs, and it is optional: when absent, `/merge` applies the default lifecycle rather than blocking. Never infer the transport from other docs, and never edit this generated instruction block to change merge behavior. The four authority gates, the delivered-value boundary, and the finding-disposition rule are transport-neutral and live in `/merging-standards`.

## Stop Triggers

Default-branch work is complete only when it reaches the default branch on origin through `/merge` — passing validation, tests, review, or audits is progress, not a stopping point, and an accepted proposal ("yes", "go", "do it") authorizes the whole lifecycle, not a pause. Each trigger below resolves the same way: finish the remaining independent work, then continue through `/commit-changes` and `/merge` until the change reaches the default branch on origin or an explicit lifecycle gate stops.

🛑 **About to summarize after edits, validation, tests, review, or audits passed** — do not conclude.

🛑 **About to report blocked, wait, or ask a question** — first do every action that does not need the answer: edits, verification, branch setup, commit, review. A blocker exists only when all three hold:

- the immediate next action cannot proceed without the operator or an external-state change;
- the local branch already holds every change makeable without the answer;
- the applicable gates have run or produced concrete failing evidence.

🛑 **About to finish on a detached HEAD or stop at a fresh commit** — `git status --short --branch` reporting `## HEAD (no branch)`, or a new local commit, is not an endpoint; create or switch to a local branch preserving the worktree changes, unless the user explicitly limited the task to local-only work.

## Checkpoint Commits

`/commit-changes` may create an atomic local checkpoint whenever a coherent concern is ready to preserve, independent of verification state — never strand dirty work because verification fails or has not run. Record the latest state as `passing`, `failing`, or `not-run`; that state controls later gate dispatch, never commit permission. Run hooks normally, confirm the full `HEAD` changed, and report committed paths, remaining paths, and verification state.

## Commit Before Another Session Reads

Changes may remain uncommitted while the authoring agent session works on them. When repository writes are authorized, commit the exact current version through `/commit-changes` before another agent session or human reads it for collaboration or reusable verification; the commit may record `passing`, `failing`, or `not-run`. After any further change, commit the new version before another such reading. An explicit advisory audit or review may inspect modified or untracked work, but its verdict is not reusable gate evidence. Without repository-write authorization, defer a reading that requires a committed subject. Agentic gate dispatch additionally requires its declared deterministic verification to pass on the exact committed subject.

## Worktree Occupancy

Before treating any worktree as available, run `spx worktree status` and require a live claim for the exact absolute worktree root and current native session. Refresh this proof at session start, after restart or compaction, and immediately before any checkout or worktree transition. A clean tree, detached `HEAD`, branch name, pane title, or absent process in one view never proves availability. When the exact root is absent or claimed by another live session, remain in the assigned worktree and record the ownership issue instead of entering the sibling checkout.

## Git Safety Protocol

```text
ALLOW  git checkout -- README.md
ALLOW  git checkout HEAD -- .
ALLOW  git restore README.md

DENY   git stash drop
DENY   git stash drop stash@{3}
DENY   git stash pop
DENY   git stash pop stash@{0}
DENY   git stash clear
```

## Autonomy Boundary

Default-branch git and version-control mutation — branching, committing, pushing, publishing, merging, and the `/merge` flow's own cleanup of the branches it created — proceeds only inside a governing skill flow, never as a direct command outside one; creating or switching to a local branch to preserve work in progress, and a `--force-with-lease` push to the working branch that flow owns, stay inside it. The `/merge` direct-push transport's publication of a coordination-note-only changeset to the default branch on origin, performed under a held `MERGE_READINESS` with a converged local review, is likewise inside its governing flow. This autonomy never extends to force-pushing a shared or protected ref, deleting a ref no active skill flow authorizes, bypassing commit hooks (`--no-verify`) or commit signing, or any action the Git Safety Protocol forbids; each needs explicit operator instruction in the same turn.

### Sub-agent dispatch

The configured verifier and reviewer roles this router names are pre-authorized. A harness rule may require the operator to request sub-agent use before one is dispatched; treat this section as that standing request. Authorization follows the named role, never a role resemblance.

- **NEVER** ask the operator to confirm dispatching one — not at a gate, not per node, not once per session, and never as a structured-question option set. A harness permission prompt is the operator's to answer, never a question to raise.
- **NEVER** dispatch a sub-agent this router does not name merely because it is discovered, available, or plausibly useful.
- **NEVER** run a verification skill — audit or review — in the main conversation; the separate verifier agent session keeps the verdict free of the authoring agent session's bias.
- **ALWAYS** treat the gate as blocked when a named role cannot be dispatched or does not return: finish the deterministic verification, then report the exact dispatch attempted and how it failed.

### Agent identity in generated artifacts

**NEVER** name the agent or its runtime in an operational artifact — a branch name, commit message, pull-request title or body, review comment, or authorship marker written into a product file. Describe the work, never who performed it. Exact filesystem paths, package and tool names, quoted command output, and operator-supplied text keep their required spelling.

**ALWAYS** confine that ban to operational artifacts. Authored guidance that documents Claude's behavior uses imperative voice or names Claude as its subject by design; stripping Claude from that guidance to satisfy this rule misapplies it rather than complying with it.

### Operator questions

Raise an operator question through AskUserQuestion, never as prose the operator has to answer in free text. Reserve it for an answer that changes what happens next and that no loaded skill, decision, spec, or command output settles — a product-intent conflict a rebase cannot decide, a blocked expense ceiling, or a resolution the evidence leaves genuinely open. Name the exact blocked action, what each option does, and a pause-and-inspect choice.

- **ALWAYS** finish every action that does not depend on the answer first, so the question is the only thing outstanding when it is asked.
- **NEVER** raise one to confirm work already authorized, to report progress, or to choose an option the loaded truth already decides.

## Mutation Status Updates

Before proposing or performing a repository mutation, name:

- the exact target path, PR number, branch ref, or command target;
- the intended action;
- why the action is local enough or gate-authorized enough to proceed;
- the next validation command, review, audit, check wait, or merge gate the action feeds.

Avoid shorthand such as "config patch" or "ship it path" when the exact file, PR state, or command is known. A terse prompt such as "check", "continue", or "ship it" still gets the live state first: full head SHA when a PR exists, current-head review state, required-check state, deployment-readiness and release-readiness rules, and the next autonomous action.

## Quick Reference: Skills and Agents

Skills run in the main conversation. Agents preload the skill and run autonomously in their own agent sessions. Audit agents return structured verdicts; changeset reviewer agents return the raw review journal token for the main conversation to inspect and process through the governing review workflow. Dispatch agents in parallel when auditing multiple targets; `### Sub-agent dispatch` above governs when to dispatch one.

**Use the `Agent` tool for every configured verifier or reviewer.** Launch in the foreground with `subagent_type` set to the exact configured agent type and `prompt` set to the role-task body from the shared contracts below. The completed `Agent` tool result is that configured agent's final message; apply the matching output contract to that message. An error, missing final message, or output outside the matching contract blocks the gate.

**Inspect every successful `changes-reviewer` result through the sealed journal.** Invoke the `spec-tree:project-run-journal` skill and use its `render_review_run.py <run-token>` helper. The helper calls `spx journal render --type review --run <run-token>`, resolves a not-found current-scope miss through `spx journal list --type review --sealed sealed --limit 200`, re-renders with the listed branch slug when exactly one sealed run matches the token, reads the sealed event prefix, and prints the raw token, terminal status, full head/base identity, scope coverage, blocking/debt counts, and any findings through `render_surface(events)`. Treat this as journal inspection; the sealed prefix remains the only review result.

**Configured verifier and reviewer role-task contracts.** Supply only the fields named for the role:

- `changes-reviewer`: the raw scope token — `HEAD`, `origin/<base>...HEAD`, a branch, or a PR reference. Its final message MUST be the raw sealed review-journal run token.
- `implementation-auditor`: repository path, exact committed `<base>..<head>` scope, no live file list for a gating audit, governing node paths, deterministic verification commands and results, the `implementation-auditor` role's six-field run-driver identity, and the task to run the implementation audit through `spx verification run`. Its final message MUST carry the raw run token and rendered projection; only `terminalStatus: approved` passes.
- `test-evidence-auditor`: repository path, governing node, full assertion text or exact spec path plus headings, test-file paths, and the task to audit coupling, falsifiability, alignment, and coverage without weakening the evidence type. Its final message MUST be the `spec-tree:audit-tests` JSON verdict with `schema_version: 1`, `skill: "audit-tests"`, `overall: "APPROVED" | "REJECTED"`, `rows`, and `metadata`, with no prose outside the JSON object. Treat `overall` as authoritative. Malformed JSON, a missing required field, an unexpected `skill`, or an `overall` value outside that vocabulary blocks the gate.
- `eval-evidence-auditor`: repository path, governing node, `[eval]` assertions, all eval artifacts, producer artifacts, and the task to audit real-producer evidence. Its final message MUST be the audit-eval-evidence JSON verdict with overall `PASS`, `FAIL`, or `UNKNOWN` and no prose outside the JSON object.
- `spec-auditor`: repository path, full node path, and the task to audit assertion quality, evidence tags, atemporal voice, decision alignment, and structure. Its final message MUST be the `spec-tree:audit-specs` JSON verdict with `schema_version: 1`, `skill: "audit-specs"`, `overall: "APPROVED" | "REJECTED"`, the `section-structure`, `atemporal-voice`, and `tag-fitness` rows, and `metadata`, with no prose outside the JSON object. Treat `overall` as authoritative. Malformed JSON, a missing required field or row, an unexpected `skill`, or an `overall` value outside that vocabulary blocks the gate.
- `adr-auditor` or `pdr-auditor`: repository path, full decision path, governing node, committed audit scope, and the role's decision-audit task; ADR tasks also carry the language-scope classification. The final message MUST follow that auditor's structured verdict contract without a competing prose envelope.
- `skill-auditor`, when that configured role is installed: repository path, full paths to every changed artifact governing the skill surface — including skill-directory files, authored shared fragments, and generated runtime copies — governing nodes when known, deterministic verification state, and the skill-authoring audit task. Its final message MUST be the `instructions:audit-skill` JSON verdict with `schema_version: 1`, `skill: "audit-skill"`, `overall: "APPROVED" | "REJECTED"`, and the `keep-these-aspects`, `worth-improving`, and `must-fix` rows. Treat `overall` as authoritative. Malformed JSON, a missing required field or row, an unexpected `skill`, or an `overall` value outside that vocabulary blocks the gate.
- A craft plugin's `{plugin}-auditor` — the artifact-type auditor named for the plugin that governs its artifact type, such as a prose plugin's `prose-auditor` — when that configured role is installed: the artifact content or full paths under audit, every classification the owning plugin's audit skill requires as an input, and the audit task that skill declares — consult that skill for its exact required-field list and for its declared output contract, which is one of two shapes. When it declares a structured verdict, the final message MUST be that verdict with no prose outside it; treat `overall` as authoritative, and a malformed verdict, a missing required field, a verdict that does not identify itself as the owning plugin's audit skill, or an `overall` value outside the declared vocabulary blocks the gate. When it declares a sealed-run journal token, the final message MUST be that raw token with no prose outside it; render the sealed run through `spx journal render --type <the skill's declared run type> --run <run-token>` and treat the run's terminal status as authoritative, with only `approved` passing, and a blocked, unsealed, or unrenderable run blocking the gate. A final message that is neither the declared verdict nor the declared token blocks the gate.

- `subagent-auditor`, when that configured role is installed: repository path, exactly one changed subagent configuration path in the active agent harness's native format, governing nodes when known, deterministic verification state, and the subagent-authoring audit task. Multiple changed configurations require separate `subagent-auditor` dispatches, one per path; acquire their handles sequentially and let the role tasks run concurrently. Each final message MUST be the `instructions:audit-subagent` JSON verdict with `schema_version: 1`, `skill: "audit-subagent"`, `overall: "APPROVED" | "REJECTED"`, and the `critical-issues`, `recommendations`, `strengths`, and `quick-fixes` rows. Treat `overall` as authoritative. Malformed JSON, a missing required field or row, an unexpected `skill`, or an `overall` value outside that vocabulary blocks the gate.

| User Says...                                            | Skill                  | Agent                   |
| ------------------------------------------------------- | ---------------------- | ----------------------- |
| "Implement this outcome" or "Start the TDD flow"        | `/apply`               | —                       |
| "Create an outcome" or "Add an ADR"                     | `/author`              | —                       |
| "Add a new node" or "This node is too big"              | `/decompose`           | —                       |
| "Move this under that"                                  | `/refactor`            | —                       |
| "Check these specs"                                     | `/align`               | —                       |
| "Establish evidence for this" or "Write tests for this" | `/verify`              | —                       |
| "Audit this PDR"                                        | `/audit-pdr`           | `pdr-auditor`           |
| "Audit this ADR"                                        | `/audit-adr`           | `adr-auditor`           |
| "Audit test evidence"                                   | `/audit-tests`         | `test-evidence-auditor` |
| "Audit eval evidence"                                   | `/audit-eval-evidence` | `eval-evidence-auditor` |
| "Audit this spec node"                                  | `/audit-specs`         | `spec-auditor`          |
| "Diagnose the spx environment"                          | `/diagnose`            | —                       |
| "File a follow-up in a dependency queue"                | `/issue`               | —                       |

---

## Session Management

Sessions are shared across every worktree. Hand off each session via `/handoff` so it can be resumed from any other worktree: the handoff leaves the worktree clean and persists all state on origin. Propose one when the session's goal is met or the work must pause; resume with `/pickup`. When a claimed session is complete and should leave the active queue, close it through `/handoff` or `/handoff --no-session` so claimed-session accounting archives it. To return a wrongly claimed session to the shared queue instead, run `spx session release <session-id>`.

An explicit request to inspect, archive, or release identified session documents routes directly through the corresponding `spx session` command as operational-state management; `/handoff` is reserved for closing active work through reflection, persistence, continuation disposition, and claimed-session accounting. Direct session operations require `/understand` only before following their output into `spx/`, source, or test content.

<!-- /SPEC-TREE -->

<!-- SPEC-TREE:shared root -->

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
git gc --prune=now           ->  ALLOW
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
test/run.sh          # both suites, with per-suite totals
test/run.sh corpus   # corpus only
test/run.sh -v       # show every case
```

Two suites, because one tool cannot express both:

- **`tests/corpus/`** runs under `dcg corpus`, dcg's own regression
  harness, in the upstream `true_positives` / `false_positives` /
  `bypass_attempts` taxonomy. Each case asserts a `rule_id`. dcg 0.14 still
  marks a wrong-rule denial as passed, so `test/run.sh` independently compares every
  expected rule ID with the current run's actual rule ID. A rejection fixture
  verifies that check. `tests/baseline.json` records the full result.
- **`test/cases/`** covers effective policy and resolved modes through
  `dcg explain`, and which rule claims each custom-pack case through
  `dcg test --config` with the custom-only config and the posix dialect.
  `dcg corpus` evaluates pack matching *without* applying `allowlist.toml` or
  `[policy.rules]`, records every match as `deny`, and has no `--config`
  flag, so an allowlist-dependent ALLOW, a resolved WARN, and attribution
  under a chosen config and dialect do not fit there.

That second point matters if you adopt these packs: **a corpus run alone will
not tell you the allowlist is installed**, and without it the git pack does not
behave as this repo documents. It also will not tell you what the hook does
with a medium-severity rule. A medium rule resolves to WARN — the warning goes
to stderr and the command runs — and the corpus still records `deny` for it.
`core.git:stash-drop` is that rule. This policy accepts the default, and the
`stash_drop` policy row pins `WARN` so a `[policy.rules]` change in either
direction shows up. Before dcg 0.14.4 `dcg explain` reported the rule default
instead of the resolved mode, so an `explain`-based check read DENY while the
hook let the command through.

Attribution under `dcg test --config` does not come from disabling
`core.git`: dcg reinserts the core packs after it applies `disabled`. It comes
from `test/run.sh` comparing the reported rule ID with the expected one, so a
row that a built-in rule claims first fails. A custom rule cannot harden a
built-in either: dcg resolves the mode of the first matching rule and never
reaches a later match, so a critical custom `git stash drop` rule sits behind
the medium built-in and changes nothing.

`dcg pack validate` proves a pack parses, not that a rule still matches. Always
run the matrices. Verified against dcg 0.14.4.

CI runs both suites on every push and pull request. It pins the dcg version and
the release tarball's checksum in
`.github/workflows/deterministic-verification.yml`, because a newer dcg can
change a built-in pack's verdict with no change in this repo, and because
`tests/baseline.json` records the binary that produced it. Bump the version, the
checksum and the baseline together.

## Three things that will trip you up

**dcg hooks your own shell.** A command line containing `git worktree remove`
is blocked *for you*, including when testing the rule that blocks it. That is
why cases live in files and reach dcg through a variable.
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

Active destructive pack patterns anchor to a real command position. Allowlist
patterns anchor to the entire input line, so a neighbouring command cannot
satisfy an exception. Both walk intervening tokens with a bounded character
class. These choices are not cosmetic: `README.md` and `packs/readme.md`
explain the prose-matching and fail-open bugs behind them.

<!-- /SPEC-TREE:shared root -->
