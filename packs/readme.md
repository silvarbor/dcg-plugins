# DCG custom packs

This directory contains two active packs and one disabled historical pack.

```text
packs/
|-- silvarbor.git_safety.worktree_isolated.yaml
|-- silvarbor.access_boundary.yaml
|-- disabled/
|   `-- silvarbor.process_hygiene.yaml
`-- readme.md
```

The dcg `custom_paths` glob loads only the YAML files directly under `packs/`.
Files under `disabled/` are not active.

## Git safety

### Charter

Block only operations that can escape an agent's own worktree and cause
difficult-to-recover damage.

Each worktree has its own HEAD, index, and working tree. All worktrees share
the object store, reflogs, refs, repository configuration, and remotes. Git
also refuses to delete or force-move a branch checked out in another
worktree. A two-worktree test repository verified these properties.

The custom pack is intentionally smaller than a general Git safety pack.
Built-in `core.git` rules continue to cover plain force pushes, stash deletion,
and `git clean -f`.

### Scope

| Operation                                              | Policy               | Reason                                                                       |
| ------------------------------------------------------ | -------------------- | ---------------------------------------------------------------------------- |
| `git worktree remove`                                  | Blocked              | Can delete a peer worktree and uncommitted files                             |
| `git gc --prune=now` or `--prune=all`                  | Blocked              | Immediately destroys shared recovery objects                                 |
| `git prune` without `--dry-run`                        | Blocked              | Removes unreachable objects from the shared store                            |
| immediate `git reflog expire`                          | Blocked              | Removes shared recovery history                                              |
| `git update-ref -d` or `--stdin`                       | Blocked              | Can bypass worktree-aware porcelain checks                                   |
| `git push +<refspec>` or `--mirror`                    | Blocked              | Force-updates remote refs without a lease                                    |
| `git worktree prune`                                   | Allowed              | Removes stale administrative records, not a worktree directory               |
| `git remote remove`, `rm`, or `set-url`                | Allowed              | Recoverable configuration; guarding it caused excessive friction             |
| `git stash pop`                                        | Allowed              | Routine workflow; upstream still guards drop and clear                       |
| `git reset`, path checkout, and restore                | Allowed by allowlist | Affect only the calling worktree                                             |
| `git branch -d` or `-D`                                | Allowed by allowlist | Git protects branches checked out elsewhere and records deletion in a reflog |
| `git push --force-with-lease` or `--force-if-includes` | Allowed              | Verifies remote state before the rewrite                                     |

The upstream pack blocks `git clean -f` even though it is worktree-local.
Untracked files have no object-store recovery path.

### Executable scope and token walking

dcg 0.10 resolves the executable before it applies a custom pattern. Every Git
rule therefore declares `executables: [git]`. Text in another program's stdin
or argument list does not become a Git command merely because it contains a
matching phrase.

Every pattern also starts at a command position. The executable scope rejects
other programs. The anchor rejects a matching phrase inside the scoped
executable's own arguments.

The Git patterns consume global options before they identify the subcommand.
The grammar accepts any option token. Only `-C` and `-c` consume the next shell
token. The grammar accepts quoted values. This structure covers new
zero-argument options without a manual whitelist. It also distinguishes
`git worktree prune` from the top-level `git prune` command.

Each rule then requires its subcommands in their exact grammar positions. A
later argument named `remove`, `set`, `edit`, or `publish` cannot impersonate a
subcommand.

These custom packs guard the command grammar documented here and exercised by
`tests/corpus` and `test/cases`. They do not parse every POSIX spelling of the
same argument vector. dcg 0.10 resolves the executable for scoped rules. Custom
pack patterns still receive raw shell text. Fragmented quoting, escaping, and
unlisted wrapper commands or client options can bypass a rule.

Arguments use a shell-operator-bounded token class rather than `.*` or `\S+`.
One command cannot satisfy a rule or exception in its neighbour.

The assignment, wrapper, and Git-global-option repetitions have no count
ceiling. Earlier ceilings created deterministic bypasses after four
assignments, two wrappers, or 16 Git options.

Assignment chains cover every active rule and every help or heredoc allowlist
pattern. Wrapper chains cover every active rule and every help allowlist
pattern.
Git-option chains cover every Git rule and both Git-specific help forms. Each
chain has 65 entries, and each Git option has a value.

The matrix runs with dcg's enforced budget set to 200 ms. That is stricter than
dcg 0.10's 1,000 ms default.

The chains stay independent because dcg's launcher analysis fails closed on
some combined synthetic prefixes before custom matching. It also fails closed
on a long wrapper chain before a heredoc. Separate cases isolate the repetition
they measure without weakening the live policy.

## Access boundary

This pack covers outward actions whose blast radius does not depend on the
current directory.

| Operation                                                       | Policy                                             |
| --------------------------------------------------------------- | -------------------------------------------------- |
| `gh repo edit --visibility`                                     | Blocked                                            |
| `gh secret set`                                                 | Blocked                                            |
| npm, pnpm, Yarn, Poetry, or Cargo publish                       | Blocked unless a supported dry-run flag is present |
| `twine upload`                                                  | Blocked                                            |
| `gem push`                                                      | Blocked                                            |
| all `gh pr` commands, including `gh pr create` without `--repo` | Allowed                                            |
| `gh secret list` and `gh repo edit` without `--visibility`      | Allowed                                            |

dcg's built-in GitHub pack already covers `gh repo delete`. The custom pack
does not duplicate that rule.

The registry grammar intentionally enumerates leading client options. It is
not a general parser for each package manager.

| Client             | Recognized prefixes before the guarded action                                                                                                             |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| npm                | `--workspace`/`-w`, `--prefix`, `--location`, `--workspaces`, `--include-workspace-root`, and `--global`                                                  |
| pnpm               | `--filter`, `--dir`/`-C`, and `--workspace-root`                                                                                                          |
| Yarn               | `--cwd`                                                                                                                                                   |
| Poetry             | `--directory`/`-C` and `--project`/`-P`                                                                                                                   |
| Cargo              | `+toolchain`, `--color`, `-C`, `--config`, `-Z`, `-V`, `-v`, `-q`, `--version`, `--list`, `--verbose`, `--quiet`, `--locked`, `--offline`, and `--frozen` |
| Twine and RubyGems | none                                                                                                                                                      |

Known-gap cases record ordinary prefixes that remain outside this grammar:
npm, pnpm, and Yarn registry selection, plus Poetry's non-interactive mode.
Those expected `ALLOW` results document the boundary; they do not classify a
publish as safe. Widen a client grammar only with matching deny and dry-run
evidence.

`allowlist.toml` accepts a single-quoted `EOF` heredoc from
`gh pr create --body-file -`. dcg 0.10 does not register this GitHub CLI form
as a structured standard-input data sink. Its legacy launcher detector
therefore reads Markdown code spans that resemble shell commands as local
commands. The exception rejects command substitution before the heredoc. It
also rejects an unquoted delimiter.

Keep PR creation as the only command in that shell tool call. dcg 0.10 does
not inspect a command after a heredoc's end delimiter. `allowlist.toml`
requires the first `EOF` delimiter to end the input. It cannot repair the
separate upstream fail-open.

Every destructive rule declares its executable scope. The `keywords` list
also contains every executable name because dcg evaluates that pre-filter
before any pattern. A missing executable silently makes its ecosystem ALLOW,
even when the regex itself is correct.

## Disabled process-hygiene pack

The repository retains `disabled/silvarbor.process_hygiene.yaml` only as
historical reference. The custom policy does not activate it. The corpus omits
its old cases. The custom policy allows sleep, polling loops, background
timers, and `gh run watch`.

Repeated harness process-exhaustion incidents motivated the pack. Its regex
rules also denied transported command text as if that text executed locally.
That false-positive cost currently outweighs the protection.

If another incident appears, start from its exact command. Use dcg's executable
or parsed-command scope to create the narrowest rule.

## Shared help policy

`allowlist.toml` handles help instead of individual packs. Pack-local safe
patterns cannot override another pack's denial.

The allowlist accepts complete shell `help` commands. It accepts an immediate
`help` subcommand only for the explicitly listed CLIs, including `gh help`.
This limit prevents operand-oriented commands from impersonating help. The
allowlist also accepts an unquoted `--help` after an option-free command path.
Command-specific help patterns allow trailing `--help` after declared options
for guarded GitHub and Git commands. Value-taking options consume a following
`--help` token as data. The help command can end with a known pager pipeline or
final background marker. The allowlist does not absorb redirects or
neighbouring commands, so other dcg rules can still inspect those operations.

The allowlist matches Git global options with declared arity before it
recognizes help. For example, `git -C /repo worktree remove --help` is help. In
`git -C --help worktree remove`, the `-C` option consumes `--help`, so dcg
continues to guard the command.

## Related files

- `../example/config.toml` shows the `custom_paths` and built-in pack setup.
- `../example/allowlist.toml` permits worktree-local Git operations and owns
  the shared help policy.
- `../tests/corpus/` covers native pack matching and asserts rule IDs.
- `../test/cases/worktree_isolated.tsv` covers the effective policy, including
  the allowlist, help behavior, disabled process rules, and `gh pr create`
  without `--repo`.
- `../test/cases/custom_pack.tsv` checks custom Git rule attribution without
  built-in Git pack precedence.

From the repository root, validate the packs. Then run both test suites:

```sh
.github/scripts/validate-packs.sh
test/run.sh
```
