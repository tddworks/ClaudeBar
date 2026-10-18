#!/bin/sh
# Example metrics probe — uses config values from Settings
# $CLAUDEBAR_API_KEY and $CLAUDEBAR_MONTHLY_BUDGET are injected automatically
#
# Replace this with real API calls:
#   USAGE=$(curl -s -H "Authorization: Bearer $CLAUDEBAR_API_KEY" "$CLAUDEBAR_BASE_URL/billing")
#   BUDGET=${CLAUDEBAR_MONTHLY_BUDGET:-100}

YESTERDAY_LABEL=$(date -v-1d +"%b %d")

cat <<EOF
{
    "metrics": [
        {
            "label": "Cost Usage",
            "value": "\$10.26",
            "unit": "Spent",
            "icon": "dollarsign.circle.fill",
            "color": "#FFEB3B",
            "progress": 0.82,
            "delta": {
                "vs": "$YESTERDAY_LABEL",
                "value": "-\$701.58",
                "percent": 98.6
            }
        },
        {
            "label": "Token Usage",
            "value": "8.3M",
            "unit": "Tokens",
            "icon": "number.circle.fill",
            "color": "#4CAF50",
            "progress": 0.65,
            "delta": {
                "vs": "$YESTERDAY_LABEL",
                "value": "-393.0K",
                "percent": 97.0
            }
        },
        {
            "label": "Working Time",
            "value": "1h 4m",
            "unit": "Duration",
            "icon": "clock.fill",
            "color": "#CE93D8",
            "progress": 0.35,
            "delta": {
                "vs": "$YESTERDAY_LABEL",
                "value": "-10h 50m",
                "percent": 91.0
            }
        }
    ]
}
EOF
