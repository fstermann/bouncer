#!/bin/sh
# Rebuilds the icon asset catalog from the master drawings in Assets/Icons. Needs SwiftDraw
# (brew install swiftdraw). Run after adding or changing an icon, then commit both.
#
# The 3-unit inset maps the 24-unit grid so icons match SF Symbols in size; the stroke scales
# give the ultralight and black weights that the system interpolates the rest from.
set -eu

catalog=Modules/Sources/BouncerFoundation/Resources/Icons.xcassets
rm -rf "$catalog"
mkdir -p "$catalog"
printf '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' > "$catalog/Contents.json"
for svg in Assets/Icons/*.svg; do
    name=$(basename "$svg" .svg)
    set="$catalog/$name.symbolset"
    mkdir -p "$set"
    swiftdraw "$svg" --format sfsymbol --insets 3,3,3,3 \
        --ultralight-stroke-width 0.5 --black-stroke-width 1.9 --output "$set/$name.svg" --quiet
    printf '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  },\n  "symbols" : [\n    {\n      "filename" : "%s.svg",\n      "idiom" : "universal"\n    }\n  ]\n}\n' \
        "$name" > "$set/Contents.json"
done
echo "$(ls "$catalog" | grep -c symbolset) icons in $catalog"
