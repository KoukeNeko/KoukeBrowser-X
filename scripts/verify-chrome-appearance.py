#!/usr/bin/env python3
"""
Chrome appearance verification.

Asserts that each ChromeAppearance reaches the screen, under both tab bar
styles. Two things have to be true together for translucency, and checking
only one of them passes while the window still looks flat grey:

  * the window must stop painting an opaque background, otherwise the
    materials sample it instead of the desktop, and
  * the material view itself must actually be installed in the hierarchy.

So every case asserts the window state and the live NSView tree, and then
that the tab strip still draws something — dropping the opaque background is
exactly the change that can leave the chrome blank.

Usage: scripts/verify-chrome-appearance.py [--keep-running]
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from spike_harness import (
    AppSession, SpikeFailure, check, wait_until,
    GREEN, RED, RESET,
)

BLUR_VIEW = "NSVisualEffectView"
GLASS_VIEW = "NSGlassEffectView"

# Each translucent page's material is identified by its own URL. The chrome
# bands put views of the same class in the same window, and hidden tabs stay in
# the view tree, so neither the class name nor a shared identifier could say
# which page went translucent.
BLANK_PAGE_URL = "kouke:blank"
TRANSLUCENT_PAGE_URLS = (BLANK_PAGE_URL, "kouke:settings",
                         "kouke:about", "kouke:help")


def page_material_id(page_url):
    return f"KoukeChromePage:{page_url}"


# The address bar's own materials: the band behind it, and the glass capsule
# around the input under Liquid Glass. Both disappear when the address bar is
# opted out of the style.
ADDRESS_BAR_MATERIAL_ID = "KoukeChromeAddressBar"
ADDRESS_FIELD_MATERIAL_ID = "KoukeChromeAddressField"

TAB_BAR_STYLES = ("normal", "compact")

# Alpha of the window's own background colour. Translucent chrome needs it
# fully clear; solid chrome paints TitleBarBg over it.
CLEAR_ALPHA = 0.0
OPAQUE_ALPHA = 1.0
ALPHA_TOLERANCE = 0.01

SETTLE_TIMEOUT_SECONDS = 5.0

# The window is pinned so the strip sample below lands inside it whatever size
# the window happened to restore at.
PROBE_WINDOW_WIDTH = 1100
PROBE_WINDOW_HEIGHT = 700

# A band across the tab strip, in points, clear of the traffic lights on the
# left and of the window edge on the right.
STRIP_TOP, STRIP_BOTTOM = 4, 36
STRIP_LEFT, STRIP_RIGHT = 90, 400
STRIP_SAMPLE_STEP_Y, STRIP_SAMPLE_STEP_X = 4, 10

# Tab labels, borders and the active tab fill together produce far more than
# this. A blank band produces one.
MINIMUM_STRIP_COLORS = 4
RETINA_WIDTH_THRESHOLD = 2000

# Points inside the first and second tab, clear of their icons and labels, and
# one just past the last tab where the bare band shows.
#
# The band's colour is never asserted on its own: it is blurring whatever is
# behind the window, so it changes with the desktop and moves between runs of
# the same build. It is only ever compared against a tab in the same snapshot,
# close enough that both sit over the same backdrop.
TAB_FILL_SAMPLE_Y = 20
SELECTED_TAB_SAMPLE_X = 150
UNSELECTED_TAB_SAMPLE_X = 350
BAND_SAMPLE_X = 600

# Compact draws its unselected tabs with no fill at all, so there is no second
# fill to compare there; the swap is checked on the normal tab bar.
TAB_FILL_CHECK_STYLE = "normal"


class AppearanceExpectation:
    """What one appearance should produce in the window and its view tree."""

    def __init__(self, opaque, required_view, forbidden_views, translucent_page):
        self.opaque = opaque
        self.required_view = required_view
        self.forbidden_views = forbidden_views
        self.translucent_page = translucent_page


def expectations_for(glass_available):
    """Liquid Glass degrades to Normal's blur below macOS 26, so what counts
    as correct there depends on the machine the run happens on."""
    glass_view = GLASS_VIEW if glass_available else BLUR_VIEW
    return {
        "solid": AppearanceExpectation(
            opaque=True, required_view=None,
            forbidden_views=(BLUR_VIEW, GLASS_VIEW),
            translucent_page=False),
        "normal": AppearanceExpectation(
            opaque=False, required_view=BLUR_VIEW,
            forbidden_views=(GLASS_VIEW,),
            translucent_page=True),
        "liquid_glass": AppearanceExpectation(
            opaque=False, required_view=glass_view,
            forbidden_views=(),
            translucent_page=True),
    }


def read_state(client):
    client.send("state")
    return json.loads((client.working_dir / "state.json").read_text())


def browser_window(state):
    """The window owning a viewModel. Panels and popovers have no tabs and
    must not be mistaken for the browser window."""
    windows = [window for window in state["windows"] if "tabs" in window]
    if not windows:
        raise SpikeFailure("no browser window found in state.json")
    return windows[0]


def ensure_page_is_active(client, page_url):
    """A page only paints while it is the visible tab, so each page under test
    has to be brought to the front first."""
    window = browser_window(read_state(client))
    active = next((tab for tab in window["tabs"]
                   if tab["id"] == window.get("activeTabId")), None)
    if active and active["url"] == page_url:
        return
    existing = next((tab for tab in window["tabs"] if tab["url"] == page_url), None)
    if existing:
        client.send("switch_tab", tab=existing["id"])
    else:
        client.send("add_tab", url=page_url)


def prepare_tabs_for_fill_check(client):
    """Two tabs with the first one — the blank page — active.

    The fill check reads a fixed point in each of the first two tabs, and a
    strip with a single tab has no unselected fill to read.
    """
    window = browser_window(read_state(client))
    if len(window["tabs"]) < 2:
        client.send("add_tab", url=BLANK_PAGE_URL)
        window = browser_window(read_state(client))

    first = window["tabs"][0]
    if first["url"] != BLANK_PAGE_URL:
        raise SpikeFailure(
            f"expected the first tab to be {BLANK_PAGE_URL}, got {first['url']}")
    client.send("switch_tab", tab=first["id"])


def read_hierarchy(client, window_number):
    client.send("snapshot")
    return (client.working_dir / f"hierarchy-{window_number}.txt").read_text()


def sample_strip_pixels(client, window_number):
    """The pixels the tab strip draws.

    The snapshot is the window rendering itself, so a behind-window blur
    contributes nothing here — which is the point: what is being checked is
    that the tabs on top of it still draw.
    """
    from PIL import Image

    snapshot = Image.open(
        client.working_dir / f"snapshot-{window_number}.png").convert("RGB")
    scale = 2 if snapshot.size[0] > RETINA_WIDTH_THRESHOLD else 1
    pixels = []
    for y in range(STRIP_TOP * scale, STRIP_BOTTOM * scale, STRIP_SAMPLE_STEP_Y):
        for x in range(STRIP_LEFT * scale, STRIP_RIGHT * scale, STRIP_SAMPLE_STEP_X):
            pixels.append(snapshot.getpixel((x, y)))
    return pixels


def sample_tab_fills(client, window_number):
    """(selected fill, unselected fill, bare band).

    Read at fixed points inside the first two tabs rather than as the band's
    commonest colours: the band behind the tabs renders differently once the
    window is translucent, so only a within-snapshot comparison is meaningful.
    The window is pinned to a known size and the first tab is kept active, so
    these points land in the same tabs every run.
    """
    from PIL import Image

    snapshot = Image.open(
        client.working_dir / f"snapshot-{window_number}.png").convert("RGB")
    scale = 2 if snapshot.size[0] > RETINA_WIDTH_THRESHOLD else 1
    return tuple(snapshot.getpixel((x * scale, TAB_FILL_SAMPLE_Y * scale))
                 for x in (SELECTED_TAB_SAMPLE_X, UNSELECTED_TAB_SAMPLE_X,
                           BAND_SAMPLE_X))


def check_page_material(hierarchy, page_url, label, expectation):
    """Whether the page painted its own material, by that page's identifier."""
    found = page_material_id(page_url) in hierarchy
    state = "present" if expectation.translucent_page else "absent"
    return check(f"{label}: {page_url} material {state}",
                 found == expectation.translucent_page, f"found={found}")


def verify_page_material(client, page_url, appearance, expectation):
    """A page other than the blank one. The window and chrome assertions do not
    depend on which page is showing, so only the page's own background is
    checked here."""
    client.send("set_appearance", value=appearance)
    state = settled_state(client, appearance)
    window = browser_window(state)
    hierarchy = read_hierarchy(client, window["windowNumber"])
    return [check_page_material(hierarchy, page_url, appearance, expectation)]


def settled_state(client, appearance):
    """Window properties are pushed asynchronously, so poll rather than sleep."""
    return wait_until(
        lambda: read_state(client),
        lambda state: state.get("chromeAppearance") == appearance,
        timeout=SETTLE_TIMEOUT_SECONDS,
    )


def verify_appearance(client, tab_bar_style, appearance, expectation, tab_fills):
    client.send("set_appearance", value=appearance)
    state = settled_state(client, appearance)
    window = browser_window(state)
    hierarchy = read_hierarchy(client, window["windowNumber"])

    label = f"{tab_bar_style}/{appearance}"
    results = [
        check(f"{label}: window isOpaque is {expectation.opaque}",
              window["isOpaque"] == expectation.opaque,
              f"got {window['isOpaque']}"),
    ]

    expected_alpha = OPAQUE_ALPHA if expectation.opaque else CLEAR_ALPHA
    actual_alpha = window["backgroundAlpha"]
    results.append(check(
        f"{label}: window background alpha is {expected_alpha}",
        abs(actual_alpha - expected_alpha) < ALPHA_TOLERANCE,
        f"got {actual_alpha}"))

    if expectation.required_view:
        results.append(check(
            f"{label}: {expectation.required_view} is in the view tree",
            expectation.required_view in hierarchy))

    for forbidden in expectation.forbidden_views:
        results.append(check(
            f"{label}: no {forbidden} in the view tree",
            forbidden not in hierarchy))

    results.append(check_page_material(hierarchy, BLANK_PAGE_URL, label, expectation))

    pixels = sample_strip_pixels(client, window["windowNumber"])
    distinct = len(set(pixels))
    results.append(check(
        f"{label}: tab strip still renders",
        distinct >= MINIMUM_STRIP_COLORS,
        f"{distinct} distinct colours"))

    if tab_bar_style == TAB_FILL_CHECK_STYLE:
        tab_fills[appearance] = sample_tab_fills(client, window["windowNumber"])
    return results


def verify_tab_fills(tab_fills):
    """Normal keeps Solid's selected fill and drops the unselected one, so an
    unselected tab reads as part of the band. Liquid Glass replaces the
    selected fill outright."""
    solid_selected, solid_unselected, solid_band = tab_fills["solid"]
    normal_selected, normal_unselected, normal_band = tab_fills["normal"]
    glass_selected, glass_unselected, glass_band = tab_fills["liquid_glass"]

    return [
        check("solid: every tab has a fill, and the selected one differs",
              solid_selected != solid_unselected != solid_band,
              f"selected={solid_selected} unselected={solid_unselected} "
              f"band={solid_band}"),
        check("normal: the selected tab keeps solid's fill",
              normal_selected == solid_selected,
              f"normal={normal_selected} solid={solid_selected}"),
        check("normal: an unselected tab is indistinguishable from the band",
              normal_unselected == normal_band,
              f"unselected={normal_unselected} band={normal_band}"),
        check("liquid glass: an unselected tab is indistinguishable from the band",
              glass_unselected == glass_band,
              f"unselected={glass_unselected} band={glass_band}"),
        check("liquid glass: the selected tab uses neither flat fill",
              glass_selected not in (solid_selected, solid_unselected),
              f"selected={glass_selected}"),
    ]


def verify_address_bar_opt_out(client):
    """The address bar can be left out of the style while the tab bar keeps it,
    so its materials have to come and go with that setting alone."""
    # Compact merges the address field into the active tab, so there is no
    # address bar of its own to opt out of.
    client.send("set_style", value="normal")
    results = []
    for appearance in ("normal", "liquid_glass"):
        client.send("set_appearance", value=appearance)
        settled_state(client, appearance)

        for follows in (True, False):
            client.send("set_address_bar_style", value=follows)
            state = wait_until(
                lambda: read_state(client),
                lambda dump: dump.get("addressBarFollowsChromeStyle") == follows,
                timeout=SETTLE_TIMEOUT_SECONDS)
            window = browser_window(state)
            hierarchy = read_hierarchy(client, window["windowNumber"])

            label = f"{appearance}/address bar {'on' if follows else 'off'}"
            found_band = ADDRESS_BAR_MATERIAL_ID in hierarchy
            results.append(check(
                f"{label}: band material {'present' if follows else 'absent'}",
                found_band == follows, f"found={found_band}"))

            # The capsule only exists under Liquid Glass to begin with. Below
            # macOS 26 it is a blur wearing the same identifier, so this holds
            # either way.
            wants_field = follows and appearance == "liquid_glass"
            found_field = ADDRESS_FIELD_MATERIAL_ID in hierarchy
            results.append(check(
                f"{label}: input capsule {'present' if wants_field else 'absent'}",
                found_field == wants_field, f"found={found_field}"))

    client.send("set_address_bar_style", value=True)
    return results


def verify_all_appearances(client):
    state = read_state(client)
    glass_available = state.get("glassAvailable", False)
    print(f"Glass material available on this machine: {glass_available}")
    expectations = expectations_for(glass_available)

    client.send("window_frame", w=PROBE_WINDOW_WIDTH, h=PROBE_WINDOW_HEIGHT)
    prepare_tabs_for_fill_check(client)

    results = []
    tab_fills = {}
    for tab_bar_style in TAB_BAR_STYLES:
        print(f"\n{GREEN}Tab bar style: {tab_bar_style}{RESET}")
        client.send("set_style", value=tab_bar_style)
        for appearance, expectation in expectations.items():
            results += verify_appearance(client, tab_bar_style,
                                         appearance, expectation, tab_fills)

    print(f"\n{GREEN}Tab fills ({TAB_FILL_CHECK_STYLE} tab bar){RESET}")
    results += verify_tab_fills(tab_fills)

    for page_url in TRANSLUCENT_PAGE_URLS:
        if page_url == BLANK_PAGE_URL:
            continue  # already covered above, under both tab bar styles
        print(f"\n{GREEN}Page: {page_url}{RESET}")
        ensure_page_is_active(client, page_url)
        for appearance, expectation in expectations.items():
            results += verify_page_material(client, page_url,
                                            appearance, expectation)

    print(f"\n{GREEN}Address bar opt-out{RESET}")
    results += verify_address_bar_opt_out(client)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-running", action="store_true",
                        help="Leave the app open after the run")
    args = parser.parse_args()

    session = AppSession()
    try:
        client = session.start()
        results = verify_all_appearances(client)
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
        print(f"{GREEN}CHROME APPEARANCE CHECKS PASSED{RESET}  {passed}/{total}")
        return 0
    print(f"{RED}CHROME APPEARANCE CHECKS FAILED{RESET}  {passed}/{total}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
