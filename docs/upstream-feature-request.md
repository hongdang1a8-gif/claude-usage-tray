# Góp ý gửi CodeZeno/Claude-Code-Usage-Monitor

Đề xuất hiển thị email của tài khoản đang được đo hạn mức, gửi tới
[CodeZeno/Claude-Code-Usage-Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor/issues).
Đã tìm trong các issue hiện có (ngày 20/11/2026): chưa ai đề xuất nội dung này.

Trạng thái: **soạn xong, chờ gửi** (gửi xong thì dán link issue vào đây và vào README).

---

**Title:** Show the signed-in account email for each Claude Code account

## Problem

The monitor shows usage and reset times, but not *which* Claude account is being measured.
When several logins exist on one PC (work and personal accounts, a `CLAUDE_CONFIG_DIR` profile,
the Claude desktop app vs. the CLI, or WSL), it is hard to confirm that the numbers on the taskbar
belong to the account I am actually using. Account names in **Settings > Providers > Accounts** are
labels I type myself, so they can drift from the real login after I sign out and sign in with a
different account.

## Proposed improvement

Show the account email (and organization name, if any) for each Claude Code account:

- in the tray tooltip or the first line of the tray context menu, e.g. `name@example.com · Team`
- next to each account in **Settings > Providers > Accounts**
- as a theme binding, e.g. `{claude.account.email}` / `{accounts.claude.work.account.email}`

Possible source, with no extra network request: Claude Code writes the signed-in account to
`.claude.json` (in the user's home directory, or inside `CLAUDE_CONFIG_DIR` when that is set),
under `oauthAccount` (`emailAddress`, `organizationName`). Reading only those two fields would be
enough. For the desktop app or when that file is missing, the OAuth profile endpoint used by
Claude Code could be a fallback, but polling it would add requests next to the already
rate-limited usage endpoint, so a local read (or fetching it once per login) seems preferable.

Since emails are personal information, a setting to hide or mask it (e.g. `n***@example.com`)
would help people who share their screen.

Codex accounts could get the same treatment later if their stored login exposes an email.

## Alternatives considered

- Naming each account by hand in Settings: works, but the label is not tied to the actual login
  and goes stale when the login changes.
- Running `/status` in Claude Code to check the account: requires opening a terminal each time.

## Additional context

Teams that share one PC or switch between a company and a personal subscription would benefit most.
