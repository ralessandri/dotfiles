# AGENTS.md

## Hard Rules

- Never print, log, or quote secret contents; reference by path only. This covers `.env`, `.ssh/config`, credential/token files, `*.pem`, `*token*`, `*secret*`, `id_rsa*`, and `*.key`.
- Never execute `setup/tasks/*.sh`, even with approval; only static validation is allowed. During review, flag `dnf install`/`dnf remove`, `systemctl`, and firmware actions.
- Run `git add` only with explicit approval; never create commits. The user manually invokes `dotfiles/.local/bin/ai-commit.sh` for commit conventions.
- Do not run GNU Stow unless explicitly requested. Do not modify ignored files or binary assets in `theme/backgrounds` or `theme/icons` unless explicitly requested.

## Scope

- Personal dotfiles, theme assets, and Fedora setup automation.
- `dotfiles/` contains managed configuration and command-line utilities; `setup/` contains Just recipes and Fedora task scripts.

## Working Guidelines

- Make focused changes; preserve user changes and avoid unrelated reformatting. Plan multi-file or multi-step work unless it is one clear edit in one file.
- Do not split, merge, or restructure scripts without first proposing the change and obtaining explicit approval.
- Explicit approval is an affirmative confirmation of a specific action in the current turn; prior approval for similar work does not carry over.
- The following commands form the complete no-approval allow-list only in read-only/static-validation mode, without write-capable flags, actions, or shell escapes: `cat`, `grep`, `rg`, `find`, `sed`, `awk`, `git diff`, `git status`, `git log`, `git show`, `bash -n`, `shellcheck`, `shfmt -d`, and `just --list`, including `just --justfile setup/justfile --list`.
- Allow-list membership applies to the exact invocation, not the command name. A listed command with a state-changing flag, option, or subaction is excluded and requires approval under the next rule; for example, `sed -i`, `find ... -delete`, or a writing `find ... -exec`.
- Any invocation not covered by that allow-list that writes, modifies, deletes, or installs requires explicit approval, including a validation command such as `shfmt -w`; ask instead if a check needs one. Deletion also requires separate confirmation naming exact paths.
- During execution, implement only the approved plan. Do not fix, refactor, or touch additional findings, even if minor or clearly correct; report them as noticed but not addressed and propose them separately for approval.
- Current-turn instructions override this document except the secrets and `setup/tasks/*.sh` rules above.
- Match existing non-Bash formatting; do not introduce a new style. Changes to this file need explicit approval and must be called out when proposed.

## Bash Script Style

- Use `#!/usr/bin/env bash` and `set -euo pipefail`. New scripts in `dotfiles/.local/bin/` and `setup/tasks/` must be executable; preserve their executable bit.
- Keep scripts single-purpose. A script is substantial if it has more than 50 lines or at least two independently changeable responsibilities. Substantial scripts use clear English sections for configuration, helpers, domain workflows, option parsing, and command dispatch.
- A substantial script that parses options must support `--help`: print a concise purpose, options, and optional example to stdout, then exit 0. Check `--help` and optional `--version` before prerequisites or other logic; add `--version` only for a meaningful maintained value. Simple single-purpose scripts need neither option solely for this rule.
- Keep functions focused. Add English comments only when names do not make purpose, inputs, side effects, or failure behavior clear. Prefer self-explanatory code and avoid obvious what-comments. Preserve and add why-comments for workarounds, Fedora/package constraints, and ordering dependencies; do not remove them as boilerplate unless requested. Do not add file-header blocks; convey purpose through the file name, structure, and `--help`.
- Follow `.editorconfig`; use 2-space indentation and no tabs. Quote expansions as `"${variable}"`; use `$(...)`, `[[ ... ]]`, and arrays for argument lists.
- Use `lower_snake_case` for functions and locals; reserve uppercase for constants. Prefix internal helpers with `_`. For an existing helper, call out the required rename and get approval; then apply it consistently within the approved scope. Exclude executable entry points, tool/Just entry points, aliases, and interactive shell functions. `_` documents intent only; Bash has no true visibility.
- Use `printf` for user messages; send errors to stderr and exit non-zero. Terminal section headers use `:: ` followed by a blank line, for example `printf ':: %s\n\n' "Heading"`; do not use this for status or error messages.
- Validate genuinely variable prerequisites before changes, make reruns safe where practical, avoid `eval`, and avoid prompts unless a user choice is required.

## Interactive UI (gum / fzf)

- Prefer `gum` and `fzf` over raw `read` or `select` when they improve prompts, lists, or confirmations. They are guaranteed available: add no checks or fallbacks.
- Do not hardcode colors, styles, hex codes, or ANSI values. Reference global Matugen theme values; if their script-facing source is unknown, report it as an open item rather than guess.
- Keep UI direct for this fixed personal setup: no TTY or portability overhead. Other Bash rules, including variable-prerequisite validation and `_` naming, still apply. These rules concern terminal UX, not agent approval.

## Validation

- No test suite or CI is versioned. Do not introduce test infrastructure unless requested; use relevant validation below.
- For changed Bash scripts, run `bash -n`, `shfmt -d`, and `shellcheck` when available. Do not install missing `shfmt` or `shellcheck`; report absence.
- For changed Just recipes, run `just --justfile setup/justfile --list`; report an unavailable `just` rather than install it.
- Apply `shfmt` changes only with current-turn formatting approval. Report `shellcheck` findings; fix them only with approval, except pure formatting.
- In the final report, include only applicable sections: changes made (one line per file), validation by tool and result, anything unverified and why, assumptions made, and noticed but not addressed.
