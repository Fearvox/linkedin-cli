# Security & Responsible Use Policy

**linkedin-cli** automates LinkedIn outreach via undocumented APIs and browser session cookies.
This document outlines expectations for responsible use, data handling, and security.

---

## Responsible Use Policy

This tool exists for **targeted, professional outreach** — not bulk scraping, spam, or harassment.

- Use it to connect with real prospects you'd genuinely want to talk to.
- Built-in rate limits (3s between API calls, 20 leads/batch max) exist for a reason. Don't bypass them.
- Exercise judgment. If your outreach volume feels aggressive, it probably is.
- You are solely responsible for how you use this tool and for compliance with LinkedIn's Terms of Service.

## LinkedIn Terms of Service

Automated access to LinkedIn may violate their [User Agreement](https://www.linkedin.com/legal/user-agreement).

- The author acknowledges this risk and does not encourage ToS violations.
- **You accept all risk** of account restrictions, bans, or legal action from LinkedIn.
- This tool is provided as-is. No warranties, express or implied.

## Data Privacy

All data stays on your machine. Nothing phones home.

- Scraped leads are stored locally in `data/leads.jsonl`.
- No data is sent to third-party services, analytics, or remote servers.
- `leads.jsonl` is gitignored — **never commit personal data to version control**.
- You must handle scraped data responsibly under applicable privacy laws (GDPR, CCPA, etc.).
- If someone asks you to delete their data, do it.

## Security Practices

- **No credentials stored.** Authentication uses your existing browser session cookie.
- **No API keys or tokens in code.** Nothing to leak.
- Always run `--dry-run` before any live operation to preview what will happen.
- The **human review gate is mandatory** — you confirm every action before it executes.
- Review `data/leads.jsonl` before sending connection requests or messages.

## Reporting Vulnerabilities

If you discover a security vulnerability:

- **Email:** [nolan@0xvox.com](mailto:nolan@0xvox.com)
- **Do not** open public GitHub issues for security vulnerabilities.
- Allow reasonable time for a response before any public disclosure.

## Disclaimer

This project is licensed under [CC BY-NC-ND 4.0](LICENSE). No commercial use, no derivatives.

- The author assumes **no liability** for how this tool is used.
- No warranty of any kind — fitness, merchantability, or otherwise.
- **Use at your own risk.**

---

See also: [README](README.md) · [CONTRIBUTING](CONTRIBUTING.md) · [LICENSE](LICENSE)

[↑ Back to top](#security--responsible-use-policy)
