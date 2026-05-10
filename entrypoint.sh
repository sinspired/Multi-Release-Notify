#!/usr/bin/env bash
# =============================================================================
# Multi-Channel Notification — entrypoint.sh
# Handles: status mapping · title generation · URL decoration ·
#          per-channel format injection · template rendering · generic fallback
# =============================================================================
set -euo pipefail

# ─── Inputs ───────────────────────────────────────────────────────────────────
STATUS="${INPUT_STATUS:-released}"
CHANNELS="${INPUT_CHANNELS:-}"
URLS_INPUT="${INPUT_URLS:-}"
VERSION="${INPUT_VERSION:-}"
RELEASE_URL="${INPUT_RELEASE_URL:-}"
RELEASE_NOTES="${INPUT_RELEASE_NOTES:-}"
REPOSITORY="${GITHUB_REPOSITORY:-unknown/repo}"
AUTHOR="${INPUT_AUTHOR:-${GITHUB_ACTOR:-unknown}}"
ICON_URL="${INPUT_ICON_URL:-https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png}"

# ─── Guard: require at least one destination ──────────────────────────────────
if [[ -z "${CHANNELS}" && -z "${URLS_INPUT}" ]]; then
  echo "::error::No destination configured. Set 'channels' and/or 'urls'."
  exit 1
fi

# ─── Status → display text + Apprise notify-type ──────────────────────────────
case "${STATUS,,}" in
  success|released) STATUS_TEXT="Released";  NOTIFY_TYPE="success" ;;
  failure|failed)   STATUS_TEXT="Failed";    NOTIFY_TYPE="failure" ;;
  cancelled)        STATUS_TEXT="Cancelled"; NOTIFY_TYPE="warning" ;;
  *)                STATUS_TEXT="${STATUS}";  NOTIFY_TYPE="info"    ;;
esac

# ─── Title: auto-generate from repo + version unless overridden ───────────────
if [[ -n "${INPUT_TITLE:-}" ]]; then
  TITLE="${INPUT_TITLE}"
elif [[ "${NOTIFY_TYPE}" == "failure" ]]; then
  TITLE="${REPOSITORY} updated to ${VERSION} — failed"
else
  TITLE="${REPOSITORY} updated to ${VERSION}"
fi

# ─── Message body ─────────────────────────────────────────────────────────────
MESSAGE="${INPUT_MESSAGE:-${RELEASE_NOTES:-No release notes provided.}}"

# ─── URL decoration ───────────────────────────────────────────────────────────
# Injects icon, group, tags, avatar_url, and from= per channel scheme.
# Never overwrites parameters the user has already set.
decorate_url() {
  local url="$1"
  local icon="$2"
  local scheme
  scheme=$(echo "$url" | sed 's|://.*||' | tr '[:upper:]' '[:lower:]')
  local sep
  [[ "$url" == *"?"* ]] && sep="&" || sep="?"

  local encoded_icon
  encoded_icon=$(python3 -c \
    "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" \
    "$icon")

  case "$scheme" in
    bark*)
      [[ "$url" != *"icon="*  ]] && url="${url}${sep}icon=${encoded_icon}" && sep="&"
      [[ "$url" != *"group="* ]] && url="${url}${sep}group=GitHub_Release"
      ;;
    ntfy*)
      [[ "$url" != *"avatar_url="* ]] && url="${url}${sep}avatar_url=${encoded_icon}" && sep="&"
      if [[ "$url" != *"tags="* ]]; then
        url="${url}${sep}tags=GitHub_Release"
        sep="&"
      else
        # Append tag without replacing existing ones
        url=$(echo "$url" | sed 's/\(tags=[^&]*\)/\1,GitHub_Release/')
      fi
      [[ "$url" != *"format="* ]] && url="${url}${sep}format=markdown"
      ;;
    discord)
      [[ "$url" != *"avatar="*     ]] && url="${url}${sep}avatar=yes"              && sep="&"
      [[ "$url" != *"avatar_url="* ]] && url="${url}${sep}avatar_url=${encoded_icon}"
      ;;
    mailto|mailtos)
      [[ "$url" != *"from="* ]] && url="${url}${sep}from=GitHub_Actions"
      ;;
  esac

  echo "$url"
}

# ─── Template rendering ────────────────────────────────────────────────────────
# Substitutes all {PLACEHOLDERS} using Python to safely handle
# multi-line values, slashes, and special characters that break sed.
render_template() {
  local tpl_file="$1"
  TITLE="$TITLE"           \
  MESSAGE="$MESSAGE"       \
  STATUS="${STATUS,,}"     \
  STATUS_TEXT="$STATUS_TEXT" \
  REPOSITORY="$REPOSITORY" \
  AUTHOR="$AUTHOR"         \
  VERSION="$VERSION"       \
  RELEASE_URL="$RELEASE_URL" \
  RELEASE_NOTES="$RELEASE_NOTES" \
  python3 - "$tpl_file" <<'PYEOF'
import sys, os

with open(sys.argv[1], 'r') as f:
    content = f.read()

for placeholder, env_key in {
    '{TITLE}':         'TITLE',
    '{MESSAGE}':       'MESSAGE',
    '{STATUS}':        'STATUS',
    '{STATUS_TEXT}':   'STATUS_TEXT',
    '{REPOSITORY}':    'REPOSITORY',
    '{AUTHOR}':        'AUTHOR',
    '{VERSION}':       'VERSION',
    '{RELEASE_URL}':   'RELEASE_URL',
    '{RELEASE_NOTES}': 'RELEASE_NOTES',
}.items():
    content = content.replace(placeholder, os.environ.get(env_key, ''))

print(content, end='')
PYEOF
}

# ─── Send one channel ──────────────────────────────────────────────────────────
# Each named channel automatically receives the correct --input-format value
# (foolproof design — users never need to configure this manually).
send_channel() {
  local label="$1"        # human-readable name for log output
  local raw_url="$2"      # Apprise URL before decoration
  local user_tpl="$3"     # user-supplied template path (repo-relative, may be empty)
  local fmt="$4"          # --input-format: text | html | markdown
  local builtin_tpl="$5"  # absolute path to built-in fallback template

  [[ -z "$raw_url" ]] && {
    echo "⚠  [${label}] Skipped — no URL configured."
    return 0
  }

  # Prefer user's custom template if it exists in their workspace
  local tpl_file
  if [[ -n "$user_tpl" && \
        -f "${GITHUB_WORKSPACE:-/github/workspace}/${user_tpl}" ]]; then
    tpl_file="${GITHUB_WORKSPACE:-/github/workspace}/${user_tpl}"
    echo "📄 [${label}] Using custom template: ${user_tpl}"
  else
    tpl_file="$builtin_tpl"
  fi

  local body
  body=$(render_template "$tpl_file")

  local url
  url=$(decorate_url "$raw_url" "$ICON_URL")

  echo "📤 [${label}] Sending..."
  if apprise \
      --title        "${TITLE}" \
      --body         "${body}"  \
      --input-format "${fmt}"   \
      --notification-type  "${NOTIFY_TYPE}" \
      "${url}"; then
    echo "✅ [${label}] Sent."
  else
    echo "::error::[${label}] Failed. Verify the URL and credentials."
    return 1
  fi
}

# ─── Named channel dispatch ────────────────────────────────────────────────────
# Format mapping (automatic, per-channel):
#   email, telegram → html      (rich rendering)
#   ntfy, slack, dingtalk → markdown
#   bark → text                 (iOS push — no markup support)
TDIR="/templates"

if [[ -n "${CHANNELS}" ]]; then
  IFS=',' read -ra CHANNEL_LIST <<< "${CHANNELS}"
  for ch in "${CHANNEL_LIST[@]}"; do
    ch=$(echo "$ch" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    case "$ch" in
      email)
        send_channel "Email"    "${INPUT_EMAIL_URL:-}"    \
                     "${INPUT_EMAIL_TEMPLATE:-}"    "html"     "${TDIR}/email.html"    ;;
      telegram)
        send_channel "Telegram" "${INPUT_TELEGRAM_URL:-}" \
                     "${INPUT_TELEGRAM_TEMPLATE:-}" "html"     "${TDIR}/telegram.html" ;;
      bark)
        send_channel "Bark"     "${INPUT_BARK_URL:-}"     \
                     "${INPUT_BARK_TEMPLATE:-}"     "text"     "${TDIR}/bark.txt"      ;;
      ntfy)
        send_channel "Ntfy"     "${INPUT_NTFY_URL:-}"     \
                     "${INPUT_NTFY_TEMPLATE:-}"     "markdown" "${TDIR}/ntfy.md"       ;;
      slack)
        send_channel "Slack"    "${INPUT_SLACK_URL:-}"    \
                     "${INPUT_SLACK_TEMPLATE:-}"    "markdown" "${TDIR}/slack.md"      ;;
      dingtalk)
        send_channel "DingTalk" "${INPUT_DINGTALK_URL:-}" \
                     "${INPUT_DINGTALK_TEMPLATE:-}" "markdown" "${TDIR}/dingtalk.md"   ;;
      *)
        echo "⚠  Unknown channel: '${ch}'. Use the 'urls' input for unlisted services."
        ;;
    esac
  done
fi

# ─── Generic Apprise URLs — any service Apprise supports ──────────────────────
# Sends plain text for maximum cross-service compatibility.
# URL decoration (icon, group, tags) is still applied per scheme.
if [[ -n "${URLS_INPUT}" ]]; then
  echo "─── Generic URLs ────────────────────────────────────────────────"

  generic_body="${MESSAGE}

${RELEASE_URL}"

  while IFS= read -r raw_url; do
    raw_url=$(echo "$raw_url" | tr -d ' ,')
    [[ -z "$raw_url" ]] && continue

    local_scheme="${raw_url%%://*}"
    url=$(decorate_url "$raw_url" "$ICON_URL")

    fmt="text"
    case "${local_scheme,,}" in
      ntfy*|slack*|dingtalk*|mattermost*|matrix*|rocket*|discord*|telegram)
        fmt="markdown"
        ;;
      email|mailto|mailtos)
        fmt="html"
        ;;
      bark*)
        fmt="text"
        ;;
    esac

    echo "📤 [generic:${local_scheme}] Sending..."
    if apprise \
        --title        "${TITLE}"        \
        --body         "${generic_body}" \
        --input-format "${fmt}"            \
        --notification-type  "${NOTIFY_TYPE}"  \
        "${url}"; then
      echo "✅ [generic:${local_scheme}] Sent."
    else
      echo "::error::[generic:${local_scheme}] Failed. See Apprise docs for URL format."
    fi
  done < <(echo "${URLS_INPUT}" | tr ',' '\n')
fi

echo "──────────────────────────────────────────────────────────────────"
echo "✅ All notifications processed."