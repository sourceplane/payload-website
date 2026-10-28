#!/usr/bin/env bash
# TIER 2 — the product a bootstrap produces builds, migrates, deploys (dry)
# and serves.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree.
# This proves it WORKS, by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its one pull request merges),
#      install with the lockfile the product ships, render the wrangler
#      fixture and check the committed config IS that render, typecheck,
#      lint, test, build. The landing's own PR runs `plan` alone (an
#      `orun/BASE-*` branch), so THIS is where a product those steps refuse
#      is caught: before the tag, not after a build has merged it;
#   2. the stage lanes' own steps, rendered by `orun plan` in the product and
#      run IN THE TREE THE RUNNER STAGES for each job (testing/lib/stage-job.py),
#      with the dependency layout the pinned composition produces and with the
#      job's secrets in its environment as the platform resolves them (the
#      component's secretEnv, and its environment's: stage's documents only):
#      - web, from a pull request's plan (the verify profile: the deploy
#        profile has no dry run) — `verify-app-structure` (which checks the
#        wrangler config exists BEFORE anything is built), `build-app` (the
#        component's buildCommand: the live wiring render, then the build),
#        `verify-build-output` and `deploy-dry-run` (`wrangler deploy
#        --dry-run --name <reponame>-web-stage`), the database id and the
#        bucket name in the built config asserted to be the stage documents',
#        not the fixture's;
#      - db-migrate: its install and build, the pull request's `plan` (offline,
#        every checksum verified), then the merge's `apply` — the step a push
#        to main runs — against a stand-in for D1's REST API over real SQLite
#        (testing/lib/d1-api.py), which refuses any account, database or token
#        but the ones the job resolves: Payload's schema created, the site's
#        three secrets generated and every migration recorded; then the apply
#        again, which applies nothing;
#   3. serve the built Worker with `wrangler dev` (a local D1 and R2 behind
#      the same bindings): with no schema Payload has no secret and the
#      component's OWN `smokeCommand` REFUSES the site; after the product's
#      own `db:migrate:local` the smoke passes, verbatim — the check the real
#      deploy ends with — and then every route the site promises: the pages,
#      the admin, the REST API and the sitemaps answer, the titles carry the
#      product's name, a draft preview without the secret is refused, the
#      first admin signs up and signs in, the template's seed fills D1 and
#      uploads its images to R2, the media is served back from R2, the seeded
#      home and posts render, and the Cron Trigger runs Payload's job queue.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered Cloudflare tokens, apply the database, migrate it and deploy for
# real, and probe workers.dev. The D1 and R2 roots are verified to
# `terraform validate` and their plans are part of every pull request's lanes;
# the applies need an account. And the deploy itself needs Workers Paid: the
# Worker is about 4 MiB gzipped, over Workers Free's 3 MiB (the dry run prints
# it).
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, and the network for
# `pnpm install`, the build's Google Font and the seed's images (or a warm
# store). Several minutes: three installs and two builds.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git curl; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done

scratch="$(mktemp -d)"
dev_pid=""
api_pid=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So it is
# started as its own process group (setsid) and the whole group is stopped.
stop_group() {
  kill -TERM -- "-$1" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$1" 2>/dev/null || break; sleep 0.5; done
  kill -KILL -- "-$1" 2>/dev/null || true
}
cleanup() {
  [ -z "$dev_pid" ] || stop_group "$dev_pid"
  [ -z "$api_pid" ] || stop_group "$api_pid"
  rm -rf "$scratch"
}
trap cleanup EXIT
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false NEXT_TELEMETRY_DISABLED=1 TURBO_TELEMETRY_DISABLED=1

# The landing's own checks, step for step: what a pull request in the product
# verifies through its lanes, run here at once on the whole tree.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "git diff --exit-code"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

# A job's steps out of a plan, by component and environment: each step's
# script (named by its id, or by a fixed name for the composition steps this
# file runs), the job's path, its env and the names of its secrets.
extract() { # PLAN COMPONENT ENV OUTDIR
  python3 - "$@" <<'PY'
import json, pathlib, re, sys
plan, comp, env, out = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4])
out.mkdir(parents=True, exist_ok=True)
job = next(j for j in plan["jobs"] if j["component"] == comp and j["environment"] == env)
for s in job["steps"]:
    run = s.get("run") or ""
    if not run:
        continue
    sid = s["id"]
    if "dist/runner/cli.js apply" in run:
        sid = "migrate-apply"
    elif "dist/runner/cli.js plan" in run:
        sid = "migrate-plan"
    (out / f"{re.sub(r'[^A-Za-z0-9_-]', '_', sid)}.sh").write_text(run)
    if s["id"] in ("install-workspace-dependencies", "install-dependencies"):
        (out / "install.sh").write_text(run)
        (out / "install.wd").write_text(s.get("working-directory") or ".")
        (out / "install.scope").write_text(s.get("scope") or "job")
(out / "path").write_text(job.get("path") or ".")
(out / "env").write_text("".join(f"export {k}={json.dumps(v)}\n" for k, v in (job.get("env") or {}).items()))
(out / "secrets").write_text("\n".join(r["asEnv"] for r in job.get("secretRefs") or []))
PY
}

# A job's private tree, staged as orun stages it. The source checkout carries
# no build output (nothing was built in it), and its dependencies are what the
# pinned composition says: a lane-scoped install ran once in the source tree
# and is linked in, or the job installs its own.
stage_job() { # STEPS-DIR WORK-DIR LOG
  local steps="$1" work="$2" log="$3"
  [ -f "$steps/install.sh" ] || { echo "FAIL: the lane has no install step" >&2; return 1; }
  if [ "$(cat "$steps/install.scope")" = lane ]; then
    (cd "$tree" && bash -e "$steps/install.sh") > "$log" 2>&1 \
      || { echo "FAIL: the lane's install step" >&2; tail -30 "$log" >&2; return 1; }
    python3 "$here/lib/stage-job.py" "$tree" "$work" --shared-deps
    [ -L "$work/node_modules" ] || { echo "FAIL: the staged tree's node_modules is not the lane's symlink" >&2; return 1; }
    echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: lane — node_modules → the source tree's"
  else
    python3 "$here/lib/stage-job.py" "$tree" "$work"
    echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: job — installing inside it"
    (cd "$work/$(cat "$steps/path")/$(cat "$steps/install.wd")" && bash -e "$steps/install.sh") > "$log" 2>&1 \
      || { echo "FAIL: the lane's install step" >&2; tail -30 "$log" >&2; return 1; }
    [ -d "$work/node_modules" ] && [ ! -L "$work/node_modules" ] \
      || { echo "FAIL: the job's install did not land inside its own tree" >&2; return 1; }
  fi
}

# One step, in the runner's per-job environment: the job's env (intent
# environment `env:`), its resolved secrets (exported by the caller) and
# ORUN_ENVIRONMENT; the step runs in the component's directory.
run_step() { # STEPS-DIR WORK-DIR STEP LOG
  local steps="$1" work="$2" step="$3" log="$4"
  [ -f "$steps/$step.sh" ] || { echo "FAIL: the stage lane has no $step step" >&2; return 1; }
  echo "   ▸ $step"
  if ! (cd "$work/$(cat "$steps/path")" && source "$steps/env" && export ORUN_ENVIRONMENT=stage \
        && bash -e "$steps/$step.sh") > "$log" 2>&1; then
    echo "FAIL: the lane's $step step" >&2; tail -40 "$log" >&2; return 1
  fi
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   2 phases placed and landed"
s01="$(git -C "$tree" rev-parse HEAD~1)"

# ── 1. the product's one pull request ──────────────────────────────────────
echo "── 01-product's landing: install, the fixture render, typecheck, lint, test, build"
git -C "$tree" worktree add -q "$scratch/at-01" "$s01"
checks "$scratch/at-01" "$scratch/checks-01.log"
# The landing's build is done; its tree is not needed again, and the disk is shared.
git -C "$tree" worktree remove --force "$scratch/at-01"

# ── 2. the stage lanes' steps, in each job's own tree ─────────────────────
# A pull request that changes the site and the migration component: the lanes
# `orun plan` gives it. And the merge's plan, for the step only a merge runs.
git -C "$tree" checkout -q -b e2e-pr
echo "<!-- a change to the site's component -->" >> "$tree/apps/web/README.md"
echo "# a change to the migration component" >> "$tree/infra/db-migrate/component.yaml"
git -C "$tree" -c user.email=e2e@example.invalid -c user.name=e2e commit -qam "a pull request"
(cd "$tree" && orun plan --intent intent.yaml --trigger github-pull-request --changed \
   --base main --head HEAD --env stage --output "$scratch/plan.json") > "$scratch/plan.log" 2>&1 \
  || { echo "FAIL: orun plan (pull request)" >&2; tail -15 "$scratch/plan.log" >&2; exit 1; }
(cd "$tree" && orun plan --intent intent.yaml --trigger github-push-main --env stage \
   --output "$scratch/plan-main.json") > "$scratch/plan-main.log" 2>&1 \
  || { echo "FAIL: orun plan (push to main)" >&2; tail -15 "$scratch/plan-main.log" >&2; exit 1; }
extract "$scratch/plan.json" web stage "$scratch/web"
extract "$scratch/plan.json" db-migrate stage "$scratch/mig"
extract "$scratch/plan-main.json" db-migrate stage "$scratch/mig-main"

# What the platform resolves into the jobs before their first step: the
# wiring document the D1 root lease-published (the components' secretEnv),
# with a database id no fixture carries, so the built config and the
# migrated database prove which document they came from.
d1_id="5ca1ab1e-0000-4000-8000-00000000a001"
export WIRING_CLOUDFLARE_D1_STAGE='{"d1_database_id":"'"$d1_id"'","d1_database_name":"stg-'"$repo"'-stage"}'
# …and the bucket the R2 root lease-published, under a name no fixture carries.
# Stage's documents only: prod's are not published here, as on a first
# convergence whose prod applies have not finished, and the stage lane must
# not need them.
r2_bucket="e2e-$repo-stage-bucket"
export WIRING_CLOUDFLARE_R2_STAGE='{"r2_bucket_name":"'"$r2_bucket"'"}'
unset WIRING_CLOUDFLARE_D1_PROD WIRING_CLOUDFLARE_R2_PROD

echo "── the stage web lane: verify-app-structure, build-app, verify-build-output, deploy-dry-run"
for key in WIRING_CLOUDFLARE_D1_STAGE WIRING_CLOUDFLARE_R2_STAGE; do
  grep -qx "$key" "$scratch/web/secrets" || { echo "FAIL: the stage web lane does not resolve $key" >&2; exit 1; }
done
# A job resolves every secret it declares before its first step, and the
# stage lane waits on stage's applies alone — so a prod document here fails
# it whenever prod's apply has not published yet.
for key in WIRING_CLOUDFLARE_D1_PROD WIRING_CLOUDFLARE_R2_PROD; do
  ! grep -qx "$key" "$scratch/web/secrets" || { echo "FAIL: the stage web lane resolves $key — prod's document, which nothing orders it after" >&2; exit 1; }
done
work="$tree/.orun/runs/e2e/web.stage.verify-deploy/work"
stage_job "$scratch/web" "$work" "$scratch/install-web.log"
[ ! -e "$work/apps/web/.open-next" ] || { echo "FAIL: the staged tree carries build output" >&2; exit 1; }
for step in verify-app-structure build-app verify-build-output deploy-dry-run; do
  run_step "$scratch/web" "$work" "$step" "$scratch/$step.log"
done
grep -q "\"$d1_id\"" "$work/apps/web/wrangler.jsonc" \
  || { echo "FAIL: the lane's build did not render the stage database id from its wiring document" >&2; exit 1; }
grep -q "\"$r2_bucket\"" "$work/apps/web/wrangler.jsonc" \
  || { echo "FAIL: the lane's build did not render the stage bucket from its wiring document" >&2; exit 1; }
# wrangler's dry run names a D1 binding's database by name, not id.
grep -Eq "env\.D1 \(stg-$repo-stage\) +D1 Database" "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run does not bind D1 to the stage database" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
grep -Eq "env\.R2 \($r2_bucket\) +R2 Bucket" "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run does not bind R2 to the stage bucket" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
size="$(grep -Eo 'Total Upload: [0-9.]+ KiB / gzip: [0-9.]+ KiB' "$scratch/deploy-dry-run.log" | head -1)"
echo "   the built config binds D1 to the stage document's database ($d1_id) and R2 to its bucket ($r2_bucket);"
echo "   the dry run accepts it — ${size:-size not printed} (Workers Paid: the Free plan allows 3 MiB gzipped)"

echo "── the stage db-migrate lane: install, build, the PR's plan, the merge's apply (a stand-in D1 API)"
for key in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID WIRING_CLOUDFLARE_D1; do
  grep -qx "$key" "$scratch/mig-main/secrets" || { echo "FAIL: the stage db-migrate lane does not resolve $key" >&2; exit 1; }
done
[ -f "$scratch/mig/migrate-plan.sh" ] && [ ! -f "$scratch/mig/migrate-apply.sh" ] \
  || { echo "FAIL: a pull request's db-migrate lane must plan and not apply" >&2; ls "$scratch/mig" >&2; exit 1; }
[ -f "$scratch/mig-main/migrate-apply.sh" ] && [ ! -f "$scratch/mig-main/migrate-plan.sh" ] \
  || { echo "FAIL: the merge's db-migrate lane must apply" >&2; ls "$scratch/mig-main" >&2; exit 1; }
mwork="$tree/.orun/runs/e2e/db-migrate.stage.migrate/work"
stage_job "$scratch/mig" "$mwork" "$scratch/install-mig.log"
run_step "$scratch/mig" "$mwork" build-db-package "$scratch/mig-build.log"
run_step "$scratch/mig" "$mwork" migrate-plan "$scratch/mig-plan.log"
grep -q '"010_payload"' "$scratch/mig-plan.log" && grep -q '"020_app_secrets"' "$scratch/mig-plan.log" \
  || { echo "FAIL: the plan does not list 010_payload and 020_app_secrets as pending" >&2; cat "$scratch/mig-plan.log" >&2; exit 1; }
# The stand-in D1 API: only this account, this database (the stage
# document's id) and this token are answered.
(exec setsid python3 "$here/lib/d1-api.py" "$scratch/d1.sqlite" "$scratch/d1.port" \
   --account e2e-account --database "$d1_id" --token e2e-d1-token) > "$scratch/d1-api.log" 2>&1 < /dev/null &
api_pid=$!
for _ in $(seq 1 50); do [ -s "$scratch/d1.port" ] && break; sleep 0.1; done
[ -s "$scratch/d1.port" ] || { echo "FAIL: the stand-in D1 API did not start" >&2; cat "$scratch/d1-api.log" >&2; exit 1; }
export CLOUDFLARE_API_BASE_URL="http://127.0.0.1:$(cat "$scratch/d1.port")/client/v4"
# The job's own secrets: the D1 token as CLOUDFLARE_API_TOKEN, the account id,
# and this environment's wiring document.
for pass in first again; do
  (export CLOUDFLARE_API_TOKEN=e2e-d1-token CLOUDFLARE_ACCOUNT_ID=e2e-account \
          WIRING_CLOUDFLARE_D1="$WIRING_CLOUDFLARE_D1_STAGE" \
   && run_step "$scratch/mig-main" "$mwork" migrate-apply "$scratch/mig-apply-$pass.log") || exit 1
done
python3 - "$scratch/d1.sqlite" "$scratch/mig-apply-first.log" "$scratch/mig-apply-again.log" <<'PY'
import json, re, sqlite3, sys
db = sqlite3.connect(sys.argv[1])
def result(path):
    text = open(path).read()
    return json.loads(text[text.index("{"):text.rindex("}") + 1])
first, again = result(sys.argv[2]), result(sys.argv[3])
problems = []
ALL = ["000_control_baseline", "010_payload", "020_app_secrets"]
if first["applied"] != ALL:
    problems.append(f"the first apply applied {first['applied']}")
if again["applied"] or again["skipped"] != ALL:
    problems.append(f"the second apply applied {again['applied']} and skipped {again['skipped']} — it must apply nothing")
have = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
for t in ("users", "users_sessions", "pages", "posts", "media", "categories", "header", "footer", "payload_jobs"):
    if t not in have:
        problems.append(f"Payload's schema has no {t} table")
secrets = dict(db.execute("SELECT name, value FROM app_secrets"))
if sorted(secrets) != ["cron", "payload", "preview"] or not all(re.fullmatch(r"[0-9a-f]{64}", v) for v in secrets.values()):
    problems.append(f"the generated secrets are {sorted(secrets)}")
ledger = [r[0] for r in db.execute("SELECT id FROM _migrations_applied ORDER BY id")]
if ledger != ALL:
    problems.append(f"the ledger records {ledger}")
for p in problems:
    print(f"  ✕ {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
grep -q 'POST /client/v4/accounts/e2e-account/d1/database/'"$d1_id"'/query' "$scratch/d1-api.log" \
  || { echo "FAIL: the runner did not call the stage database's query endpoint" >&2; exit 1; }
echo "   the stage document's database: Payload's schema created, three secrets generated, all three migrations"
echo "   recorded; the second apply applied nothing"
stop_group "$api_pid"; api_pid=""
unset CLOUDFLARE_API_BASE_URL

# ── 3. serve it, and smoke it as the deploy does ───────────────────────────
echo "── wrangler dev over the built Worker (a local D1 behind D1, a local bucket behind R2)"
# Payload loads its config once per isolate, so a Worker that started before
# its database was migrated stays without one: a real convergence deploys
# (new isolates) after the migrations, and this serves the Worker again
# after them, the same way.
start_dev() {
  port=$(python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()")
  (cd "$work/apps/web" && exec setsid pnpm exec wrangler dev --config wrangler.jsonc --ip 127.0.0.1 --port "$port" \
     --name "$repo-web-stage" --test-scheduled --show-interactive-dev-session=false) > "$scratch/dev.log" 2>&1 < /dev/null &
  dev_pid=$!
  url="http://127.0.0.1:$port"
  for _ in $(seq 1 90); do
    curl -s -o /dev/null "$url/favicon.ico" && break
    kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }
    sleep 1
  done
  curl -s -o /dev/null "$url/favicon.ico" || { echo "FAIL: wrangler dev never answered" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }
}
start_dev
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"

echo "   ▸ no schema yet: Payload has no secret, the site does not serve, and the deploy's smoke refuses it"
code="$(curl -s -o /dev/null -w '%{http_code}' "$url/api/users/me")"
[ "$code" -ge 500 ] || { echo "FAIL: without the migrations /api/users/me answered $code, not an error" >&2; exit 1; }
if DEPLOYED_URL="$url" bash -c "$smoke"; then
  echo "FAIL: the deploy's smoke passed a site that could not read its database" >&2; exit 1
fi
# The Worker logs why, a moment after it answers.
for _ in $(seq 1 30); do grep -q 'No PAYLOAD_SECRET' "$scratch/dev.log" && break; sleep 0.5; done
grep -q 'No PAYLOAD_SECRET' "$scratch/dev.log" \
  || { echo "FAIL: the Worker's log does not say why (No PAYLOAD_SECRET …)" >&2; tail -20 "$scratch/dev.log" >&2; exit 1; }

echo "   ▸ the product's own db:migrate:local, then the component's own smokeCommand, DEPLOYED_URL=$url"
(cd "$work/apps/web" && pnpm run db:migrate:local) > "$scratch/migrate-local.log" 2>&1 \
  || { echo "FAIL: db:migrate:local" >&2; tail -20 "$scratch/migrate-local.log" >&2; exit 1; }
stop_group "$dev_pid"; dev_pid=""
start_dev
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the migrated site" >&2; exit 1; }

echo "   ▸ every route the site promises; an admin signs up, the seed fills D1 and R2, the Cron Trigger runs the jobs"
python3 - "$url" "$values" "$scratch/dev.log" <<'PY'
import html, http.cookiejar, json, re, sys, time, urllib.error, urllib.parse, urllib.request
base, values, devlog = sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3]
name, repo = values["productname"], values["reponame"]
problems = []
def bad(m): problems.append(m)
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
def req(path, method="GET", body=None, timeout=60):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(base + path, method=method, data=data,
                               headers={"content-type": "application/json"} if data else {})
    try:
        with opener.open(r, timeout=timeout) as resp:
            return resp.status, resp.headers.get("content-type", ""), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("content-type", ""), e.read()
def title(page):
    m = re.search(r"<title>(.*?)</title>", page, re.S)
    return html.unescape(m.group(1)) if m else None

# Before any content: the static home, the admin, the API, the sitemaps.
for path, want in (("/", 200), ("/admin", 200), ("/posts", 200), ("/search", 200), ("/pages-sitemap.xml", 200),
                   ("/posts-sitemap.xml", 200), ("/sitemap.xml", 200), ("/robots.txt", 200), ("/no-such-page", 404)):
    s, _, _ = req(path)
    if s != want:
        bad(f"{path} answered {s}, want {want}")
s, _, body = req("/posts")
if title(body.decode()) != f"{name} Posts":
    bad(f"/posts is titled {title(body.decode())!r}, not '{name} Posts'")
if "payload-website" in body.decode():
    bad("/posts still carries the baseline's name")
s, _, body = req("/api/users/me")
if s != 200 or json.loads(body).get("user") is not None:
    bad(f"/api/users/me signed out answered {s} {body[:80]!r}")
s, _, _ = req("/next/preview?" + urllib.parse.urlencode({"path": "/", "previewSecret": "not-the-secret"}))
if s != 403:
    bad(f"a draft preview without the preview secret answered {s}, not 403")

# The first admin, signed in; then the template's own seed.
s, _, body = req("/api/users/first-register", "POST", {"email": "e2e@example.com", "password": "e2e-password-1", "name": "E2E"})
if s not in (200, 201):
    bad(f"first-register answered {s} {body[:120]!r}")
s, _, body = req("/api/users/login", "POST", {"email": "e2e@example.com", "password": "e2e-password-1"})
if s != 200 or b"token" not in body:
    bad(f"login answered {s} {body[:120]!r}")
s, _, body = req("/api/users/me")
if s != 200 or (json.loads(body).get("user") or {}).get("email") != "e2e@example.com":
    bad(f"/api/users/me signed in answered {s} {body[:120]!r}")
s, _, body = req("/next/seed", "POST", timeout=300)
if s != 200 or b'"success":true' not in body:
    bad(f"the seed answered {s} {body[:200]!r}")

# What the seed wrote: media in R2, served back through the Worker.
s, _, body = req("/api/media?limit=10")
docs = json.loads(body).get("docs", []) if s == 200 else []
if len(docs) < 3:
    bad(f"/api/media lists {len(docs)} file(s) after the seed")
for d in docs[:2]:
    s, ctype, data = req(d["url"])
    if s != 200 or not ctype.startswith("image/") or len(data) < 1000:
        bad(f"{d['url']} answered {s} {ctype} ({len(data)} bytes) — not the image the seed uploaded to R2")
# …and pages and posts in D1, rendered per request.
s, _, body = req("/")
if s != 200 or "<h1" not in body.decode():
    bad(f"the seeded home answered {s}")
s, _, body = req("/posts")
posts = sorted(set(re.findall(r'href="(/posts/[a-z0-9-]+)"', body.decode())))
if len(posts) < 3:
    bad(f"/posts lists {posts} after the seed")
else:
    s, _, body = req(posts[0])
    t = title(body.decode()) or ""
    if s != 200 or not t.endswith(f"| {name}"):
        bad(f"{posts[0]} answered {s} titled {t!r}, not '… | {name}'")

# The Cron Trigger: wrangler dev's /__scheduled runs worker.ts's scheduled
# handler, which runs Payload's job queue with the cron secret.
s, _, _ = req("/__scheduled?cron=" + urllib.parse.quote("0 0 * * *"))
if s != 200:
    bad(f"the scheduled handler answered {s}")
for _ in range(20):
    log = open(devlog, errors="replace").read()
    if "/api/payload-jobs/run 200" in log:
        break
    time.sleep(0.5)
else:
    bad("the Cron Trigger did not run /api/payload-jobs/run (200) — the dev log says nothing of it")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   the pages, the admin, the API and the sitemaps, titled for {name!r}; a preview refused; an admin signed up,")
print(f"   the seed's {len(docs)} images served back from R2 and {len(posts)} posts rendered from D1; the job queue run by the Cron Trigger")
PY

echo "e2e.test.sh: ok"
