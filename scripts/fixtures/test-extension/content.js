// Phase 0 spike probe — content script.
//
// Performs the sequence a password manager depends on:
//   1. locate the login form
//   2. write into its fields
//   3. talk to the background service worker
//   4. publish the outcome where the native harness can read it
//
// Results land on document.documentElement.dataset.koukeSpike so the DebugAutomation
// harness can assert on them via evaluateJavaScript.

const SENTINEL_USERNAME = "kouke-spike-user";
const SENTINEL_PASSWORD = "kouke-spike-pass";
const RESULT_DATASET_KEY = "koukeSpike";

function findLoginFields() {
  const passwordField = document.querySelector('input[type="password"]');
  if (!passwordField) {
    return null;
  }

  const form = passwordField.closest("form") || document;
  const usernameField = form.querySelector(
    'input[type="text"], input[type="email"], input[name*="user" i], input[autocomplete="username"]'
  );

  return { usernameField, passwordField };
}

function fillFields(fields) {
  if (fields.usernameField) {
    fields.usernameField.value = SENTINEL_USERNAME;
    fields.usernameField.dispatchEvent(new Event("input", { bubbles: true }));
  }
  fields.passwordField.value = SENTINEL_PASSWORD;
  fields.passwordField.dispatchEvent(new Event("input", { bubbles: true }));
}

function publishResult(result) {
  document.documentElement.dataset[RESULT_DATASET_KEY] = JSON.stringify(result);
}

async function probeBackgroundWorker() {
  try {
    const reply = await chrome.runtime.sendMessage({ type: "spike-ping" });
    return { ok: reply?.type === "spike-pong", detail: reply?.detail ?? null };
  } catch (error) {
    return { ok: false, detail: String(error) };
  }
}

async function run() {
  const result = {
    contentScriptRan: true,
    url: location.href,
    formFound: false,
    usernameFilled: false,
    passwordFilled: false,
    backgroundReachable: false,
    backgroundDetail: null,
    error: null
  };

  try {
    const fields = findLoginFields();
    if (fields) {
      result.formFound = true;
      fillFields(fields);
      result.usernameFilled = fields.usernameField?.value === SENTINEL_USERNAME;
      result.passwordFilled = fields.passwordField.value === SENTINEL_PASSWORD;
    }

    const background = await probeBackgroundWorker();
    result.backgroundReachable = background.ok;
    result.backgroundDetail = background.detail;
  } catch (error) {
    result.error = String(error);
  }

  publishResult(result);
}

run();
