#!/bin/sh
# lint_tokens.sh - fail the build when a screen names its own size or colour.
#
# Colour has always come from TGTheme+Colours; type and metrics come from
# TGStyle. The point of both is that one value is set in one place, and the
# only way that survives is if a new literal cannot get merged. So this runs
# as part of the test suite, not as advice.
#
# Run on its own:   sh scripts/lint_tokens.sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
status=0

report() {
    printf '\n  %s\n' "$1"
    printf '  %s\n\n' "$2"
    status=1
}

# ── 1. a point size spelled out in a screen ──────────────────────────────────
# Every role is a function in TGStyle.h. TGStyle.m is where the numbers live.
hits=$(grep -rn 'UIFont [a-zA-Z]*[sS]ystemFontOfSize:[0-9]' src \
        --include='*.m' --include='*.mm' --include='*.h' | grep -v '^src/Core/TGStyle')
if [ -n "$hits" ]; then
    report "A point size is written out instead of asking TGStyle for a role:" \
            "use TGFontBody(), TGFontRow(), TGFontCaption()... see src/Core/TGStyle.h"
    echo "$hits"
fi

# ── 2. a literal handed to the computed-size escape hatch ────────────────────
# TGFontAtSize is for a size the screen works out - a glyph fitted to its box,
# message text at the size the user chose. A literal there is rule 1 in
# disguise.
hits=$(grep -rnE 'TGFont(Bold|Italic|Medium)?AtSize\([0-9]' src \
        --include='*.m' --include='*.mm' --include='*.h')
if [ -n "$hits" ]; then
    report "A literal passed to TGFont...AtSize, which is only for computed sizes:" \
            "pick the role from the scale in src/Core/TGStyle.h instead"
    echo "$hits"
fi

# ── 3. a colour mixed by hand outside the palette ────────────────────────────
# All colours must originate from TGTheme+Colours. Any first argument counts:
# a palette hidden behind `((c >> 16) & 0xFF) / 255.0f` is still a palette. The
# one exception is TGBackgroundColour, which draws what the server sent.
hits=$(grep -rnE '\[UIColor colorWith(Red|Hue|White):' src \
        --include='*.m' --include='*.mm' --include='*.h' | grep -v '^src/Core/' \
        | grep -v '^src/Controllers/TGBackgroundsViewController.m')
if [ -n "$hits" ]; then
    report "A colour is mixed in a screen instead of coming from the palette:" \
            "add a name to TGTheme+Colours.m and ask the theme for it"
    echo "$hits"
fi

# ── 4. a system alert where the app has its own sheet ────────────────────────
# UIAlertView and UIActionSheet draw themselves in the system's colours, which
# is a white box on a dark theme, and they answer through a tag-keyed delegate.
# Everything went over to TGAlertSheet; nothing comes back.
hits=$(grep -rn 'UIAlertView\|UIActionSheet' src --include='*.m' --include='*.mm' --include='*.h' \
        | grep -v 'TGAlertSheet' | grep -vE ':[[:space:]]*(//|\*|/\*)')
if [ -n "$hits" ]; then
    report "A system alert or action sheet, which ignores the theme:" \
            "use TGAlertSheet - showMessage / showConfirm / showChoices / showInput"
    echo "$hits"
fi

# ── 5. a list row that picked its own height ────────────────────────────────
# The same row - somebody's picture, their name, a line under it - was 52, 56
# and 60 across five screens. TGMetricPersonRow is what it is.
hits=$(grep -rn 'tableView\.rowHeight = [0-9]' src --include='*.m' --include='*.mm')
if [ -n "$hits" ]; then
    report "A list row's height is written out instead of a metric:" \
            "TGMetricPersonRow for a row showing somebody, TGMetricRow for a settings row"
    echo "$hits"
fi

# ── 6. a section caption styled by hand ─────────────────────────────────────
# Seven screens did this themselves and five left the system's, which over a
# dark list is grey on grey.
hits=$(grep -rn 'header\.textLabel\.textColor' src --include='*.m' --include='*.mm' | grep -v 'src/Core/TGTheme')
if [ -n "$hits" ]; then
    report "A section caption is styled in a screen:" \
            "[[TGTheme shared] styleSectionHeader:view] in willDisplayHeaderView:"
    echo "$hits"
fi

# ── 7. a character standing in for an icon ──────────────────────────────────
# The dismiss cross was U+00D7 in two places and U+2715 in a third, at three
# different weights, and the record lock's arrow was a bold "▲".
hits=$(grep -rnE 'setTitle:@"(\\[uU]|[^"A-Za-z0-9 .,:%+?!-])' src --include='*.m' --include='*.mm')
if [ -n "$hits" ]; then
    report "A character is standing in for an icon:" \
            "draw it in TGIcons+Menu and ask for it with glyphNamed:colour:side:"
    echo "$hits"
fi

# ── 8. an icon at its own stroke weight ─────────────────────────────────────
# The set was drawn at ten widths between 1.3 and 5.0, and send sat beside
# attach in one bar at 2.4 and 2.0. Two named weights now: the family's, and
# a finer one for marks under about sixteen points.
hits=$(grep -rnE 'CGContextSetLineWidth\(ctx, [0-9]' src/Views/TGIcons.m \
        src/Views/TGIcons+Menu.m src/Views/TGEmojiPanel.m)
if [ -n "$hits" ]; then
    report "An icon sets its own stroke weight:" \
            "TGIconStroke, or TGIconStrokeFine for a mark under ~16 points"
    echo "$hits"
fi

# ── 9. a corner radius that is neither the scale nor half a side ─────────────
# Two shapes exist and no third. A rounded rectangle takes a value from the
# corner scale. A circle or a capsule is half of its own side, written as
# TGHalf(side) - and that is the whole of it, because demanding a name per
# shape is what produced eighteen one-use corner tokens in the first place:
# TGMetricCornerListAvatar, ...CallAvatar, ...SendButton, each the half of a
# side that already had a token, each free to drift from it in silence.
#
# A raw literal, or a hand-written "/ 2", is still neither.
hits=$(grep -rnE '\.cornerRadius\s*=\s*([^;]+);' src --include='*.m' --include='*.mm' \
        | grep -vE '\.cornerRadius\s*=\s*TGMetricCornerNone;' \
        | grep -vE '\.cornerRadius\s*=\s*.*(\[|TGMetricCorner|TGHalf\(|kCorner|radius;)' \
        | grep -v '^src/Core/TGStyle')
if [ -n "$hits" ]; then
    report "A corner radius is neither a scale value nor half its own side:" \
            "TGMetricCorner* for a rounded rectangle, TGHalf(side) for a circle or capsule"
    echo "$hits"
fi

# ── 10. a font name and size requested directly in a screen ─────────────────
# All fonts come through TGStyle roles. A custom face belongs in TGStyle.m.
hits=$(grep -rnE '\[UIFont fontWithName:.* size:[0-9]' src --include='*.m' --include='*.mm' \
        | grep -v '^src/Core/TGStyle.m')
if [ -n "$hits" ]; then
    report "A font is created with fontWithName: and a literal size:" \
            "add a role function in src/Core/TGStyle.h and TGStyle.m"
    echo "$hits"
fi

# ── 11. an animation duration written out as a literal ──────────────────────
# Transitions must use TGAnimationDuration* tokens (Fast/Normal/Medium/Slow).
hits=$(grep -rnE 'animateWithDuration:\s*[0-9]' src --include='*.m' --include='*.mm')
if [ -n "$hits" ]; then
    report "An animation duration is written out as a literal instead of a motion token:" \
            "use TGAnimationDurationFast, Normal, Medium, or Slow from src/Core/TGStyle.h"
    echo "$hits"
fi

# ── 12. a manual division by 2 for geometry / centering ──────────────────────
# Manual `/ 2` or `/ 2.0f` introduces inconsistent rounding and magic calculations.
# Use TGCenteredOrigin(container, item), TGHalf(dimension), or a semantic token.
hits=$(grep -rnE '(\([a-zA-Z0-9_.]+\s*-\s*[a-zA-Z0-9_.]+\)\s*/\s*2(\.0f)?|\.width\s*/\s*2(\.0f)?|\.height\s*/\s*2(\.0f)?)\b' \
        src/Controllers src/Views --include='*.m' --include='*.mm' \
        | grep -v '^src/Core/' | grep -v '^src/Views/TGIcons' | grep -v '^src/Views/TGLottieView')
if [ -n "$hits" ]; then
    report "A manual division by 2 is used for layout/centering:" \
            "use TGCenteredOrigin(container, item) or TGHalf(dimension) from src/Core/TGStyle.h"
    echo "$hits"
fi

# ── 13. a table row height returned as a literal number ──────────────────────
# Row heights must use TGMetric* tokens (e.g. TGMetricRow, TGMetricPersonRow, TGMetricSettingsProfileRow).
hits=$(grep -rnE 'heightForRowAtIndexPath' src/Controllers -A 20 --include='*.m' --include='*.mm' \
        | grep -E 'return\s+[0-9]+(\.[0-9]+)?f?;')
if [ -n "$hits" ]; then
    report "A table row height is returned as a literal number instead of a metric token:" \
            "use TGMetric* tokens from src/Core/TGStyle.h"
    echo "$hits"
fi

# ── 14. a colour alpha mixed manually outside palette ────────────────────────
# Ad-hoc transparency creates uncalibrated tints. Put semantic colors in TGTheme+Colours.m.
hits=$(grep -rnE 'colorWithAlphaComponent:\s*[0-9]' src --include='*.m' --include='*.mm' --include='*.h' \
        | grep -v '^src/Core/')
if [ -n "$hits" ]; then
    report "colorWithAlphaComponent: with literal alpha is used outside Core palette:" \
            "define a semantic color in TGTheme+Colours.m instead"
    echo "$hits"
fi

# ── 15. a size written out inside a frame ───────────────────────────────────
# The one that matters most, and the one the other fourteen were standing in
# for. A screen that writes CGRectMake(10, 16 + side + 8, width - 20, 26) has
# named four sizes in passing, and the next screen wanting the same stack will
# name four more, slightly different ones. That is how the app came to space
# things at thirteen different values and give a one-line label ten different
# heights. So no literal goes inside CGRectMake, CGSizeMake, CGPointMake,
# UIEdgeInsetsMake or CGRectInset.
#
# Allowed there: 0, 1 and 0.5 - an origin, a hairline, a midpoint, none of
# which can mean anything else - and any name, whether from a scale in TGStyle
# or from the file's own constants, which is where a dimension that belongs to
# one screen goes.
#
# Drawing is not laying out and is left alone: an icon draws inside the box it
# is handed, and a path's control points are the shape itself.
geom() {
    for f in $(find src -name '*.m' \
            | grep -vE 'src/Views/TGIcons|src/Views/TGLottieView'); do
        # One statement per line first: a frame is often spread over three of
        # them, and the literal is rarely on the one naming CGRectMake. Then
        # only what is inside the brackets is read, so a colour mixed in the
        # same statement is rule 3's business and not this one's.
        awk -v file="$f" '
            function args(s,    out, i, c, d, n) {
                out = ""
                while (match(s, /CG(Rect|Size|Point)Make\(|UIEdgeInsetsMake\(|CGRectInset\(/)) {
                    i = RSTART + RLENGTH
                    s = substr(s, i)
                    d = 1
                    for (n = 1; n <= length(s) && d > 0; n++) {
                        c = substr(s, n, 1)
                        if (c == "(") d++
                        else if (c == ")") d--
                        if (d > 0) out = out c
                    }
                    s = substr(s, n)
                }
                return out
            }
            { sub(/\/\/.*/, "") }
            buf == "" { start = FNR }
            { buf = buf " " $0 }
            /;[[:space:]]*$/ {
                if (buf !~ /CGContext|CGPath|addArc|UIBezierPath|drawInRect|drawAtPoint|Ellipse/) {
                    code = args(buf)
                    gsub(/"[^"]*"/, "", code)
                    gsub(/[A-Za-z_][A-Za-z0-9_.]*/, "_", code)
                    gsub(/(^|[^0-9.])(0|1)(\.(0|00|5))?f?([^0-9.]|$)/, " ", code)
                    gsub(/(^|[^0-9.])(0|1)(\.(0|00|5))?f?([^0-9.]|$)/, " ", code)
                    if (code ~ /[0-9]/) print file ":" start
                }
                buf = ""
            }
        ' "$f"
    done
}
hits=$(geom)
if [ -n "$hits" ]; then
    report "A size is written out inside a frame instead of being named:" \
            "take it from a scale in src/Core/TGStyle.h, or name it in this file"
    echo "$hits"
fi


# ── 8. iOS 8 selectors on an iOS 6 app ──────────────────────────────────────
# containsString: looks harmless and compiles against the SDK, but the runtime
# on the iPod/4S has no such selector and the app dies with an uncaught
# exception the first time the path runs.
hits=$(grep -rnE '\b(localizedCaseInsensitive)?[Cc]ontainsString:' src \
        --include='*.m' --include='*.mm' --include='*.h')
if [ -n "$hits" ]; then
    report "A selector newer than this app's oldest supported iOS:" \
            "use [string rangeOfString:...].location != NSNotFound"
    echo "$hits"
fi

# ── 16. a shadow spelled out ────────────────────────────────────────────────
# Rule 15 lets 0 and 1 through, so CGSizeMake(0, 1) passed everywhere as a
# private copy of the etched offset.
hits=$(grep -rnE 'shadowOffset\s*=\s*CGSizeMake|shadow(Opacity|Radius)\s*=\s*[0-9]' \
        src/Controllers src/Views --include='*.m' --include='*.mm')
if [ -n "$hits" ]; then
    report "A shadow is written out instead of named:" \
            "TGMetricShadowOffset*, TGMetricShadow*Radius, TGMetricShadow*Opacity"
    echo "$hits"
fi

# ── 17. a translucency spelled out ──────────────────────────────────────────
hits=$(grep -rnE '\.alpha\s*=[^;]*[^0-9A-Za-z_]0?\.[0-9]*[1-9]|k[A-Za-z]*Alpha\s*=\s*0?\.[0-9]' \
        src/Controllers src/Views --include='*.m' --include='*.mm')
if [ -n "$hits" ]; then
    report "An alpha is written out instead of named:" \
            "TGAlphaDimmed, TGAlphaHighlight... see TGStyle+Decorations.h"
    echo "$hits"
fi

# ── 18. a step of the spacing scale under a private name ────────────────────
hits=$(grep -rnE 'static const CGFloat k[A-Za-z]*(Gap|Pad|Inset|Margin)\s*=\s*(2|4|8|10|16|20)(\.0)?f?;' \
        src/Controllers src/Views --include='*.m' --include='*.mm')
if [ -n "$hits" ]; then
    report "A step of the spacing scale has been copied into a constant:" \
            "TGMetricPadTiny, PadSmall, Pad, PadMedium, PadLarge or PadWide"
    echo "$hits"
fi

# ── 19. a private copy of a size the app already has a name for ─────────────
# Each of these drifted or could: the video note's record dot was 10 beside the
# voice note's 9, and the theme preview set its text at 9 beside the bubble's 10.
hits=$(grep -rnE 'static const CGFloat k(DotSide|PreviewTextLeft|TailWidth|TailHeight|ChoiceGlyph|OnceSide|ActionBarCloseSide|MiniCloseSide|BarEditHeight|BarControlSide)\s*=\s*[0-9]' \
        src/Controllers src/Views --include='*.m' --include='*.mm')
if [ -n "$hits" ]; then
    report "A shared size has been copied as a number:" \
            "point the constant at its TGMetric token"
    echo "$hits"
fi

# ── 20. white named directly ────────────────────────────────────────────────
# White on a filled control is onAccentColour and white over a picture is
# onMediaColour. What may name it: the QR plate a scanner needs, the screen used
# as a lamp, and the icon and avatar drawing that bakes it into a bitmap.
hits=$(grep -rnF '[UIColor whiteColor]' src/Controllers src/Views --include='*.m' --include='*.mm' \
        | grep -vE '^src/Controllers/TGLoginViewController\+Steps.m|^src/Controllers/TGVideoNoteViewController.m|^src/Views/TGIcons\+(Menu|Avatars).m')
if [ -n "$hits" ]; then
    report "White is named directly:" \
            "[[TGTheme shared] onAccentColour] on a filled control, onMediaColour over a picture"
    echo "$hits"
fi

# ── 21. a badge in its own type ─────────────────────────────────────────────
# The chat row's badge was 13 bold, the jump button's 12 and TGBadge's 11.
hits=$(grep -rnE '(_label|[bB]adge)\.font\s*=\s*TGFont' src/UI/TGBadge.m src/Views/TGChatCell.m \
        src/Controllers/TGChatViewController+Chrome.m | grep -v 'TGFontCaptionStrong()')
if [ -n "$hits" ]; then
    report "A badge has its own type:" "TGFontCaptionStrong()"
    echo "$hits"
fi

# ── 22. a screen that paints itself once ────────────────────────────────────
# A screen left in another tab's stack outlives a theme change and is painted
# in the old colours when the user comes back. It needs the notification, its
# own or a base class's. The exceptions either repaint in viewWillAppear or are
# full-screen and modal over dark media, where nothing can change the theme
# underneath them; the call screen comes back from its bar, and is the one left
# to do.
for f in src/Controllers/*ViewController.m; do
    b=$(basename "$f" .m)
    grep -q 'Colour\]' "$f" || continue
    grep -q 'TGThemeChangedNotification' "$f" && continue
    case "$b" in
        TGStickerPacksViewController|TGMessageAudienceViewController|TGStickerEditorViewController) continue ;;
        TGVideoNoteViewController|TGStoryViewerViewController|TGQRViewController|TGCallViewController) continue ;;
    esac
    sup=$(sed -n "s/^@interface $b *: *\([A-Za-z0-9_]*\).*/\1/p" "${f%.m}.h" "$f" 2>/dev/null | head -1)
    case "$sup" in
        TGListViewController|TGTier2ListViewController|TGBusinessBaseViewController) continue ;;
    esac
    report "A screen paints theme colours but never hears the theme change:" "$f"
done

# ── 23. a recording strip of its own ────────────────────────────────────────
# The round video once drew its own: 58 pt to the composer's 48, floating 14 pt
# off the bottom, a 54 pt send disc to the voice note's 34. TGRecordBar is the
# strip; a recording that wants one asks for it.
hits=$(grep -rln 'skeuomorphicInputBarImageWithHeight' src/Controllers src/Views \
        | grep -vE 'TGChatViewController\+Input.m|TGRecordBar.m')
if [ -n "$hits" ]; then
    report "A recording draws its own strip:" "use TGRecordBar"
    echo "$hits"
fi

# ── 24. mirroring a connection that mirrors itself ─────────────────────────
# automaticallyAdjustsVideoMirroring is on by default, and setting videoMirrored
# over it raises on iOS 6: the round video recorder died this way on the iPod
# touch 4 the moment the camera attached.
hits=$(grep -rnE '\.videoMirrored\s*=' src --include='*.m' --include='*.mm')
if [ -n "$hits" ]; then
    report "videoMirrored is set over the connection's own mirroring, which throws:" \
            "leave it to automaticallyAdjustsVideoMirroring"
    echo "$hits"
fi

# ── 25. a capture session started on a queue ────────────────────────────────
# iOS 6 finishes startRunning through the caller's run loop. On a dispatch queue
# it returns with isRunning NO and every file fails with SessionNotRunning.
hits=$(grep -rn -B8 'startRunning\]' src --include='*.m' --include='*.mm' | grep -E 'dispatch_(a)?sync\(.*global_queue|get_global_queue')
if [ -n "$hits" ]; then
    report "A capture session is started on a dispatch queue, which iOS 6 never finishes:" \
            "give it a thread with a run loop, or the main thread"
    echo "$hits"
fi

if [ "$status" -eq 0 ]; then
    echo "  design tokens: clean"
fi
exit $status
