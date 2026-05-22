#!/bin/bash
# Debug script to fetch raw Antigravity API response
# Usage: ./scripts/antigravity-debug.sh

set -e

echo "=== Antigravity Debug Script ==="
echo

# Step 1: Find Antigravity process
echo "Step 1: Finding Antigravity process..."
PROCESS_LINE=$(pgrep -lf "language_server" | grep -E "(antigravity|--app_data_dir.*antigravity)" | head -1)

if [ -z "$PROCESS_LINE" ]; then
    echo "ERROR: Antigravity process not found. Is the app running?"
    exit 1
fi

PID=$(echo "$PROCESS_LINE" | awk '{print $1}')
echo "Found PID: $PID"

# Step 2: Extract CSRF token
echo
echo "Step 2: Extracting CSRF token..."
CSRF_TOKEN=$(echo "$PROCESS_LINE" | grep -oE '\-\-csrf_token[= ]+[^ ]+' | sed -E 's/--csrf_token[= ]+//')

if [ -z "$CSRF_TOKEN" ]; then
    echo "ERROR: Could not extract CSRF token from process args"
    echo "Process line: $PROCESS_LINE"
    exit 1
fi
echo "CSRF token found: ${CSRF_TOKEN:0:20}..."

# Step 3: Extract extension port (optional)
EXT_PORT=$(echo "$PROCESS_LINE" | grep -oE '\-\-extension_server_port[= ]+[0-9]+' | grep -oE '[0-9]+$')
if [ -n "$EXT_PORT" ]; then
    echo "Extension port: $EXT_PORT"
fi

# Step 4: Find listening ports
echo
echo "Step 3: Finding listening ports..."
LSOF_PATH="/usr/sbin/lsof"
[ ! -x "$LSOF_PATH" ] && LSOF_PATH="/usr/bin/lsof"

PORTS=$($LSOF_PATH -nP -iTCP -sTCP:LISTEN -a -p "$PID" 2>/dev/null | grep -oE ':[0-9]+ \(LISTEN\)' | grep -oE '[0-9]+' | sort -u)

if [ -z "$PORTS" ]; then
    echo "ERROR: No listening ports found for PID $PID"
    exit 1
fi

echo "Listening ports: $PORTS"

# Step 5: Try API endpoints
echo
echo "Step 4: Fetching API response..."

REQUEST_BODY='{"metadata":{"ideName":"antigravity","extensionName":"antigravity","ideVersion":"unknown","locale":"en"}}'

ENDPOINTS=(
    "/exa.language_server_pb.LanguageServerService/GetUserStatus"
    "/exa.language_server_pb.LanguageServerService/GetCommandModelConfigs"
)

fetch_api() {
    local scheme=$1
    local port=$2
    local path=$3

    curl -sS --max-time 5 \
        --insecure \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Codeium-Csrf-Token: $CSRF_TOKEN" \
        -H "Connect-Protocol-Version: 1" \
        -d "$REQUEST_BODY" \
        "${scheme}://127.0.0.1:${port}${path}" 2>/dev/null
}

# Try HTTPS on each port
for PORT in $PORTS; do
    for ENDPOINT in "${ENDPOINTS[@]}"; do
        echo "Trying https://127.0.0.1:$PORT$ENDPOINT ..."
        RESPONSE=$(fetch_api "https" "$PORT" "$ENDPOINT")
        if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "null" ]; then
            echo
            echo "=== SUCCESS on port $PORT ==="
            echo "Endpoint: $ENDPOINT"
            echo
            echo "=== Raw Response ==="
            echo "$RESPONSE"
            echo
            echo "=== Pretty Printed ==="
            echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
            exit 0
        fi
    done
done

# Fallback to HTTP on extension port
if [ -n "$EXT_PORT" ]; then
    for ENDPOINT in "${ENDPOINTS[@]}"; do
        echo "Trying http://127.0.0.1:$EXT_PORT$ENDPOINT (HTTP fallback)..."
        RESPONSE=$(fetch_api "http" "$EXT_PORT" "$ENDPOINT")
        if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "null" ]; then
            echo
            echo "=== SUCCESS on HTTP port $EXT_PORT ==="
            echo "Endpoint: $ENDPOINT"
            echo
            echo "=== Raw Response ==="
            echo "$RESPONSE"
            echo
            echo "=== Pretty Printed ==="
            echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
            exit 0
        fi
    done
fi

echo
echo "ERROR: Could not fetch API response from any port/endpoint"
exit 1