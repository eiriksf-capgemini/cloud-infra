#!/usr/bin/env node
// Mint a short-lived GitHub App installation token so coding agents act under
// the app's bot identity (<slug>[bot]) instead of the human's account.
//
// Usage:
//   node gh-app-token.mjs             # prints the token
//   node gh-app-token.mjs --env       # prints `export` lines; eval "$(node gh-app-token.mjs --env)"
//   node gh-app-token.mjs --check     # prints bot login, user id, repos reachable; never prints the token
//
// Configuration, env first, then .gh-app-identity.json found in the current
// directory or the nearest parent (gitignore it). A relative privateKeyPath in
// the file resolves against the file's own directory:
//   GH_APP_CLIENT_ID          app client id (Iv23li...) or numeric app id     [required]
//   GH_APP_INSTALLATION_ID    installation id on the owner                    [required]
//   GH_APP_PRIVATE_KEY_PATH   PEM file, gitignored                            [required]
//   GH_APP_BOT_LOGIN          <slug>[bot]; looked up from GET /app if absent  [optional]
//   GH_APP_BOT_USER_ID        numeric id; looked up from GET /users if absent [optional]
//   JSON keys: clientId, installationId, privateKeyPath, botLogin, botUserId
//
// Node 18+; no dependencies. Tokens expire after one hour; re-run for a fresh one.
import { createSign } from "node:crypto";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const CONFIG_FILE = ".gh-app-identity.json";
const API = "https://api.github.com";

// Every value spliced into an eval-ed export line is checked against an
// allowlist that cannot carry shell syntax. Installation tokens are ~383
// characters, ghs_ prefixed, and contain two '.' (observed 2026-10-16), so '.'
// is admitted: the shell does no expansion on it and it does not split words.
const TOKEN_PATTERN = /^[A-Za-z0-9._-]+$/;
const EXPIRY_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const LOGIN_PATTERN = /^[A-Za-z0-9-]+\[bot\]$/;
const ID_PATTERN = /^\d+$/;

const b64url = (buf) => Buffer.from(buf).toString("base64url");

const redact = (text, token) =>
  typeof token === "string" && token !== ""
    ? String(text).replaceAll(token, "[redacted]")
    : String(text);

export function mintJwt(pem, clientId, nowMs = Date.now()) {
  const now = Math.floor(nowMs / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  // 60s backdated for clock skew; 600s is GitHub's maximum lifetime.
  const payload = b64url(
    JSON.stringify({ iat: now - 60, exp: now + 540, iss: clientId }),
  );
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${payload}`);
  return `${header}.${payload}.${b64url(signer.sign(pem))}`;
}

export function buildEnvLines(token, expiresAt, botLogin, botUserId, env = {}) {
  const email = `${botUserId}+${botLogin}@users.noreply.github.com`;
  const lines = [
    `export GH_TOKEN=${token}`,
    `export GITHUB_TOKEN=${token}`,
    `export GIT_AUTHOR_NAME='${botLogin}'`,
    `export GIT_AUTHOR_EMAIL='${email}'`,
    `export GIT_COMMITTER_NAME='${botLogin}'`,
    `export GIT_COMMITTER_EMAIL='${email}'`,
  ];
  // A credential helper scoped to this shell, so `git push https://github.com/<owner>/<repo>.git`
  // authenticates as the bot without touching ~/.gitconfig. The empty VALUE_0 resets the helper
  // list for github.com first, so a global helper (osxkeychain, manager) holding the human's
  // credentials cannot answer before ours. An SSH remote never carries the token.
  if (env.GIT_CONFIG_COUNT === undefined) {
    lines.push(
      "export GIT_CONFIG_COUNT=2",
      "export GIT_CONFIG_KEY_0=credential.https://github.com.helper",
      "export GIT_CONFIG_VALUE_0=",
      "export GIT_CONFIG_KEY_1=credential.https://github.com.helper",
      `export GIT_CONFIG_VALUE_1='!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f'`,
    );
  } else {
    lines.push(
      "# GIT_CONFIG_COUNT already set; not adding a credential helper. Push over HTTPS with x-access-token basic auth.",
    );
  }
  lines.push(`# expires ${expiresAt}`);
  return lines;
}

export function findConfigFile(cwd) {
  let dir = resolve(cwd);
  for (;;) {
    const candidate = resolve(dir, CONFIG_FILE);
    if (existsSync(candidate)) return candidate;
    const parent = dirname(dir);
    if (parent === dir) return undefined;
    dir = parent;
  }
}

export function loadConfig(env, cwd = process.cwd()) {
  let file = {};
  let fileDir = cwd;
  const path = findConfigFile(cwd);
  if (path) {
    try {
      file = JSON.parse(readFileSync(path, "utf8"));
      fileDir = dirname(path);
    } catch (err) {
      return { error: `cannot parse ${path}: ${err.message}` };
    }
  }
  const pick = (envKey, fileKey) =>
    env[envKey] !== undefined && env[envKey] !== ""
      ? String(env[envKey])
      : file[fileKey] !== undefined
        ? String(file[fileKey])
        : undefined;
  const cfg = {
    clientId: pick("GH_APP_CLIENT_ID", "clientId"),
    installationId: pick("GH_APP_INSTALLATION_ID", "installationId"),
    privateKeyPath: pick("GH_APP_PRIVATE_KEY_PATH", "privateKeyPath"),
    botLogin: pick("GH_APP_BOT_LOGIN", "botLogin"),
    botUserId: pick("GH_APP_BOT_USER_ID", "botUserId"),
  };
  const missing = ["clientId", "installationId", "privateKeyPath"].filter(
    (k) => !cfg[k],
  );
  if (missing.length) {
    return {
      error: `missing ${missing.join(", ")}; set GH_APP_* env or write ${CONFIG_FILE}`,
    };
  }
  if (!ID_PATTERN.test(cfg.installationId)) {
    return { error: "installationId must be numeric" };
  }
  const keyFromEnv = env.GH_APP_PRIVATE_KEY_PATH !== undefined && env.GH_APP_PRIVATE_KEY_PATH !== "";
  cfg.privateKeyPath = resolve(keyFromEnv ? cwd : fileDir, cfg.privateKeyPath);
  return { cfg };
}

// Returns { code, stdout, stderr }; never writes to the process streams, so a
// caller can drive it with a stubbed fetch and a throwaway key.
export async function main({
  fetch: fetchFn = fetch,
  argv = [],
  env = process.env,
  cwd = process.cwd(),
} = {}) {
  const fail = (msg) => ({ code: 1, stdout: "", stderr: `gh-app-token: ${msg}\n` });
  const wantEnv = argv.includes("--env");
  const wantCheck = argv.includes("--check");
  const unknown = argv.filter((a) => a !== "--env" && a !== "--check");
  if (unknown.length) {
    return fail(`unknown argument ${unknown[0]}; use --env or --check (no argument prints the token)`);
  }

  const loaded = loadConfig(env, cwd);
  if (loaded.error) return fail(loaded.error);
  const cfg = loaded.cfg;

  let pem;
  try {
    pem = readFileSync(cfg.privateKeyPath, "utf8");
  } catch (err) {
    return fail(`cannot read private key at ${cfg.privateKeyPath}: ${err.message}`);
  }

  const headers = (auth) => ({
    Authorization: auth,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  });
  let jwtAuth;
  let token;
  try {
    jwtAuth = `Bearer ${mintJwt(pem, cfg.clientId)}`;
    const res = await fetchFn(
      `${API}/app/installations/${cfg.installationId}/access_tokens`,
      { method: "POST", headers: headers(jwtAuth) },
    );
    const body = await res.json();
    if (!res.ok || !body.token) {
      // Never print the raw body: a non-2xx body may still carry a token.
      const msg =
        typeof body.message === "string"
          ? `: ${redact(body.message.split("\n")[0], body.token)}`
          : "";
      return fail(`GitHub returned ${res.status}${msg}`);
    }
    if (!TOKEN_PATTERN.test(body.token)) {
      return fail("GitHub returned a token with unexpected characters");
    }
    if ((wantEnv || wantCheck) && !EXPIRY_PATTERN.test(body.expires_at)) {
      return fail("GitHub returned an expires_at that is not ISO-8601");
    }
    token = body.token;

    if (!wantEnv && !wantCheck) {
      return { code: 0, stdout: token + "\n", stderr: "" };
    }

    // Resolve the bot identity unless both halves were configured.
    let { botLogin, botUserId } = cfg;
    if (!botLogin) {
      const app = await fetchFn(`${API}/app`, { headers: headers(jwtAuth) });
      const appBody = await app.json();
      if (!app.ok || typeof appBody.slug !== "string") {
        return fail(`GET /app returned ${app.status}; set GH_APP_BOT_LOGIN to skip the lookup`);
      }
      botLogin = `${appBody.slug}[bot]`;
    }
    if (!LOGIN_PATTERN.test(botLogin)) {
      return fail("bot login has an unexpected shape; expected <slug>[bot]");
    }
    if (!botUserId) {
      const user = await fetchFn(
        `${API}/users/${encodeURIComponent(botLogin)}`,
        { headers: headers(`Bearer ${token}`) },
      );
      const userBody = await user.json();
      if (!user.ok || typeof userBody.id !== "number") {
        return fail(
          `GET /users/${botLogin} returned ${user.status}; set GH_APP_BOT_USER_ID to skip the lookup`,
        );
      }
      botUserId = String(userBody.id);
    }
    if (!ID_PATTERN.test(botUserId)) {
      return fail("bot user id must be numeric");
    }

    if (wantCheck) {
      const repos = await fetchFn(`${API}/installation/repositories?per_page=100`, {
        headers: headers(`Bearer ${token}`),
      });
      const reposBody = await repos.json();
      const names = Array.isArray(reposBody.repositories)
        ? reposBody.repositories.map((r) => r.full_name)
        : [];
      const out = [
        `bot login:      ${botLogin}`,
        `bot user id:    ${botUserId}`,
        `commit email:   ${botUserId}+${botLogin}@users.noreply.github.com`,
        `installation:   ${cfg.installationId}`,
        `repositories:   ${names.length ? names.join(", ") : `(GET /installation/repositories returned ${repos.status})`}${names.length >= 100 ? " (first 100 shown)" : ""}`,
        `token expires:  ${body.expires_at}`,
        "token minted and discarded; use --env to export it",
      ];
      return { code: 0, stdout: redact(out.join("\n"), token) + "\n", stderr: "" };
    }

    return {
      code: 0,
      stdout: buildEnvLines(token, body.expires_at, botLogin, botUserId, env).join("\n") + "\n",
      stderr: "",
    };
  } catch (err) {
    return fail(redact(String(err.message).split("\n")[0], token));
  }
}

function invokedDirectly() {
  if (!process.argv[1]) return false;
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (invokedDirectly()) {
  const r = await main({ argv: process.argv.slice(2) });
  process.stdout.write(r.stdout);
  process.stderr.write(r.stderr);
  process.exitCode = r.code;
}
