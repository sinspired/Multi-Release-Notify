# Multi Release Notify

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Multi--Release%20Notify-blue?logo=github)](https://github.com/marketplace/actions/multi-release-notify)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Send release and CI/CD notifications to **Slack, Telegram, Email, Bark, Ntfy, DingTalk**,
or any of the [100+ channels Apprise supports](https://github.com/caronc/apprise/wiki) —
with format-optimized built-in templates and zero manual configuration.

---

## Features

- **Release-aware** — first-class support for `release: [published]` events; auto-generates
  titles like `owner/repo updated to v1.2.0`
- **Auto-generate release notes** — if no `release_notes` is provided, automatically generates
  commit messages from the previous tag to HEAD (subject-only, no hashes)
- **Automatic format injection** — HTML for Email & Telegram, Markdown for Ntfy / Slack /
  DingTalk, plain text for Bark; set per-channel automatically, no configuration needed
- **URL decoration** — injects `icon`, `group`, `tags`, `avatar_url`, and `from` into
  Apprise URLs per scheme, only when not already set
- **Generic fallback** — pass any Apprise URL via `urls` to reach services not listed above
  (Discord, Pushover, Gotify, Matrix, and more)
- **Custom templates** — override any built-in template with your own file in your repo
- **Failsafe title** — auto-generates `repo updated to v1.2.0` or `repo updated to v1.2.0 — failed`

---

## Quick Start

### Release notification

```yaml
name: Release Notification
on:
  release:
    types: [published]

jobs:
  notify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Required for git tag detection
      - uses: sinspired/multi-release-notify@v1
        with:
          channels:      email,telegram,bark
          email_url:     ${{ secrets.EMAIL_APPRISE_URL }}
          telegram_url:  ${{ secrets.TELEGRAM_APPRISE_URL }}
          bark_url:      ${{ secrets.BARK_APPRISE_URL }}
```

### Manual trigger with custom inputs

Manually dispatch the workflow with custom channels or URLs:

```yaml
name: Release Notification
on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      channels:
        description: "Notification channels (email,telegram,slack,etc.) — optional if urls provided"
        required: false
      urls:
        description: "Generic Apprise URLs (comma or newline separated) — optional if channels provided"
        required: false

jobs:
  notify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: sinspired/multi-release-notify@v1
        with:
          channels:      ${{ inputs.channels }}
          urls:          ${{ inputs.urls }}
          email_url:     ${{ secrets.EMAIL_APPRISE_URL }}
          telegram_url:  ${{ secrets.TELEGRAM_APPRISE_URL }}
          slack_url:     ${{ secrets.SLACK_APPRISE_URL }}
```

### CI/CD status notification

```yaml
- uses: sinspired/multi-release-notify@v1
  if: always()
  with:
    status:      ${{ job.status }}
    channels:    slack
    slack_url:   ${{ secrets.SLACK_APPRISE_URL }}
```

### Any Apprise-supported channel (generic fallback)

```yaml
- uses: sinspired/multi-release-notify@v1
  with:
    version:     ${{ github.event.release.tag_name }}
    release_url: ${{ github.event.release.html_url }}
    urls: |
      discord://webhook_id/webhook_token
      gotify://hostname/token
      pushover://user_key/app_token
```

---

## Inputs

### Core

| Input | Description | Default |
|-------|-------------|---------|
| `status` | `success`, `failure`, `cancelled`, `released`, or any string | `released` |
| `channels` | Comma-separated: `email`, `telegram`, `bark`, `ntfy`, `slack`, `dingtalk` | (optional if `urls` provided) |
| `urls` | Generic fallback: any Apprise URL(s), comma- or newline-separated | (optional if `channels` provided) |
| `title` | Custom title. Auto-generated from repo + version if omitted. | |
| `message` | Custom body. Uses `release_notes` if omitted. | |
| `icon_url` | Icon URL injected into Bark, Ntfy, and Discord URLs | GitHub logo |

### Release metadata

| Input | Description |
|-------|-------------|
| `version` | Tag name, e.g. `v1.2.0` |
| `release_url` | URL to the GitHub Release page |
| `release_notes` | Release body / changelog |
| `author` | Publisher username (defaults to `github.actor`) |

### Channel URLs

| Input | Apprise URL format |
|-------|-------------------|
| `email_url` | `mailtos://user:pass@smtp.example.com?to=dest@example.com` |
| `telegram_url` | `tgram://bottoken/chatid` |
| `bark_url` | `bark://device_key@api.day.app` |
| `ntfy_url` | `ntfy://topic` or `ntfys://user:pass@host/topic` |
| `slack_url` | `slack://xoxb-token/#channel` |
| `dingtalk_url` | `dingtalk://access_token` |

### Custom template paths

Paths are relative to your repository root. When omitted, the built-in template is used.

| Input | Format |
|-------|--------|
| `email_template` | HTML |
| `telegram_template` | Telegram HTML subset |
| `bark_template` | Plain text |
| `ntfy_template` | Markdown |
| `slack_template` | Markdown |
| `dingtalk_template` | Markdown |

---

## Channel format reference

| Channel | Format sent | Rendered by |
|---------|-------------|-------------|
| Email | Full HTML + CSS | Email client |
| Telegram | HTML subset (`<b>` `<code>` `<pre>` `<a>`) | Telegram client |
| Slack | Markdown → mrkdwn (auto-converted) | Slack client |
| Ntfy | Markdown | ntfy client |
| DingTalk | Markdown | DingTalk client |
| Bark | Plain text | iOS Notification Center |
| Generic `urls` | Plain text | Service-dependent |

---

## Template variables

| Variable | Description |
|----------|-------------|
| `{TITLE}` | Auto-generated or custom title |
| `{MESSAGE}` | Body / release notes |
| `{STATUS}` | Lowercase status: `released`, `failure`, etc. |
| `{STATUS_TEXT}` | Display label: `Released`, `Failed`, etc. |
| `{REPOSITORY}` | `owner/repo` |
| `{AUTHOR}` | Publisher username |
| `{VERSION}` | Release tag, e.g. `v1.2.0` |
| `{RELEASE_URL}` | GitHub Release page URL |
| `{RELEASE_NOTES}` | Raw release body text |

---

## Custom template example

Create `.github/templates/telegram.html` in **your** repo:

```html
<b>{TITLE}</b>

<code>{VERSION}</code>  ·  {REPOSITORY}
by {AUTHOR}

<b>Release Notes</b>
<pre>{MESSAGE}</pre>

<a href="{RELEASE_URL}">View on GitHub →</a>
```

Then pass the path:

```yaml
- uses: sinspired/multi-release-notify@v1
  with:
    telegram_url:      ${{ secrets.TELEGRAM_APPRISE_URL }}
    telegram_template: .github/templates/telegram.html
    version:           ${{ github.event.release.tag_name }}
    release_url:       ${{ github.event.release.html_url }}
```

---

## Setting up secrets

Go to **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Example value |
|--------|---------------|
| `EMAIL_APPRISE_URL` | `mailtos://user:pass@smtp.gmail.com?to=you@example.com` |
| `TELEGRAM_APPRISE_URL` | `tgram://bot_token/chat_id` |
| `BARK_APPRISE_URL` | `bark://api.day.app/device_token` |
| `NTFY_APPRISE_URL` | `ntfy://your-topic` |
| `SLACK_APPRISE_URL` | `slack://xoxb-token/#general` |
| `DINGTALK_APPRISE_URL` | `dingtalk://your_access_token` |

Full URL reference: [Apprise Wiki](https://github.com/caronc/apprise/wiki)

---

## License

MIT License — see [LICENSE](LICENSE) for details.
