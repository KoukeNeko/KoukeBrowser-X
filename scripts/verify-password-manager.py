#!/usr/bin/env python3
"""
Password manager verification.

Exercises the credential store against the real macOS keychain and asserts the
security rules that make autofill safe. Exits 0 only if every check passes.

All harness credentials live under *.kouke-test.invalid — a suffix reserved by
RFC 2606 that can never be a real site — and the app refuses any other host, so
a run cannot read or delete a password you actually saved.

Usage: scripts/verify-password-manager.py [--keep-running]
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from spike_harness import (
    AppSession, FixtureServer, SpikeFailure, check, wait_until,
    FIXTURES_DIR, GREEN, RED, YELLOW, RESET,
)

FILL_USERNAME = "alice@example.com"

# Characters that would break out of a naively built JavaScript expression.
# No newline: a single-line <input> cannot hold one, so expecting it back would
# be testing the HTML spec rather than the escaping.
FILL_PASSWORD = 'p@ss"with\'quotes\\backslash</script>&amp;'

# Fixtures are served from loopback, and the app only lets the harness store
# credentials there under this username prefix.
LOOPBACK_HOST = "127.0.0.1"
HARNESS_USERNAME = "kouke-harness-alice"

READ_FIELDS_JS = """
JSON.stringify({
  username: (document.querySelector('input[autocomplete="username"]') || {}).value || '',
  password: (document.querySelector('input[type="password"]') || {}).value || ''
})
"""

# Types a login in and submits it, the way a person signing in would.
SUBMIT_LOGIN_JS = f"""
(() => {{
  const username = document.querySelector('input[autocomplete="username"]');
  const password = document.querySelector('input[type="password"]');
  username.value = {json.dumps(HARNESS_USERNAME)};
  username.dispatchEvent(new Event('input', {{ bubbles: true }}));
  password.value = {json.dumps(FILL_PASSWORD)};
  password.dispatchEvent(new Event('input', {{ bubbles: true }}));
  document.getElementById('login-form').dispatchEvent(
    new Event('submit', {{ bubbles: true, cancelable: true }}));
  return 'submitted';
}})()
"""

# Drives the staged fixture the way a real one behaves: the username is entered
# first, the step that holds it is hidden, and only then is the password sent.
SUBMIT_TWO_STEP_JS = f"""
(() => {{
  const username = document.querySelector('input[autocomplete="username"]');
  username.value = {json.dumps(HARNESS_USERNAME)};
  username.dispatchEvent(new Event('input', {{ bubbles: true }}));
  document.getElementById('next').click();
  const password = document.querySelector('input[type="password"]');
  password.value = {json.dumps(FILL_PASSWORD)};
  password.dispatchEvent(new Event('input', {{ bubbles: true }}));
  document.getElementById('login-form').dispatchEvent(
    new Event('submit', {{ bubbles: true, cancelable: true }}));
  return 'submitted';
}})()
"""

TEST_HOST = "example.kouke-test.invalid"
OTHER_HOST = "other.kouke-test.invalid"
TEST_USERNAME = "alice@example.com"
TEST_PASSWORD = "correct horse battery staple"
UPDATED_PASSWORD = "a different secret entirely"


def verify_storage_round_trip(client):
    print(f"\n{YELLOW}1. Storage round trip{RESET}")
    results = []

    client.send("credential_reset_test_data")

    saved = json.loads(client.send("credential_save", host=TEST_HOST,
                                   username=TEST_USERNAME, password=TEST_PASSWORD))
    results.append(check("credential saved", saved.get("saved") is True,
                         str(saved.get("error") or "")))

    read = json.loads(client.send("credential_read", host=TEST_HOST, username=TEST_USERNAME))
    results.append(check("password reads back identically",
                         read.get("password") == TEST_PASSWORD,
                         "stored value did not match" if read.get("password") != TEST_PASSWORD else ""))

    listed = json.loads(client.send("credential_list"))
    results.append(check("credential appears in the list", listed.get("count") == 1,
                         f"count={listed.get('count')}"))

    return results


def verify_update_and_delete(client):
    print(f"\n{YELLOW}2. Update and delete{RESET}")
    results = []

    client.send("credential_save", host=TEST_HOST,
                username=TEST_USERNAME, password=UPDATED_PASSWORD)
    read = json.loads(client.send("credential_read", host=TEST_HOST, username=TEST_USERNAME))
    results.append(check("re-saving replaces the password",
                         read.get("password") == UPDATED_PASSWORD))

    listed = json.loads(client.send("credential_list"))
    results.append(check("re-saving does not duplicate the entry",
                         listed.get("count") == 1, f"count={listed.get('count')}"))

    client.send("credential_delete", host=TEST_HOST, username=TEST_USERNAME)
    read = json.loads(client.send("credential_read", host=TEST_HOST, username=TEST_USERNAME))
    results.append(check("deleted password is gone", read.get("found") is False))

    return results


def verify_host_isolation(client):
    print(f"\n{YELLOW}3. Host isolation{RESET}")
    results = []

    client.send("credential_reset_test_data")
    client.send("credential_save", host=TEST_HOST,
                username=TEST_USERNAME, password=TEST_PASSWORD)

    other = json.loads(client.send("credential_read", host=OTHER_HOST, username=TEST_USERNAME))
    results.append(check("a different host cannot read the password",
                         other.get("found") is False))

    scoped = json.loads(client.send("credential_list", host=OTHER_HOST))
    results.append(check("a different host lists nothing", scoped.get("count") == 0,
                         f"count={scoped.get('count')}"))

    client.send("credential_reset_test_data")
    return results


def verify_policy_rules(client):
    """The security decisions from the plan, asserted directly.

    A lookalike domain must not inherit another site's credentials, and plaintext
    HTTP must never be offered autofill.
    """
    print(f"\n{YELLOW}4. Eligibility policy{RESET}")
    results = []

    cases = [
        ("https://example.com/login", True, "example.com", "https is eligible"),
        ("http://example.com/login", False, "example.com", "plain http is refused"),
        ("https://evil-example.com/", True, "evil-example.com",
         "lookalike domain resolves to its own host, not example.com"),
        ("https://example.com.evil.net/", True, "example.com.evil.net",
         "suffix attack resolves to the attacker host, not example.com"),
        ("kouke:settings", False, None, "internal pages are refused"),
        ("file:///etc/passwd", False, None, "file urls are refused"),
    ]

    for url, expected_eligible, expected_host, description in cases:
        verdict = json.loads(client.send("credential_policy", url=url))
        actual_host = verdict.get("host")
        actual_host = None if actual_host is None else actual_host

        passed = (verdict.get("eligible") is expected_eligible
                  and actual_host == expected_host)
        results.append(check(description, passed,
                             f"eligible={verdict.get('eligible')} host={actual_host}"))

    return results


def verify_harness_guard(client):
    print(f"\n{YELLOW}5. Harness safety guard{RESET}")

    try:
        client.send("credential_read", host="github.com", username="anyone")
        return [check("harness refuses non-test hosts", False,
                      "a real host was accepted")]
    except SpikeFailure as error:
        return [check("harness refuses non-test hosts", "kouke-test.invalid" in str(error))]


def describe_page(client, server, page):
    client.send("load_page", url=f"{server.base_url}/{page}", timeout=60)
    return json.loads(client.send("autofill_describe", timeout=30))


def verify_form_detection(client, server):
    """Detection across page shapes, including the two that must be refused."""
    print(f"\n{YELLOW}6. Login form detection{RESET}")
    results = []

    standard = describe_page(client, server, "standard-login.html")
    results.append(check("standard login form detected",
                         standard.get("hasLoginForm") is True))
    results.append(check("standard form exposes a username field",
                         standard.get("hasUsernameField") is True))

    autocomplete_off = describe_page(client, server, "autocomplete-off.html")
    results.append(check("autocomplete=off form is still detected",
                         autocomplete_off.get("hasLoginForm") is True))

    client.send("load_page", url=f"{server.base_url}/spa-login.html", timeout=60)
    spa = wait_until(
        lambda: json.loads(client.send("autofill_describe", timeout=30)),
        lambda value: value.get("hasLoginForm") is True,
    )
    results.append(check("form rendered after load is detected",
                         spa.get("hasLoginForm") is True))

    # The security-critical cases.
    hidden = describe_page(client, server, "hidden-trap.html")
    results.append(check("hidden login form is REFUSED",
                         hidden.get("hasLoginForm") is False,
                         "a concealed form would be filled invisibly"))

    framed = describe_page(client, server, "iframe-login.html")
    results.append(check("form inside a frame is REFUSED",
                         framed.get("hasLoginForm") is False,
                         "an embedding page must not reach a framed login"))

    return results


def verify_filling(client, server):
    print(f"\n{YELLOW}7. Filling{RESET}")
    results = []

    client.send("load_page", url=f"{server.base_url}/standard-login.html", timeout=60)
    outcome = json.loads(client.send("autofill_fill", timeout=30,
                                     username=FILL_USERNAME, password=FILL_PASSWORD))
    results.append(check("fill reported success", outcome.get("filled") is True))

    fields = json.loads(outcome.get("fields") or "{}")
    results.append(check("username written to the page",
                         fields.get("username") == FILL_USERNAME,
                         f"got {fields.get('username')!r}"))
    results.append(check("password with quotes and backslashes written intact",
                         fields.get("password") == FILL_PASSWORD,
                         f"got {fields.get('password')!r}"))

    # Autofill must never send the form; submitting is the user's decision.
    still_there = json.loads(client.send("autofill_describe", timeout=30))
    results.append(check("form was not submitted", still_there.get("hasLoginForm") is True))

    print(f"\n{YELLOW}8. Filling is refused where it must be{RESET}")
    client.send("load_page", url=f"{server.base_url}/hidden-trap.html", timeout=60)
    trap = json.loads(client.send("autofill_fill", timeout=30,
                                  username=FILL_USERNAME, password=FILL_PASSWORD))
    trap_fields = json.loads(trap.get("fields") or "{}")
    results.append(check("hidden form is not filled",
                         trap.get("filled") is False and not trap_fields.get("password"),
                         f"filled={trap.get('filled')}"))

    client.send("load_page", url=f"{server.base_url}/iframe-login.html", timeout=60)
    framed = json.loads(client.send("autofill_fill", timeout=30,
                                    username=FILL_USERNAME, password=FILL_PASSWORD))
    results.append(check("framed form is not filled", framed.get("filled") is False,
                         f"filled={framed.get('filled')}"))

    return results


def verify_end_to_end_flow(client, server):
    """The journey a real user takes, driven through the same calls the prompt
    card's buttons make.
    """
    print(f"\n{YELLOW}9. End-to-end: offer, fill, save{RESET}")
    results = []

    client.send("credential_reset_test_data")
    client.send("credential_save", host=LOOPBACK_HOST,
                username=HARNESS_USERNAME, password=FILL_PASSWORD)

    # Visiting a site with a saved login should raise a fill offer by itself.
    client.send("load_page", url=f"{server.base_url}/standard-login.html", timeout=60)
    prompt = wait_until(
        lambda: json.loads(client.send("autofill_prompt", timeout=30)),
        lambda value: value.get("kind") == "fill",
    )
    results.append(check("fill offer raised for a known site",
                         prompt.get("kind") == "fill", f"kind={prompt.get('kind')}"))
    results.append(check("offer lists the saved username",
                         HARNESS_USERNAME in (prompt.get("usernames") or []),
                         str(prompt.get("usernames"))))

    # Nothing should have reached the page before the user chose.
    before = json.loads(client.send("autofill_describe", timeout=30))
    results.append(check("nothing filled before the user chooses",
                         before.get("usernameValue") == "",
                         f"username box held {before.get('usernameValue')!r}"))

    client.send("autofill_prompt_accept", timeout=30, username=HARNESS_USERNAME)
    after = wait_until(
        lambda: json.loads(client.send("eval_js", timeout=30, script=READ_FIELDS_JS)),
        lambda value: value.get("password") == FILL_PASSWORD,
    )
    results.append(check("accepting the offer fills the page",
                         after.get("password") == FILL_PASSWORD,
                         f"got {after.get('password')!r}"))

    dismissed = wait_until(
        lambda: json.loads(client.send("autofill_prompt", timeout=30)),
        lambda value: value.get("kind") == "none",
    )
    results.append(check("prompt clears after filling",
                         dismissed.get("kind") == "none", f"kind={dismissed.get('kind')}"))

    # A submitted login the browser has never seen should raise a save offer.
    print(f"\n{YELLOW}10. End-to-end: save a new login{RESET}")
    client.send("credential_reset_test_data")
    client.send("load_page", url=f"{server.base_url}/standard-login.html", timeout=60)
    client.send("eval_js", timeout=30, script=SUBMIT_LOGIN_JS)
    save_prompt = wait_until(
        lambda: json.loads(client.send("autofill_prompt", timeout=30)),
        lambda value: value.get("kind") == "save",
    )
    results.append(check("save offer raised after submitting",
                         save_prompt.get("kind") == "save", f"kind={save_prompt.get('kind')}"))
    results.append(check("save offer names the submitted user",
                         save_prompt.get("username") == HARNESS_USERNAME,
                         str(save_prompt.get("username"))))

    client.send("autofill_prompt_accept", timeout=30)
    stored = json.loads(client.send("credential_read", host=LOOPBACK_HOST,
                                    username=HARNESS_USERNAME))
    results.append(check("accepting the offer stores the password",
                         stored.get("password") == FILL_PASSWORD,
                         f"got {stored.get('password')!r}"))

    # A staged sign-in hides the username box before the password is sent. The
    # username is still the user's own input, and a login saved without one can
    # never be offered back, so losing it here is the difference between a
    # usable entry and a useless one.
    print(f"\n{YELLOW}11. End-to-end: save from a two-step sign-in{RESET}")
    client.send("credential_reset_test_data")
    client.send("load_page", url=f"{server.base_url}/two-step-login.html", timeout=60)
    client.send("eval_js", timeout=30, script=SUBMIT_TWO_STEP_JS)
    staged_prompt = wait_until(
        lambda: json.loads(client.send("autofill_prompt", timeout=30)),
        lambda value: value.get("kind") == "save",
    )
    results.append(check("save offer raised for a staged sign-in",
                         staged_prompt.get("kind") == "save",
                         f"kind={staged_prompt.get('kind')}"))
    results.append(check("the hidden username step still names the user",
                         staged_prompt.get("username") == HARNESS_USERNAME,
                         f"got {staged_prompt.get('username')!r}"))

    client.send("credential_reset_test_data")
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-running", action="store_true",
                        help="Leave the app open after the run")
    args = parser.parse_args()

    session = AppSession()
    server = FixtureServer(FIXTURES_DIR / "pages").start()
    print(f"Serving fixtures at: {server.base_url}")

    try:
        client = session.start()
        results = []
        results += verify_storage_round_trip(client)
        results += verify_update_and_delete(client)
        results += verify_host_isolation(client)
        results += verify_policy_rules(client)
        results += verify_harness_guard(client)
        results += verify_form_detection(client, server)
        results += verify_filling(client, server)
        results += verify_end_to_end_flow(client, server)
    except SpikeFailure as error:
        print(f"\n{RED}HARNESS ERROR{RESET}: {error}", file=sys.stderr)
        return 2
    finally:
        server.stop()
        if not args.keep_running:
            session.stop()

    passed = sum(1 for result in results if result)
    total = len(results)
    print(f"\n{'=' * 46}")
    if passed == total:
        print(f"{GREEN}PASSWORD MANAGER CHECKS PASSED{RESET}  {passed}/{total}")
        return 0
    print(f"{RED}PASSWORD MANAGER CHECKS FAILED{RESET}  {passed}/{total}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
