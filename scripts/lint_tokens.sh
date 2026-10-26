#!/bin/sh
# lint_tokens.sh - fail the build when a screen names its own size or colour.
#
# Colour has always come from TGTheme+Palette; type and metrics come from
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
        --include='*.m' --include='*.h' | grep -v '^src/Core/TGStyle')
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
        --include='*.m' --include='*.h')
if [ -n "$hits" ]; then
    report "A literal passed to TGFont...AtSize, which is only for computed sizes:" \
            "pick the role from the scale in src/Core/TGStyle.h instead"
    echo "$hits"
fi

# ── 3. a colour mixed by hand outside the palette ────────────────────────────
# Only literal components are caught: TGIcons+Avatars builds a colour out of a
# packed integer, which is a generator and not a decision.
hits=$(grep -rnE '\[UIColor colorWith(Red|Hue):[0-9]' src \
        --include='*.m' --include='*.h' | grep -v '^src/Core/')
if [ -n "$hits" ]; then
    report "A colour is mixed in a screen instead of coming from the palette:" \
            "add a name to TGTheme+Palette.m and ask the theme for it"
    echo "$hits"
fi

# ── 4. a system alert where the app has its own sheet ────────────────────────
# UIAlertView and UIActionSheet draw themselves in the system's colours, which
# is a white box on a dark theme, and they answer through a tag-keyed delegate.
# Everything went over to TGAlertSheet; nothing comes back.
hits=$(grep -rn 'UIAlertView\|UIActionSheet' src --include='*.m' --include='*.h' \
        | grep -v 'TGAlertSheet' | grep -vE ':[[:space:]]*(//|\*|/\*)')
if [ -n "$hits" ]; then
    report "A system alert or action sheet, which ignores the theme:" \
            "use TGAlertSheet - showMessage / showConfirm / showChoices / showInput"
    echo "$hits"
fi

if [ "$status" -eq 0 ]; then
    echo "  design tokens: clean"
fi
exit $status
