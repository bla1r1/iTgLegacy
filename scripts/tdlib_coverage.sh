#!/bin/sh
# tdlib_coverage.sh - how much of TDLib the app actually calls.
#
# td_api.tl declares every function the protocol offers. The ones this app
# never names are, exactly, what it cannot do. That list is the feature
# backlog, and it needs no walking of the official client to produce.
#
#   sh scripts/tdlib_coverage.sh            counts, and the gap by area
#   sh scripts/tdlib_coverage.sh --list     every function never called
#   sh scripts/tdlib_coverage.sh --used     every function called
#   sh scripts/tdlib_coverage.sh --relevant what is missing and worth having
#   sh scripts/tdlib_coverage.sh --skipped   what is missing and deliberately so
#   sh scripts/tdlib_coverage.sh --wired    called names a screen can reach
#   sh scripts/tdlib_coverage.sh --bare     called names with no caller
#   sh scripts/tdlib_coverage.sh --updates  every update the receive loop drops
#   sh scripts/tdlib_coverage.sh --ignored  updates let through but not acted on
#
# The count reads literal @"@type" : @"name" pairs, so a request whose type is
# assembled from a string at runtime is missed. Treat it as a floor.
#
# A named name is not yet a feature: it can sit inside a method no screen
# calls. --wired/--bare split that gap. scripts/tdlib_wired.py walks the
# method bodies and asks whether src calls the method; tests do not count,
# because a test driving a dead method is false confidence.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TL="$ROOT/tdlib/td/td/generate/scheme/td_api.tl"
[ -f "$TL" ] || { echo "td_api.tl not found at $TL"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

awk '/^---functions---/{f=1;next} f && /^[a-z][a-zA-Z0-9_]* /{print $1}' "$TL" \
    | sort -u > "$TMP/all"
# Both branches of a ternary count: a request sent as
# `favourite ? @"addFavoriteSticker" : @"removeFavoriteSticker"` calls
# whichever branch the run takes. Every string literal is taken and the
# intersection with td_api names does the narrowing, since @"@type" was
# never a good anchor once ternaries moved in.
grep -rhoE '@"[a-zA-Z0-9_]+"' "$ROOT/src" --include='*.m' --include='*.mm' \
    | tr -d ' @"' | sort -u > "$TMP/named"
comm -12 "$TMP/all" "$TMP/named" > "$TMP/used"
comm -23 "$TMP/all" "$TMP/named" > "$TMP/gap"

# Updates are counted apart from functions: a function the app never calls is
# a button that is missing, an update it never reads is a screen that goes
# stale while the app is running. The handled list is one macro, so it is read
# from there rather than from the whole of src/.
awk '/^---functions---/{exit} /^update[a-zA-Z0-9_]* /{print $1}' "$TL" \
    | grep -v '^updates$' | sort -u > "$TMP/upd_all"
grep -oE '"update[a-zA-Z0-9]+"' "$ROOT/src/Core/TGUpdateType.h" \
    | tr -d '"' | sort -u > "$TMP/upd_used"
# TG_IGNORED_UPDATES names the rows the dispatch lets through but does not
# act on: markers for screens that do not exist yet. They are on the record
# so filter and dispatch agree, but counting them as handled overstates the
# number, so they are subtracted and reported on their own.
awk '
    /^#define TG_IGNORED_UPDATES\(X\)/ { on = 1 }
    on { print }
    on && $0 !~ /\\$/ { exit }
' "$ROOT/src/Core/TGUpdateType.h" \
    | grep -oE '"update[a-zA-Z0-9]+"' | tr -d '"' | sort -u > "$TMP/upd_ignored"
comm -23 "$TMP/upd_used" "$TMP/upd_ignored" > "$TMP/upd_read"
comm -23 "$TMP/upd_all" "$TMP/upd_used" > "$TMP/upd_gap"

# updatePoll and updatePollAnswer are in here for the same reason as the
# updateNew*Query family: td_api marks both "for bots only", so a user
# account never receives them. A poll a user can see changes through
# updateMessageContent.
#
# Areas this client is not going to have: they need a browser engine, a
# payment or wallet stack, a bot session, or a server feature that did not
# exist when this OS did. Kept as one pattern so the relevant gap is a number
# that can be watched, not a feeling. docs/feature_backlog.md explains each,
# and scripts/tdlib_tiers.py --tier3 prints the reason for every remaining
# group. Speech recognition is not in this list: TDLib's recognizeSpeech asks
# Telegram's own recognizer, so a user client can carry it.
# updates join the functions here deliberately, not with their panel:
# updateActiveEmojiReactions is the reaction-picker's list and there is no
# picker to read it, updateMessageSendAcknowledged has no state between
# pending and sent to draw, and updatePendingMessage streams a bot's
# half-written reply - no bot surface.
# updateFileGeneration* used to be here because the app never asked TDLib to
# generate a file; File Tools does now, so both updates are handled and no
# longer skipped.
# The inline and bot-side callers join the same way: editInlineMessage*,
# editMessageReplyMarkup, getPreparedInlineMessage and savePreparedInline-
# Message name a bot as the author, getCallbackQueryMessage rides a bot's
# callback, and sendTextMessageDraft/stopPendingMessage drive the streaming
# draft - none of which a user account may send. importMessages and its two
# helpers need a document picker this OS barely has, and
# setChatDirectMessagesGroup pairs with directMessagesChatTopic, already
# skipped as the channel dialog it belongs to.
#
# The three History-by-topic calls are the older spellings of getChatHistory
# with a message_thread_id or saved-messages topic id, which is what
# historyForChat:thread: already sends; getPersonalChatHistory is for bots
# only. They are named here rather than left to the Story pattern, which
# used to swallow every name containing "History" by accident.
#
# Updates whose screen is still missing are not out of scope: they stay in
# TG_HANDLED_UPDATES and are listed in TG_IGNORED_UPDATES, which is what
# --ignored reads and what keeps the number honest. Only an update whose
# feature this client will not draw belongs in the skip pattern.
SKIP='[Tt]on[CW]|TonConnect|updateActiveEmojiReactions|updateMessageSendAcknowledged|updatePendingMessage|TonCenter|TonTransaction|tonWallet|[Ww]allet|Stor(y|ies)|[Bb]usiness|[Bb]ot|WebApp|[Ww]ebApp|webBrowser|BrowserSettings|[Pp]assport|[Pp]remium|[Bb]oost|[Gg]iveaway|[Aa]ffiliate|[Ss]tar[A-Z]|[Ss]tars|[Pp]aidMedia|[Pp]aidMessage|[Gg]ift|[Cc]hecklist|[Cc]ommunity|[Cc]ommunities|[Gg]roupCall|[Vv]ideoChat|[Ll]iveStory|LiveStream|[Ss]creenSharing|Rtmp|[Aa]i$|WithAi|[Oo]nRamp|[Pp]ayment|[Ii]nvoice|[Gg]ame[A-Z]|[Gg]ameHigh|InlineGame|[Ss]ponsored|[Aa]dvertisement|[Aa]dAccount|[Ll]og[A-Z]|[Jj]son|[Dd]ice|[Aa]larm|[Cc]ollectible|[Ee]phemeral|[Pp]asskey|[Oo]auth|[Ss]uggestedAction|[Ff]actCheck|[Aa]ntiSpam|[Ss]upportInfo|[Ss]upportName|[Tt]imeZone|[Cc]urrentWeather|CurrencyExchange|[Nn]ft|^test[A-Z]|^testNetwork|answerCallbackQuery|answerInlineQuery|answerPreCheckoutQuery|answerShippingQuery|answerCustomQuery|answerGuestQuery|[Rr]evenue|[Ww]ithdrawal|[Gg]ram[A-Z]|[Ss]uggestedPost|[Ss]ummarize|[Rr]ichMessage|[Ss]peech|listenToAudio|[Qq]uickReply|[Ww]ebProxyCarrier|StoreTransaction|PurchaseFromStore|[Mm]enuButton|[Cc]ommands$|^deleteCommands|^setCommands|^getCommands|^updateNew(Callback|Chosen|Custom|Guest|Inline|PreCheckout|Shipping)|[Pp]aidReaction|^updatePoll$|^updatePollAnswer$'

case "${1:-}" in
    --list)     cat "$TMP/gap"; exit 0 ;;
    --used)     cat "$TMP/used"; exit 0 ;;
    --relevant) grep -vE "$SKIP" "$TMP/gap"; exit 0 ;;
    --skipped)  grep -E  "$SKIP" "$TMP/gap"; exit 0 ;;
    --wired)    python3 "$ROOT/scripts/tdlib_wired.py" --wired; exit 0 ;;
    --bare)     python3 "$ROOT/scripts/tdlib_wired.py" --bare; exit 0 ;;
    --updates)  grep -vE "$SKIP" "$TMP/upd_gap"; exit 0 ;;
    --ignored)  cat "$TMP/upd_ignored"; exit 0 ;;
esac

total=$(wc -l < "$TMP/all"  | tr -d ' ')
used=$(wc -l < "$TMP/used" | tr -d ' ')
wired_bare=$(python3 "$ROOT/scripts/tdlib_wired.py" --counts)
wired=${wired_bare% *}
bare=${wired_bare#* }
printf 'td_api functions:  %s\n' "$total"
printf 'called by the app: %s (%s%%)\n' "$used" "$((used * 100 / total))"
printf '  reachable:       %s   (a screen calls the method)\n' "$wired"
printf '  bare:            %s   (name added, nothing calls it)\n' "$bare"
printf 'never called:      %s\n' "$((total - used))"
relevant=$(grep -vcE "$SKIP" "$TMP/gap")
printf '  of which wanted: %s   (see docs/feature_backlog.md)\n' "$relevant"
printf '  out of scope:    %s\n\n' "$((total - used - relevant))"

upd_total=$(wc -l < "$TMP/upd_all" | tr -d ' ')
upd_used=$(wc -l < "$TMP/upd_used" | tr -d ' ')
upd_read=$(wc -l < "$TMP/upd_read" | tr -d ' ')
upd_ignored=$(wc -l < "$TMP/upd_ignored" | tr -d ' ')
upd_rel=$(grep -vcE "$SKIP" "$TMP/upd_gap")
printf 'td_api updates:    %s\n' "$upd_total"
printf 'let through:       %s (%s%%)\n' "$upd_used" "$((upd_used * 100 / upd_total))"
printf '  acted on:        %s   (a branch changes state or tells a screen)\n' "$upd_read"
printf '  ignored markers: %s   (let through, no screen yet - see --ignored)\n' "$upd_ignored"
printf 'dropped:           %s\n' "$((upd_total - upd_used))"
printf '  of which wanted: %s\n' "$upd_rel"
printf '  out of scope:    %s\n\n' "$((upd_total - upd_used - upd_rel))"

# Areas, in the order docs/feature_backlog.md ranks them.
printf '%-22s %s\n' "area" "never called"
for area in Message Chat User Story Business Bot Sticker Call Payment Star \
            Gift Poll Checklist Forum Topic Folder Reaction Notification \
            Privacy Session Passport Premium Boost Giveaway Album Live \
            QuickReply SavedMessages Proxy Language Theme File Download; do
    n=$(grep -ci "$area" "$TMP/gap")
    [ "$n" -gt 0 ] && printf '%-22s %s\n' "$area" "$n"
done
exit 0
