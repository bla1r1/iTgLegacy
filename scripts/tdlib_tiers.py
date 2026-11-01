#!/usr/bin/env python3
"""Split the functions this client skips into buildable-later and never.

The coverage script answers "what is not called" and "what was skipped on
purpose". That second list is not one thing: some of it is a feature this
client could grow later (stories, group calls, business accounts), and some
of it needs a stack the oldest supported iOS cannot carry (a browser engine,
a payment stack, a TON wallet, speech recognition) or belongs to a bot
account, which this app never signs into.

Tier 1 - done: the functions `--wired` lists. Not repeated here.
Tier 2 - buildable later: skipped today, but a screen and the existing
         client surface could carry it.
Tier 3 - never for this client: bot-account-only, or needs an external
         stack this app will not have.

    python3 scripts/tdlib_tiers.py --counts   tier sizes
    python3 scripts/tdlib_tiers.py --tier2    buildable-later names, grouped
    python3 scripts/tdlib_tiers.py --tier3    never names, grouped
    python3 scripts/tdlib_tiers.py --all      both, grouped
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Ordered: the first match wins. Each entry is (tier, category, regex).
RULES = [
    # Ordered: the first match wins. Names are CamelCase, so a pattern is a
    # token, not a lowercase substring: Star is a payment, Start is not.
    # ── Tier 3: needs a stack this iOS cannot run ──────────────────────────
    (3, "Payments, Stars, Premium, gifts and Passport",
     r"Payment|Invoice|Order|Star[A-Z]|Stars|Premium|Boost|Revenue|Withdrawal|"
     r"Affiliate|OnRamp|StoreTransaction|Purchase|Paid|Transaction|Wallet|Ton|"
     r"Gram|Nft|Collectible|Gift|Auction|Passport|Giveaway|Unpaid|Boost|boostChat"),
    (3, "Bot accounts, inline mode and callbacks",
     r"Bot|Inline|Callback|Answer[A-Z]|answer[A-Z]|Prepared|MenuButton|Commands|WebApp|"
     r"WebBrowser|Browser|Oauth|Passkey|GuestQuery|CustomQuery|CustomEvent"),
    (3, "Ads, games and speech recognition",
     r"Sponsored|Advertisement|AdAccount|Game|Speech|ListenToAudio|listenToAudio"),
    (3, "Test, log and environment plumbing",
     r"^test|Log|Json|CurrentWeather|TimeZone|CurrencyExchange|Support|Alarm"),

    # ── Tier 2: a real feature, later ──────────────────────────────────────
    (2, "Stories", r"Story|Stories"),
    (2, "Group and video calls",
     r"GroupCall|VideoChat|Rtmp|ScreenSharing|LiveStream|LiveStory"),
    (2, "Business accounts", r"Business"),
    (2, "Communities, checklists and quick replies",
     r"Community|Checklist|QuickReply|Suggested|FactCheck|RichMessage|"
     r"Summarize|summarize|WithAi"),
    (2, "Emoji status, profile audio and text styles",
     r"EmojiStatus|ProfileAudio|TextCompositionStyle"),
    (2, "Direct message topics", r"DirectMessagesChatTopic"),
    (2, "Dice, alarms and ephemeral content", r"Dice|Alarm|Ephemeral"),
    (2, "Group anti-spam switches", r"AntiSpam"),
    (2, "Web proxy carrier", r"WebProxyCarrier"),
]


def skipped():
    out = subprocess.check_output(
        ["sh", str(ROOT / "scripts" / "tdlib_coverage.sh"), "--skipped"],
        cwd=ROOT, text=True)
    return [line.strip() for line in out.splitlines() if line.strip()]


def classify(names):
    groups = {}
    unknown = []
    for name in names:
        for tier, category, pattern in RULES:
            if re.search(pattern, name):
                groups.setdefault((tier, category), []).append(name)
                break
        else:
            unknown.append(name)
    return groups, unknown


def print_groups(groups, tier):
    for (t, category), names in sorted(groups.items()):
        if t != tier:
            continue
        print(f"\n{category} ({len(names)})")
        for name in sorted(names):
            print(f"  {name}")


def main():
    names = skipped()
    groups, unknown = classify(names)
    tier2 = sum(len(v) for (t, _), v in groups.items() if t == 2)
    tier3 = sum(len(v) for (t, _), v in groups.items() if t == 3)
    mode = sys.argv[1] if len(sys.argv) > 1 else "--counts"

    if mode == "--counts":
        print(f"tier 2 (buildable later): {tier2}")
        for (t, category), v in sorted(groups.items()):
            if t == 2:
                print(f"  {category}: {len(v)}")
        print(f"tier 3 (never): {tier3}")
        for (t, category), v in sorted(groups.items()):
            if t == 3:
                print(f"  {category}: {len(v)}")
        if unknown:
            print(f"unclassified: {len(unknown)}: {', '.join(sorted(unknown))}")
        return 0 if not unknown else 1
    if mode in ("--tier2", "--all"):
        print(f"Tier 2 — buildable later ({tier2})")
        print_groups(groups, 2)
    if mode in ("--tier3", "--all"):
        print(f"\nTier 3 — never for this client ({tier3})")
        print_groups(groups, 3)
    if unknown:
        print(f"\nUnclassified ({len(unknown)}): {', '.join(sorted(unknown))}",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
