#!/bin/bash
# Update appcast.xml with a new release entry
# Usage: ./scripts/update-appcast.sh <version> <build_number> <download_url> <signature> <file_size>

set -e

VERSION="$1"
BUILD_NUMBER="$2"
DOWNLOAD_URL="$3"
ED_SIGNATURE="$4"
FILE_SIZE="$5"
PUB_DATE=$(date -R)

mkdir -p docs

# Try to fetch existing appcast from GitHub Pages
APPCAST_URL="https://tddworks.github.io/ClaudeBar/appcast.xml"
EXISTING_ITEMS=""
if curl -sL --fail "$APPCAST_URL" -o /tmp/appcast_existing.xml 2>/dev/null; then
    echo "Fetched existing appcast.xml"

    # Get the highest existing build number
    HIGHEST_BUILD=$(grep -o '<sparkle:version>[0-9]*</sparkle:version>' /tmp/appcast_existing.xml | \
                    sed 's/<[^>]*>//g' | sort -rn | head -1)

    if [ -n "$HIGHEST_BUILD" ] && [ "$BUILD_NUMBER" -le "$HIGHEST_BUILD" ]; then
        echo "Warning: Build number $BUILD_NUMBER is not higher than existing $HIGHEST_BUILD"
        BUILD_NUMBER=$((HIGHEST_BUILD + 1))
        echo "Using build number $BUILD_NUMBER instead"
    fi

    # Remove any existing items with the same version (to avoid duplicates)
    EXISTING_ITEMS=$(awk -v ver="$VERSION" '
        /<item>/,/<\/item>/ {
            if (/<item>/) { item=""; in_item=1 }
            item = item $0 "\n"
            if (/<\/item>/) {
                in_item=0
                if (item !~ "<title>" ver "</title>" && item !~ "<sparkle:shortVersionString>" ver "</sparkle:shortVersionString>") {
                    printf "%s", item
                }
            }
            next
        }
        { if (!in_item) next }
    ' /tmp/appcast_existing.xml)

    rm -f /tmp/appcast_existing.xml
else
    echo "No existing appcast found, creating new one"
fi

# Create new appcast
cat > docs/appcast.xml << EOF
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>ClaudeBar</title>
        <item>
            <title>${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <description><![CDATA[<h2>ClaudeBar ${VERSION}</h2>
<p>Bug fixes and improvements.</p>
<p><a href="https://github.com/tddworks/ClaudeBar/releases/tag/v${VERSION}">View release notes</a></p>
]]></description>
            <enclosure url="${DOWNLOAD_URL}" length="${FILE_SIZE}" type="application/octet-stream" sparkle:edSignature="${ED_SIGNATURE}"/>
        </item>
${EXISTING_ITEMS}
    </channel>
</rss>
EOF

echo "Generated appcast.xml:"
cat docs/appcast.xml
