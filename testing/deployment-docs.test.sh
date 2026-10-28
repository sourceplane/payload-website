#!/usr/bin/env bash
# THE DEPLOYMENT RECORD IS WRITTEN FROM WHAT ANSWERS, OR NOT AT ALL.
#
# `02-docs` is a bootstrap's last word: its render (hooks/render-deployment-
# docs.sh) probes every URL and writes ai/context/deployment.md and the
# README's live-deployment section. It used to record a 404 in the table and
# then call the site "live" in the README regardless — so a product whose
# deploy never happened finished its bootstrap "live on stage and prod". Here,
# against a stand-in curl (no network), the render must:
#
#   1. refuse a site that does not answer: exit non-zero, name every URL
#      that did not, and write nothing;
#   2. record a site that answers, and call it live;
#   3. probe again before giving up, so a site that comes up between rounds
#      is recorded;
#   4. with DEPLOYMENT_DOCS_ALLOW_DOWN=1 (the offline bootstrap's setting),
#      record what it found in one round and never call the site live.
#
# bash, python3, git. No network, no orun, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
hook="$root/hooks/render-deployment-docs.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "   ok  $1"; }
bad() { echo "   ✕  $1" >&2; fail=1; }

# A stand-in curl: answers FAKE_CURL_CODE (000 = unreachable) for the first
# FAKE_CURL_DOWN_FOR calls, then FAKE_CURL_UP_CODE; the REST API's body is
# Payload's signed-out `{"user":null}`. It speaks the one call the hook makes:
# curl -s -o <file> -w '%{http_code}' --max-time <n> <url>.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-w|--max-time) [ "$1" = -o ] && out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
n=$(( $(cat "$FAKE_CURL_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_CURL_COUNT"
code="${FAKE_CURL_CODE:-000}"
[ "$n" -gt "${FAKE_CURL_DOWN_FOR:-999999}" ] && code="${FAKE_CURL_UP_CODE:-200}"
case "$url" in */api/users/me) body='{"user":null}' ;; *) body='<html>payload</html>' ;; esac
[ -n "$out" ] && printf '%s' "$body" > "$out"
printf '%s' "$code"
[ "$code" = 000 ] && exit 7
exit 0
SH
chmod +x "$tmp/bin/curl"

# A placed product, as far as the render reads one.
site() { # DIR
  rm -rf "$1"; mkdir -p "$1/.rebrand" "$1/ai/context" "$1/.github/workflows"
  printf '%s\n' '{"reponame": "acme-website", "subdomain": "acme"}' > "$1/.rebrand/values.json"
  printf 'execution:\n  state:\n    workspace: ws_test\n' > "$1/intent.yaml"
  printf '      - uses: sourceplane/orun-action@v1.2.0\n        with:\n          version: v2.78.4\n' > "$1/.github/workflows/ci.yml"
  printf '# acme-website\n\n## Live deployment\n\n<!-- 02-docs:begin -->\nNot recorded yet.\n<!-- 02-docs:end -->\n' > "$1/README.md"
  echo "# operations" > "$1/ai/context/operations.md"
  git -C "$1" init -q && git -C "$1" add -A && git -C "$1" -c user.email=t@example.invalid -c user.name=t commit -qm site
}
render() { # DIR LOG [VAR=VALUE…] — the hook as 02-docs runs it, curl stood in
  local dir="$1" log="$2"; shift 2
  rm -f "$tmp/count"
  env PATH="$tmp/bin:$PATH" FAKE_CURL_COUNT="$tmp/count" DEPLOYMENT_DOCS_PROBE_INTERVAL=0 "$@" \
    bash "$hook" "$dir" ws_test "$root" > "$log" 2>&1
}
urls=(site-stage api-stage admin-stage site-prod api-prod admin-prod)
named() { # LOG — every probed URL named in the refusal
  local log="$1" u
  for u in "acme-website-web-stage.acme.workers.dev " "acme-website-web-stage.acme.workers.dev/api/users/me" \
           "acme-website-web-stage.acme.workers.dev/admin" "acme-website-web-prod.acme.workers.dev " \
           "acme-website-web-prod.acme.workers.dev/api/users/me" "acme-website-web-prod.acme.workers.dev/admin"; do
    grep -q "https://$u" "$log" || return 1
  done
}

echo "── the deployment record (hooks/render-deployment-docs.sh), against a stand-in curl"

# 1. Down, as a convergence that never deployed leaves it: refused, nothing written.
for code in 404 000; do
  site "$tmp/down"
  if render "$tmp/down" "$tmp/down.log" FAKE_CURL_CODE="$code" DEPLOYMENT_DOCS_PROBE_ATTEMPTS=2; then
    bad "a site answering $code was recorded — the render must refuse it"
  elif ! named "$tmp/down.log" || ! grep -q "nothing was recorded" "$tmp/down.log" || ! grep -q "01-product" "$tmp/down.log"; then
    bad "the refusal ($code) does not name every URL and the way out (re-run 01-product):"; sed 's/^/        /' "$tmp/down.log" >&2
  elif [ -n "$(git -C "$tmp/down" status --porcelain)" ]; then
    bad "the refusal ($code) wrote files: $(git -C "$tmp/down" status --porcelain | tr '\n' ' ')"
  elif [ "$(cat "$tmp/count")" != $(( ${#urls[@]} * 2 )) ]; then
    bad "the refusal ($code) probed $(cat "$tmp/count") time(s), not ${#urls[@]} URLs × 2 rounds"
  else
    ok "a site answering $code is refused after 2 rounds: every URL named, nothing written"
  fi
done

# 2. Up: recorded, and live.
site "$tmp/up"
if ! render "$tmp/up" "$tmp/up.log" FAKE_CURL_CODE=200; then
  bad "a site that answers was refused:"; sed 's/^/        /' "$tmp/up.log" >&2
else
  dep="$tmp/up/ai/context/deployment.md"
  if [ "$(grep -c '| LIVE (200)' "$dep")" != 6 ] || ! grep -q 'LIVE (200) — Payload reads D1' "$dep"; then
    bad "the record does not show all six URLs live (and the API reading D1)"; grep '^|' "$dep" >&2
  elif ! grep -q 'This site is \*\*live\*\*' "$tmp/up/README.md" || grep -q 'Not every URL answered' "$dep"; then
    bad "a site that answered is not called live"
  elif ! grep -q 'WIRING_CLOUDFLARE_R2' "$dep" || ! grep -q 'CLOUDFLARE_R2_TOKEN' "$dep"; then
    bad "the record does not name the R2 bucket's secrets"
  else
    ok "a site that answers is recorded, all six URLs live, and the README calls it live"
  fi
fi

# 3. Down for the first round, up by the second: recorded.
site "$tmp/late"
if render "$tmp/late" "$tmp/late.log" FAKE_CURL_CODE=404 FAKE_CURL_DOWN_FOR=6 DEPLOYMENT_DOCS_PROBE_ATTEMPTS=3 \
   && grep -q 'This site is \*\*live\*\*' "$tmp/late/README.md" && grep -q "probing again" "$tmp/late.log" \
   && [ "$(cat "$tmp/count")" = 12 ]; then
  ok "a site that comes up between rounds is recorded live — probed again, the answered URLs not re-probed"
else
  bad "a site that came up in the second round was not recorded as live (probes: $(cat "$tmp/count" 2>/dev/null)):"
  sed 's/^/        /' "$tmp/late.log" >&2
fi

# 4. The offline bootstrap's setting: recorded as found, in one round, never "live".
site "$tmp/offline"
if ! render "$tmp/offline" "$tmp/offline.log" FAKE_CURL_CODE=000 DEPLOYMENT_DOCS_ALLOW_DOWN=1 DEPLOYMENT_DOCS_PROBE_ATTEMPTS=5; then
  bad "DEPLOYMENT_DOCS_ALLOW_DOWN=1 still refused:"; sed 's/^/        /' "$tmp/offline.log" >&2
elif grep -q 'This site is \*\*live\*\*' "$tmp/offline/README.md" || ! grep -q 'This site was \*\*not answering\*\*' "$tmp/offline/README.md"; then
  bad "a record of a site that did not answer calls it live"; sed -n '/02-docs:begin/,/02-docs:end/p' "$tmp/offline/README.md" >&2
elif [ "$(grep -c '| unreachable |' "$tmp/offline/ai/context/deployment.md")" != 6 ] \
     || ! grep -q 'Not every URL answered' "$tmp/offline/ai/context/deployment.md"; then
  bad "the record does not show the six URLs unreachable, or does not say so"
elif [ "$(cat "$tmp/count")" != "${#urls[@]}" ]; then
  bad "DEPLOYMENT_DOCS_ALLOW_DOWN=1 probed $(cat "$tmp/count") time(s), not one round"
else
  ok "DEPLOYMENT_DOCS_ALLOW_DOWN=1 records what it found in one round, and the README says it was not answering"
fi

[ "$fail" -eq 0 ] || { echo "deployment-docs.test.sh: failure(s)" >&2; exit 1; }
echo "deployment-docs.test.sh: ok"
