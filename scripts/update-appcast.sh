#!/bin/bash
# Update appcast.xml with a new release entry
# Usage: ./scripts/update-appcast.sh <version> <build_number> <download_url> <signature> <file_size> [release_notes] [channel]
# channel: Optional. Set to "beta" for pre-release versions to enable beta channel filtering.

set -e

VERSION="$1"
BUILD_NUMBER="$2"
DOWNLOAD_URL="$3"
ED_SIGNATURE="$4"
FILE_SIZE="$5"
RELEASE_NOTES="${6:-Bug fixes and improvements.}"
CHANNEL="${7:-}"  # Optional: "beta" for pre-release versions
PUB_DATE=$(date -R)

mkdir -p docs

# Convert markdown to clean HTML for Sparkle
# Process line by line for proper list handling
convert_to_html() {
    local in_list=false
    local result=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        if [[ -z "$line" ]]; then
            if $in_list; then
                result+="</ul>"
                in_list=false
            fi
            continue
        fi

        # Handle ### Heading
        if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
            if $in_list; then
                result+="</ul>"
                in_list=false
            fi
            result+="<h3>${BASH_REMATCH[1]}</h3>"
        # Handle - list item
        elif [[ "$line" =~ ^-[[:space:]]+(.*) ]]; then
            if ! $in_list; then
                result+="<ul>"
                in_list=true
            fi
            # Convert backticks to <code>
            local item="${BASH_REMATCH[1]}"
            item=$(echo "$item" | sed 's/`\([^`]*\)`/<code>\1<\/code>/g')
            result+="<li>$item</li>"
        else
            if $in_list; then
                result+="</ul>"
                in_list=false
            fi
            result+="<p>$line</p>"
        fi
    done

    if $in_list; then
        result+="</ul>"
    fi

    echo "$result"
}

HTML_NOTES=$(echo "$RELEASE_NOTES" | convert_to_html)

# Human-readable date for display
DISPLAY_DATE=$(date "+%B %d, %Y")

# Build channel tag if specified
CHANNEL_TAG=""
if [[ -n "$CHANNEL" ]]; then
    CHANNEL_TAG="            <sparkle:channel>${CHANNEL}</sparkle:channel>"
    echo "Adding channel: $CHANNEL"
fi

# Create fresh appcast with only the new version
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
${CHANNEL_TAG}
            <description><![CDATA[<h2>ClaudeBar ${VERSION}</h2>
<p><em>Released ${DISPLAY_DATE}</em></p>
${HTML_NOTES}
<p><a href="https://github.com/tddworks/ClaudeBar/releases/tag/v${VERSION}">View full release notes</a></p>
]]></description>
            <enclosure url="${DOWNLOAD_URL}" length="${FILE_SIZE}" type="application/octet-stream" sparkle:edSignature="${ED_SIGNATURE}"/>
        </item>
    </channel>
</rss>
EOF

echo "Generated appcast.xml:"
cat docs/appcast.xml
