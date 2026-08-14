#!/usr/bin/env python3
"""
iCloud keychain migration verification.

Saved logins moved from the legacy file-based keychain to the data protection
keychain so iCloud can synchronize them. The two keychains cannot see each
other, so the move is a real copy — and a copy is where data goes missing.
These checks are mostly about that risk:

  * the destination keychain is actually reachable (it needs an entitlement
    only a provisioning profile grants, and fails closed without it),
  * migrating brings old logins across intact,
  * migrating never removes the originals, and
  * a login saved after the move is not overwritten by its older copy.

All harness credentials live under *.kouke-test.invalid — a suffix reserved by
RFC 2606 that can never be a real site — and the app refuses any other host, so
a run cannot read or delete a password you actually saved.

Usage: scripts/verify-icloud-sync.py [--keep-running]
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from spike_harness import (
    AppSession, SpikeFailure, check,
    GREEN, RED, YELLOW, RESET,
)

MIGRATION_HOST = "migrated.kouke-test.invalid"
CONFLICT_HOST = "conflict.kouke-test.invalid"
DIRECT_HOST = "direct.kouke-test.invalid"

USERNAME = "kouke-harness-alice"

# Distinct enough that a mix-up between them cannot pass by coincidence.
LEGACY_PASSWORD = "password-from-the-old-keychain"
NEWER_PASSWORD = "password-saved-after-the-move"

# Configurations the probe reports on, and whether iCloud sync depends on them.
REQUIRED_KEYCHAINS = ("dataProtection", "dataProtectionSynchronizable")


def ask(client, command, **arguments):
    return json.loads(client.send(command, **arguments))


def reset(client):
    """Clears both keychains of harness data and the migration flag."""
    ask(client, "credential_reset_test_data")


def verify_destination_keychain_is_reachable(client):
    """Without the entitlement the whole feature fails closed, so this is the
    check that explains every other failure below."""
    print(f"\n{YELLOW}1. Destination keychain{RESET}")
    probe = ask(client, "keychain_probe")
    usable = {entry["label"]: entry for entry in probe["results"]}

    results = [check("build carries the application-identifier entitlement",
                     probe["hasApplicationIdentifier"])]

    for label in REQUIRED_KEYCHAINS:
        entry = usable.get(label, {})
        results.append(check(f"{label} keychain is usable",
                             entry.get("usable", False),
                             entry.get("addMessage", "no result reported")))
        results.append(check(f"{label} reads back what it wrote",
                             entry.get("readBackMatched") is True))
    return results


def verify_stores_are_separate(client):
    """The migration only makes sense if the two keychains really are distinct;
    if new saves also landed in the legacy store the later checks would pass
    for the wrong reason."""
    print(f"\n{YELLOW}2. The two keychains are distinct{RESET}")
    reset(client)

    ask(client, "credential_save", host=DIRECT_HOST,
        username=USERNAME, password=NEWER_PASSWORD)

    legacy = ask(client, "credential_legacy_list")
    hosts = [entry["host"] for entry in legacy["credentials"]]

    return [check("a normal save does not touch the old keychain",
                  DIRECT_HOST not in hosts,
                  f"legacy hosts: {hosts}")]


def verify_migration_copies_old_logins(client):
    print(f"\n{YELLOW}3. Migration brings old logins across{RESET}")
    reset(client)

    ask(client, "credential_legacy_save", host=MIGRATION_HOST,
        username=USERNAME, password=LEGACY_PASSWORD)

    before = ask(client, "credential_read", host=MIGRATION_HOST, username=USERNAME)
    results = [check("the login is invisible before migrating",
                     before["found"] is False)]

    report = ask(client, "credential_migrate")
    results.append(check("migration reported no failures",
                         report["didComplete"], f"failures: {report['failures']}"))
    results.append(check("migration copied the login",
                         report["copied"] >= 1, f"copied={report['copied']}"))

    after = ask(client, "credential_read", host=MIGRATION_HOST, username=USERNAME)
    results.append(check("the login is readable after migrating", after["found"]))
    results.append(check("the password survived intact",
                         after["password"] == LEGACY_PASSWORD,
                         f"got {after['password']!r}"))

    state = ask(client, "credential_migration_state")
    results.append(check("migration is recorded as complete", state["hasCompleted"]))
    return results


def verify_originals_are_kept(client):
    """Deleting the source is what would make a bad migration unrecoverable, so
    the originals are deliberately left in place for a release."""
    print(f"\n{YELLOW}4. Originals are left alone{RESET}")

    legacy = ask(client, "credential_legacy_list")
    hosts = [entry["host"] for entry in legacy["credentials"]]

    return [check("the old keychain still holds the original",
                  MIGRATION_HOST in hosts, f"legacy hosts: {hosts}")]


def verify_newer_password_wins(client):
    """A login present in both stores was saved again after the move, so the
    legacy copy is the older one. Copying it over would silently undo a password
    the user has since changed."""
    print(f"\n{YELLOW}5. A newer password is not overwritten{RESET}")
    reset(client)

    ask(client, "credential_legacy_save", host=CONFLICT_HOST,
        username=USERNAME, password=LEGACY_PASSWORD)
    ask(client, "credential_save", host=CONFLICT_HOST,
        username=USERNAME, password=NEWER_PASSWORD)

    report = ask(client, "credential_migrate")
    results = [check("migration skipped the login it already had",
                     report["skipped"] >= 1, f"skipped={report['skipped']}")]

    current = ask(client, "credential_read", host=CONFLICT_HOST, username=USERNAME)
    results.append(check("the newer password is still in place",
                         current["password"] == NEWER_PASSWORD,
                         f"got {current['password']!r}"))
    return results


def verify_migration_is_repeatable(client):
    """Migration runs at every launch; a second pass must be a no-op rather than
    a source of duplicates or errors."""
    print(f"\n{YELLOW}6. Running it again changes nothing{RESET}")

    report = ask(client, "credential_migrate")
    results = [check("a repeat run copies nothing new",
                     report["copied"] == 0, f"copied={report['copied']}")]
    results.append(check("a repeat run reports no failures",
                         report["didComplete"], f"failures: {report['failures']}"))

    current = ask(client, "credential_read", host=CONFLICT_HOST, username=USERNAME)
    results.append(check("the password is unchanged by the repeat",
                         current["password"] == NEWER_PASSWORD,
                         f"got {current['password']!r}"))
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-running", action="store_true",
                        help="Leave the app open after the run")
    args = parser.parse_args()

    session = AppSession()

    try:
        client = session.start()
        results = []
        results += verify_destination_keychain_is_reachable(client)
        results += verify_stores_are_separate(client)
        results += verify_migration_copies_old_logins(client)
        results += verify_originals_are_kept(client)
        results += verify_newer_password_wins(client)
        results += verify_migration_is_repeatable(client)
        reset(client)
    except SpikeFailure as error:
        print(f"\n{RED}HARNESS ERROR{RESET}: {error}", file=sys.stderr)
        return 2
    finally:
        if not args.keep_running:
            session.stop()

    passed = sum(1 for result in results if result)
    total = len(results)
    print(f"\n{'=' * 46}")
    if passed == total:
        print(f"{GREEN}ICLOUD MIGRATION CHECKS PASSED{RESET}  {passed}/{total}")
        return 0
    print(f"{RED}ICLOUD MIGRATION CHECKS FAILED{RESET}  {passed}/{total}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
