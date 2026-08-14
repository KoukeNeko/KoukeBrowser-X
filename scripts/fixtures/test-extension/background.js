// Phase 0 spike probe — background service worker.
//
// Exercises the two background capabilities a password manager needs:
// message passing with content scripts, and extension-local storage.

const STORAGE_KEY = "kouke-spike-ping-count";

async function recordPing() {
  const stored = await chrome.storage.local.get(STORAGE_KEY);
  const count = (stored[STORAGE_KEY] ?? 0) + 1;
  await chrome.storage.local.set({ [STORAGE_KEY]: count });
  return count;
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "spike-ping") {
    return false;
  }

  recordPing()
    .then((count) => {
      sendResponse({
        type: "spike-pong",
        detail: `storage ok, ping #${count}`
      });
    })
    .catch((error) => {
      sendResponse({ type: "spike-pong", detail: `storage failed: ${error}` });
    });

  // Keeps the message channel open for the async sendResponse above.
  return true;
});
