#!/usr/bin/env bash
# =============================================================================
# Multi-Channel Notification — entrypoint.sh
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
# 修复核心 Bug：获取当前 Action 的正确绝对路径
ACTION_PATH="${GITHUB_ACTION_PATH:-.}"

# ─── Guard: require at least one destination ──────────────────────────────────
if [[ -z "${CHANNELS}" && -z "${URLS_INPUT}" ]]; then
  if [[ "${GITHUB_EVENT_NAME:-}" == "workflow_dispatch" ]]; then
    CHANNELS="email,telegram,ntfy,slack"
    echo "ℹ️  Using default channels for manual trigger: ${CHANNELS}"
  else
    echo "::error::No destination configured. Set 'channels' and/or 'urls'."
    exit 1
  fi
fi

# ─── VERSION: resolve with priority chain ─────────────────────────────────────
if [[ -z "${VERSION}" ]]; then
  GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  if [[ -n "${GIT_TAG}" ]]; then
    VERSION="${GIT_TAG}"
    echo "ℹ️  VERSION auto-detected from git tag: ${VERSION}"
  elif [[ "${GITHUB_REF:-}" =~ ^refs/tags/ ]]; then
    VERSION="${GITHUB_REF#refs/tags/}"
    echo "ℹ️  VERSION taken from GITHUB_REF tag: ${VERSION}"
  elif [[ "${GITHUB_REF:-}" =~ ^refs/heads/ ]]; then
    VERSION="${GITHUB_REF#refs/heads/}"
    echo "⚠️  No git tags found — VERSION falls back to branch: ${VERSION}"
  else
    VERSION="${GITHUB_REF:-unknown}"
  fi
fi

# ─── Status ───────────────────────────────────────────────────────────────────
case "${STATUS,,}" in
  success|released) STATUS_TEXT="Released";  NOTIFY_TYPE="success" ;;
  failure|failed)   STATUS_TEXT="Failed";    NOTIFY_TYPE="failure" ;;
  cancelled)        STATUS_TEXT="Cancelled"; NOTIFY_TYPE="warning" ;;
  *)                STATUS_TEXT="${STATUS}"; NOTIFY_TYPE="info"    ;;
esac

# ─── Title ────────────────────────────────────────────────────────────────────
if [[ -n "${INPUT_TITLE:-}" ]]; then
  TITLE="${INPUT_TITLE}"
elif [[ "${NOTIFY_TYPE}" == "failure" ]]; then
  TITLE="${REPOSITORY} updated to ${VERSION} — failed"
else
  TITLE="${REPOSITORY} updated to ${VERSION}"
fi

# ─── Release notes ────────────────────────────────────────────────────────────
if [[ -z "${INPUT_MESSAGE:-}" ]] && [[ -z "${RELEASE_NOTES}" ]]; then
  PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
  # 添加 --no-merges 排除 PR 合并记录，使 changelog 更清晰
  if [[ -n "${PREV_TAG}" ]]; then
    RAW_LOG=$(git log --no-merges --pretty=format:"%s" "${PREV_TAG}..HEAD" 2>/dev/null || echo "")
    [[ -n "${RAW_LOG}" ]] && RELEASE_NOTES=$(echo "${RAW_LOG}" | sed 's/^/· /') || RELEASE_NOTES="No new commits since ${PREV_TAG}."
  else
    RAW_LOG=$(git log --no-merges --pretty=format:"%s" 2>/dev/null | head -20 || echo "")
    [[ -n "${RAW_LOG}" ]] && RELEASE_NOTES=$(echo "${RAW_LOG}" | sed 's/^/· /')
  fi
fi

MESSAGE="${INPUT_MESSAGE:-${RELEASE_NOTES:-No release notes provided.}}"

# ─── URL decoration ───────────────────────────────────────────────────────────
decorate_url() {
  local url="$1"
  local icon="$2"
  local scheme sep encoded_icon
  
  scheme=$(echo "$url" | sed 's|://.*||' | tr '[:upper:]' '[:lower:]')
  [[ "$url" == *"?"* ]] && sep="&" || sep="?"
  
  encoded_icon=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$icon")

  case "$scheme" in
    bark*)
      [[ "$url" != *"icon="*  ]] && url="${url}${sep}icon=${encoded_icon}" && sep="&"
      [[ "$url" != *"group="* ]] && url="${url}${sep}group=GitHub_Release" ;;
    ntfy*)
      [[ "$url" != *"avatar_url="* ]] && url="${url}${sep}avatar_url=${encoded_icon}" && sep="&"
      if [[ "$url" != *"tags="* ]]; then
        url="${url}${sep}tags=GitHub_Release" && sep="&"
      else
        url=$(echo "$url" | sed 's/\(tags=[^&]*\)/\1,GitHub_Release/')
      fi
      [[ "$url" != *"format="* ]] && url="${url}${sep}format=markdown" ;;
    discord)
      [[ "$url" != *"avatar="*     ]] && url="${url}${sep}avatar=yes" && sep="&"
      [[ "$url" != *"avatar_url="* ]] && url="${url}${sep}avatar_url=${encoded_icon}" ;;
    mailto|mailtos)
      [[ "$url" != *"from="* ]] && url="${url}${sep}from=GitHub_Actions" ;;
  esac
  echo "$url"
}

# ─── Python Markdown Converter Helper ──────────────────────────────────────────
# 提取公用逻辑，避免代码重复
convert_markdown() {
  python3 -c '
import sys, re
text = sys.stdin.read()
is_md = bool(re.search(r"(\*\*.*?\*\*|__.*?__|#+\s|-\s|\*\s|`.*?`|!\[.*?\]\(.*?\)|\[.*?\]\(.*?\))", text))
if not is_md:
    print(text, end="")
    sys.exit(0)
try:
    import markdown
    print(markdown.markdown(text, extensions=["extra", "codehilite"]), end="")
except ImportError:
    text = re.sub(r"\*\*(.*?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"\*(.*?)\*", r"<i>\1</i>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"```([^`]+)```", r"<pre>\1</pre>", text, flags=re.DOTALL)
    text = re.sub(r"^\s*-\s+(.*)$", r"<li>\1</li>", text, flags=re.MULTILINE)
    text = re.sub(r"(?m)^(\d+)\.\s+(.*)$", r"<li>\1. \2</li>", text)
    text = re.sub(r"\n\n+", r"</p><p>", text)
    print(f"<p>{text}</p>", end="")
' <<< "$1"
}

# ─── Template rendering ────────────────────────────────────────────────────────
render_template() {
  local tpl_file="$1"
  local fmt="$2"
  
  # 处理 {MESSAGE} 内容格式
  local processed_msg="$MESSAGE"
  if [[ "$fmt" == "html" ]]; then
    processed_msg=$(convert_markdown "$MESSAGE")
  fi

  TITLE="$TITLE" MESSAGE="$processed_msg" STATUS="${STATUS,,}" STATUS_TEXT="$STATUS_TEXT" \
  REPOSITORY="$REPOSITORY" AUTHOR="$AUTHOR" VERSION="$VERSION" RELEASE_URL="$RELEASE_URL" RELEASE_NOTES="$RELEASE_NOTES" \
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
send_channel() {
  local label="$1" raw_url="$2" user_tpl="$3" fmt="$4" builtin_tpl="$5"

  [[ -z "$raw_url" ]] && { echo "⚠  [${label}] Skipped — no URL configured."; return 0; }

  local tpl_file
  if [[ -n "$user_tpl" && -f "${GITHUB_WORKSPACE:-/github/workspace}/${user_tpl}" ]]; then
    tpl_file="${GITHUB_WORKSPACE:-/github/workspace}/${user_tpl}"
    echo "📄 [${label}] Using custom template: ${user_tpl}"
  else
    tpl_file="$builtin_tpl"
  fi

  local body url
  body=$(render_template "$tpl_file" "$fmt")
  url=$(decorate_url "$raw_url" "$ICON_URL")

  echo "📤 [${label}] Sending..."
  # 修复：统一使用 python3 -m apprise，防止直接调用 apprise 时环境变量找不到的情况
  if python3 -m apprise --title "${TITLE}" --body "${body}" --input-format "${fmt}" --notification-type "${NOTIFY_TYPE}" "${url}"; then
    echo "✅ [${label}] Sent."
  else
    echo "::error::[${label}] Failed. Verify the URL and credentials."
    return 1
  fi
}

# ─── Named channel dispatch ────────────────────────────────────────────────────
# 修复核心 Bug：使用 Action 相对路径
TDIR="${ACTION_PATH}/templates"

if [[ -n "${CHANNELS}" ]]; then
  IFS=',' read -ra CHANNEL_LIST <<< "${CHANNELS}"
  for ch in "${CHANNEL_LIST[@]}"; do
    ch=$(echo "$ch" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    case "$ch" in
      email)    send_channel "Email"    "${INPUT_EMAIL_URL:-}"    "${INPUT_EMAIL_TEMPLATE:-}"    "html"     "${TDIR}/email.html" ;;
      telegram) send_channel "Telegram" "${INPUT_TELEGRAM_URL:-}" "${INPUT_TELEGRAM_TEMPLATE:-}" "html"     "${TDIR}/telegram.html" ;;
      bark)     send_channel "Bark"     "${INPUT_BARK_URL:-}"     "${INPUT_BARK_TEMPLATE:-}"     "text"     "${TDIR}/bark.txt" ;;
      ntfy)     send_channel "Ntfy"     "${INPUT_NTFY_URL:-}"     "${INPUT_NTFY_TEMPLATE:-}"     "markdown" "${TDIR}/ntfy.md" ;;
      slack)    send_channel "Slack"    "${INPUT_SLACK_URL:-}"    "${INPUT_SLACK_TEMPLATE:-}"    "markdown" "${TDIR}/slack.md" ;;
      dingtalk) send_channel "DingTalk" "${INPUT_DINGTALK_URL:-}" "${INPUT_DINGTALK_TEMPLATE:-}" "markdown" "${TDIR}/dingtalk.md" ;;
      *) echo "⚠  Unknown channel: '${ch}'. Use 'urls' input for unlisted services." ;;
    esac
  done
fi

# ─── Generic Apprise URLs ─────────────────────────────────────────────────────
if [[ -n "${URLS_INPUT}" ]]; then
  echo "─── Generic URLs ────────────────────────────────────────────────"
  while IFS= read -r raw_url; do
    raw_url=$(echo "$raw_url" | tr -d ' ,')
    [[ -z "$raw_url" ]] && continue

    local_scheme="${raw_url%%://*}"
    url=$(decorate_url "$raw_url" "$ICON_URL")

    fmt="text"
    case "${local_scheme,,}" in
      ntfy*|slack*|dingtalk*|mattermost*|matrix*|rocket*|discord*|telegram) fmt="markdown" ;;
      email|mailto|mailtos) fmt="html" ;;
      bark*) fmt="text" ;;
    esac

    formatted_message="$MESSAGE"
    if [[ "$fmt" == "html" ]]; then
      formatted_message=$(convert_markdown "$MESSAGE")
      generic_body="${formatted_message}<br><br><a href=\"${RELEASE_URL}\">${RELEASE_URL}</a>"
    else
      generic_body="${formatted_message}

${RELEASE_URL}"
    fi

    echo "📤 [generic:${local_scheme}] Sending..."
    if python3 -m apprise --title "${TITLE}" --body "${generic_body}" --input-format "${fmt}" --notification-type "${NOTIFY_TYPE}" "${url}"; then
      echo "✅ [generic:${local_scheme}] Sent."
    else
      echo "::error::[generic:${local_scheme}] Failed. See Apprise docs for URL format."
    fi
  done < <(echo "${URLS_INPUT}" | tr ',' '\n')
fi

echo "──────────────────────────────────────────────────────────────────"
echo "✅ All notifications processed."