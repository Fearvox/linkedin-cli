# Contributing to linkedin-cli

## Adding New Adapters

Place a YAML file in `adapters/` following the existing adapter format. Required fields: `site`, `name`, `description`, `domain`, `strategy`, `browser`, `args`, `columns`, `pipeline`. Always validate with `--dry-run` before submitting a PR.

## Adding Scoring Dimensions

Edit the Python heredoc in `scripts/prospect.sh` (scoring engine section). Each axis must be normalized 0–5. If your signal shifts the distribution, update tier classification thresholds accordingly.

## Adding Message Templates

Place files in `templates/`. Use `{{variable}}` syntax — supported tokens: `{{first_name}}`, `{{company}}`, `{{mutual_connection}}`, `{{topic}}`. Keep messages professional and specific. Hard limit: 3–7 lines per template.

## PR Requirements

- Run all write operations with `--dry-run` and include output in the PR description
- No credentials, tokens, or API keys anywhere in code or config
- No `leads.jsonl` or personal data files committed
- Follow existing code style: bash scripts with Python heredocs for logic

## Issue Templates

- **Bug**: adapter name + exact command + expected vs actual behavior
- **Feature**: describe the LinkedIn action, proposed adapter or flag, and any edge cases
- **Scoring**: name the signal, explain why it predicts fit, and suggest a weight (0–5)

Questions? Open a discussion before starting large changes.
