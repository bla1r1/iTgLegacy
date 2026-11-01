#!/usr/bin/env python3
"""Split the functions this client skips into buildable-later and never.

The coverage script answers "what is not called" and "what was skipped on
purpose". That second list is not one thing: some of it is a feature this
client could grow later (stories, group calls, business accounts), and some
of it needs a stack the oldest supported iOS cannot carry (a browser engine,
a payment stack, a TON wallet) or belongs to a bot account, which this app
never signs into.

Every Tier 3 group carries its reason. That reason is the audit: if a name
below is a user action this client could send, it belongs in Tier 1, not
here. scripts/tdlib_coverage.sh --skipped still decides membership; this
file only classifies it.

    python3 scripts/tdlib_tiers.py --counts   tier sizes and why
    python3 scripts/tdlib_tiers.py --tier3    never names, grouped, with reasons
    python3 scripts/tdlib_tiers.py --all      both, grouped
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Ordered: the first match wins. Each entry is (tier, category, regex, why).
# Names are CamelCase, so a pattern is a token, not a lowercase substring:
# Star is a payment, Start is not.
RULES = [
    # ── Tier 3: needs a stack this iOS cannot run ──────────────────────────
    (3, "Game score tables (bot-served)",
     r"^(getGameHighScores|getInlineGameHighScores|setGameScore|setInlineGameScore)$",
     "The score table belongs to the bot that owns the game. A user session "
     "may open the game but cannot read or write its scores."),
    (3, "Passport identity documents",
     r"Passport",
     "Telegram Passport needs a document and selfie capture pipeline plus a "
     "2FA-protected identity vault. This client has no verified identity "
     "surface, and a half-built one would send documents into an unverified flow."),
    (3, "TON wallet, on-ramp and NFT withdrawal",
     r"Ton|Wallet|OnRamp|Nft|Withdraw",
     "Needs a TON wallet, an on-ramp provider and blockchain confirmation. "
     "None of that is an iOS 6-12 API, and this app has no wallet backend."),
    (3, "Gift, auction and paid-reaction spending",
     r"^(processGiftPurchaseOffer|sendGiftPurchaseOffer)$",
     "Moves, spends or prices a gift or Star balance this client cannot fund. "
     "The read-only catalogue is implemented; the spending half is not a flow "
     "this build can complete, so it is not drawn as a dead row."),
    (3, "StoreKit purchases and payment providers",
     r"Payment|Invoice|StoreTransaction|Purchase|Premium|Refund|Giveaway|"
     r"AssignStore|AuthenticationPremium|StarPayment|StarGiftPayment|"
     r"StarGiveawayPayment|PremiumGiftPayment|PremiumGiveawayPayment",
     "The request builds a price or checkout record. Taking the money needs "
     "StoreKit or a payment provider this build does not link; showing a "
     "form that cannot charge would be a fake payment flow."),
    (3, "Affiliate and ads monetization",
     r"Affiliate|StarAdAccount",
     "Affiliate programs and the Telegram Ads account attach to an owned bot "
     "or channel and pay out through Fragment. This client has no monetization "
     "backend, so there is nothing to connect or withdraw to."),
    (3, "Gift, auction and paid-reaction spending",
     r"Gift|Auction|Boost|Star|PaidReaction|PaidMessageReaction|PendingPaid|"
     r"Affiliate|BusinessAccountStar|UserChatBoosts|SetPaidMessageReaction|"
     r"BusinessAccountGift|PassportElementErrors",
     "Moves, spends or prices a gift or Star balance this client cannot fund. "
     "The read-only catalogue is implemented; the spending half is not a flow "
     "this build can complete, so it is not drawn as a dead row."),
    (3, "Bot sessions, Web App host and passkeys",
     r"Bot|Inline|Callback|Answer[A-Z]|answer[A-Z]|Prepared|MenuButton|Commands|"
     r"WebApp|WebBrowser|Browser|Oauth|Passkey|GuestQuery|CustomQuery|CustomEvent|"
     r"GuardBot|CheckWebApp|ShareChatWithBot|ShareUsersWithBot",
     "answer* and the command/menu/managed-bot calls require a bot session; the "
     "Web App data calls require a WebView bridge with Telegram's JS host, which "
     "this client does not carry; passkeys need an AuthenticationServices API "
     "newer than iOS 12."),
    (3, "Test harness",
     r"^test",
     "td_api's test* calls exist to exercise the schema. They are not a user "
     "action, have no screen, and adding one would be a test-only row."),
    (3, "Support-staff plumbing",
     r"Support",
     "getSupportName and the two UserSupportInfo calls are for Telegram "
     "support staff. A user session cannot call them."),

    # ── Tier 2: a real feature, later ──────────────────────────────────────
    (2, "Stories", r"Story|Stories",
     "A real feature; the client surface does not draw it yet."),
    (2, "Group and video calls",
     r"GroupCall|VideoChat|Rtmp|ScreenSharing|LiveStream|LiveStory",
     "A real feature needing a media engine this build does not have."),
    (2, "Business accounts", r"Business",
     "A real subscriber feature the account pages do not draw yet."),
    (2, "Communities, checklists and quick replies",
     r"Community|Checklist|QuickReply|Suggested|FactCheck|RichMessage|"
     r"Summarize|summarize|WithAi",
     "A real feature; no screen is built yet."),
    (2, "Emoji status, profile audio and text styles",
     r"EmojiStatus|ProfileAudio|TextCompositionStyle",
     "A real feature; no screen is built yet."),
    (2, "Direct message topics", r"DirectMessagesChatTopic",
     "A real feature; no screen is built yet."),
    (2, "Dice, alarms and ephemeral content", r"Dice|Alarm|Ephemeral",
     "A real feature; no screen is built yet."),
    (2, "Group anti-spam switches", r"AntiSpam",
     "A real admin switch; no screen is built yet."),
    (2, "Web proxy carrier", r"WebProxyCarrier",
     "A real carrier page; no screen is built yet."),
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
        for tier, category, pattern, why in RULES:
            if re.search(pattern, name):
                groups.setdefault((tier, category, why), []).append(name)
                break
        else:
            unknown.append(name)
    return groups, unknown


def print_groups(groups, tier):
    for (t, category, why), names in sorted(groups.items()):
        if t != tier:
            continue
        print(f"\n{category} ({len(names)})")
        print(f"  why: {why}")
        for name in sorted(names):
            print(f"  {name}")


def main():
    names = skipped()
    groups, unknown = classify(names)
    tier2 = sum(len(v) for (t, _, _), v in groups.items() if t == 2)
    tier3 = sum(len(v) for (t, _, _), v in groups.items() if t == 3)
    mode = sys.argv[1] if len(sys.argv) > 1 else "--counts"

    if mode == "--counts":
        print(f"tier 2 (buildable later): {tier2}")
        for (t, category, _), v in sorted(groups.items()):
            if t == 2:
                print(f"  {category}: {len(v)}")
        print(f"tier 3 (never): {tier3}")
        for (t, category, _), v in sorted(groups.items()):
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
