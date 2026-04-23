# Multi-Channel Notification Action

A GitHub Action to send notifications to Slack, Telegram, and Email using [Apprise](https://github.com/caronc/apprise). This action provides beautiful default templates and supports custom templating.

## Features

- **Multi-channel support**: Send to Slack, Telegram, Email, or all of them simultaneously.
- **Dynamic Formatting**: Automatically formats the message with emojis and colors based on workflow status (Success 🟢, Failure 🔴, Cancelled ⚪️, etc.).
- **Custom Templates**: Override default templates with your own custom templates for each channel.
- **Easy Configuration**: Pass a single Apprise URL for each service to keep configuration minimal.

## Usage

You can use this action in your workflows by adding it as a step.

```yaml
name: CI/CD Pipeline
on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Your Build Step
        run: echo "Building..."

      - name: Notify on Completion
        uses: HasanHajHasan/multi-notify@v1
        if: always()
        with:
          status: ${{ job.status }}
          channels: 'slack,telegram'
          slack_url: ${{ secrets.SLACK_APPRISE_URL }}
          telegram_url: ${{ secrets.TELEGRAM_APPRISE_URL }}
```

## Inputs

| Input               | Description                                                                 | Required | Default            |
|---------------------|-----------------------------------------------------------------------------|----------|--------------------|
| `status`            | Job status (`success`, `failure`, `cancelled`, or custom)                   | No       | `failure`          |
| `job_name`          | Name of the job that triggered notification                                 | No       | `${{ github.job }}`|
| `channels`          | Comma-separated list of channels (e.g., `slack,telegram,email`)             | No       | `slack`            |
| `title`             | Custom notification title (overrides default)                               | No       |                    |
| `message`           | Custom message body (overrides default)                                     | No       |                    |
| `slack_template`    | Path to custom Slack template (relative to repo root)                       | No       |                    |
| `telegram_template` | Path to custom Telegram template                                            | No       |                    |
| `email_template`    | Path to custom email template                                               | No       |                    |
| `slack_url`         | Slack apprise URL (e.g., `slack://botname@token1/token2/token3/#channel`)   | No       |                    |
| `telegram_url`      | Telegram apprise URL (e.g., `tgram://bottoken/chatid`)                      | No       |                    |
| `email_url`         | Email apprise URL (e.g., `mailto://user:pass@domain.com`)                   | No       |                    |

## Creating Custom Templates

If you wish to use fully custom templates, you can provide `slack_template`, `telegram_template`, or `email_template`. Your template files can use the following variables which will be dynamically replaced:
- `{EMOJI}`
- `{STATUS}`
- `{TITLE}`
- `{MESSAGE}`
- `{REPOSITORY}`
- `{BRANCH}`
- `{WORKFLOW}`
- `{JOB}`
- `{COMMIT}`
- `{AUTHOR}`
- `{RUN_URL}`

## License
MIT License
