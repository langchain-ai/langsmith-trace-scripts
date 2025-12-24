#!/bin/bash
set -euo pipefail

# Upload a scrubbed trace to LangSmith
# Usage: ./upload_trace.sh <trace_file> <project_name>

show_help() {
    cat << EOF
Upload a scrubbed trace to LangSmith

USAGE:
    $0 <trace_file> <project_name>

ARGUMENTS:
    trace_file    - JSON file with scrubbed trace
    project_name  - Project name to upload to

ENVIRONMENT:
    LANGSMITH_API_KEY  - Your LangSmith API key (required)

EXAMPLE:
    export LANGSMITH_API_KEY='lsv2_pt_...'
    $0 trace.scrubbed.json "customer-issue-1234"

EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

TRACE_FILE="${1:-}"
PROJECT_NAME="${2:-}"

if [ -z "$TRACE_FILE" ] || [ -z "$PROJECT_NAME" ]; then
    echo "Error: trace_file and project_name required"
    echo "Run '$0 --help' for usage"
    exit 1
fi

if [ ! -f "$TRACE_FILE" ]; then
    echo "Error: File not found: $TRACE_FILE"
    exit 1
fi

if [ -z "${LANGSMITH_API_KEY:-}" ]; then
    echo "Error: LANGSMITH_API_KEY not set"
    echo "Run: export LANGSMITH_API_KEY='your-api-key'"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq required. Install with: brew install jq"
    exit 1
fi

API_BASE="${LANGSMITH_ENDPOINT:-https://api.smith.langchain.com}"

echo "Uploading trace to LangSmith..."
echo "Project: $PROJECT_NAME"
echo "File: $TRACE_FILE"
echo ""

# Create or get existing project
TEMP_PROJ=$(mktemp)
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TEMP_PROJ" \
    -X POST \
    -H "x-api-key: $LANGSMITH_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$PROJECT_NAME\", \"description\": \"Uploaded trace\"}" \
    "$API_BASE/api/v1/sessions")

SESSION_RESP=$(cat "$TEMP_PROJ")
SESSION_ID=$(echo "$SESSION_RESP" | jq -r '.id // ""')

if [ "$HTTP_CODE" = "409" ]; then
    echo "Project '$PROJECT_NAME' already exists, using existing project..."
    # Fetch existing project by name
    SEARCH_RESP=$(curl -sf \
        -H "x-api-key: $LANGSMITH_API_KEY" \
        "$API_BASE/api/v1/sessions?name=$PROJECT_NAME")

    SESSION_ID=$(echo "$SEARCH_RESP" | jq -r '.[0].id // ""')

    if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ]; then
        echo "Error: Could not find existing project '$PROJECT_NAME'"
        rm -f "$TEMP_PROJ"
        exit 1
    fi
elif [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo "Created new project '$PROJECT_NAME'"
else
    echo "Error: Failed to create project (HTTP $HTTP_CODE)"
    ERROR_MSG=$(echo "$SESSION_RESP" | jq -r '.error // .detail // "Unknown error"')
    echo "$ERROR_MSG"
    rm -f "$TEMP_PROJ"
    exit 1
fi

rm -f "$TEMP_PROJ"

if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ]; then
    echo "Error: Failed to get project ID"
    exit 1
fi

echo "Project ID: $SESSION_ID"

# Get run count
TOTAL=$(jq 'length' "$TRACE_FILE")
echo "Uploading $TOTAL runs..."
echo ""

# Upload runs (sorted by dotted_order for parent-child ordering)
UPLOADED=0
FAILED=0
TEMP_RUNS=$(mktemp)
TEMP_MAPPING=$(mktemp)
trap "rm -f $TEMP_RUNS $TEMP_MAPPING" EXIT

# Build ID mapping (old_id -> new_id) to preserve parent-child relationships
jq -c 'sort_by(.dotted_order)[]' "$TRACE_FILE" > "$TEMP_RUNS"
echo "{}" > "$TEMP_MAPPING"

while read -r run; do
    OLD_ID=$(echo "$run" | jq -r '.id')
    NEW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    TEMP_MAP=$(jq --arg old "$OLD_ID" --arg new "$NEW_ID" '.[$old] = $new' "$TEMP_MAPPING")
    echo "$TEMP_MAP" > "$TEMP_MAPPING"
done < "$TEMP_RUNS"

# Apply mapping and upload
jq -c 'sort_by(.dotted_order)[]' "$TRACE_FILE" > "$TEMP_RUNS"

while read -r run; do
    OLD_ID=$(echo "$run" | jq -r '.id')
    OLD_PARENT=$(echo "$run" | jq -r '.parent_run_id // ""')

    # Get new IDs from mapping
    NEW_RUN_ID=$(jq -r --arg id "$OLD_ID" '.[$id]' "$TEMP_MAPPING")
    NEW_PARENT_ID=$(if [ -n "$OLD_PARENT" ] && [ "$OLD_PARENT" != "null" ]; then
        jq -r --arg id "$OLD_PARENT" '.[$id] // ""' "$TEMP_MAPPING"
    else
        echo ""
    fi)

    # Update dotted_order with new run IDs
    DOTTED_ORDER=$(echo "$run" | jq -r '.dotted_order // ""')
    NEW_DOTTED_ORDER="$DOTTED_ORDER"

    # Replace all old IDs in dotted_order with new IDs
    if [ -n "$DOTTED_ORDER" ]; then
        TEMP_MAPPINGS=$(mktemp)
        jq -r 'to_entries[] | "\(.key):\(.value)"' "$TEMP_MAPPING" > "$TEMP_MAPPINGS"
        while IFS= read -r mapping; do
            OLD=$(echo "$mapping" | cut -d: -f1)
            NEW=$(echo "$mapping" | cut -d: -f2)
            NEW_DOTTED_ORDER=$(echo "$NEW_DOTTED_ORDER" | sed "s/$OLD/$NEW/g")
        done < "$TEMP_MAPPINGS"
        rm -f "$TEMP_MAPPINGS"
    fi

    # Get trace_id (root run's new ID)
    TRACE_ID=$(echo "$run" | jq -r '.trace_id // ""')
    NEW_TRACE_ID=$(jq -r --arg id "$TRACE_ID" '.[$id] // $id' "$TEMP_MAPPING")

    # Update run with new IDs and session
    if [ -n "$NEW_PARENT_ID" ]; then
        run=$(echo "$run" | jq --arg sid "$SESSION_ID" --arg rid "$NEW_RUN_ID" --arg pid "$NEW_PARENT_ID" \
            --arg dot "$NEW_DOTTED_ORDER" --arg tid "$NEW_TRACE_ID" \
            '.session_id = $sid | .id = $rid | .parent_run_id = $pid | .dotted_order = $dot | .trace_id = $tid')
    else
        run=$(echo "$run" | jq --arg sid "$SESSION_ID" --arg rid "$NEW_RUN_ID" \
            --arg dot "$NEW_DOTTED_ORDER" --arg tid "$NEW_TRACE_ID" \
            '.session_id = $sid | .id = $rid | del(.parent_run_id) | .dotted_order = $dot | .trace_id = $tid')
    fi

    RUN_ID=$(echo "$run" | jq -r '.id')
    RUN_NAME=$(echo "$run" | jq -r '.name')

    TEMP_RESP=$(mktemp)
    HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TEMP_RESP" \
        -X POST \
        -H "x-api-key: $LANGSMITH_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$run" \
        "$API_BASE/api/v1/runs" 2>/dev/null)

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
        UPLOADED=$((UPLOADED + 1))
        echo "  ✓ [$UPLOADED/$TOTAL] $RUN_NAME"
    else
        FAILED=$((FAILED + 1))
        ERROR_MSG=$(cat "$TEMP_RESP" 2>/dev/null | jq -r '.error // .detail // "Unknown error"' 2>/dev/null || echo "Unknown error")
        echo "  ✗ Failed: $RUN_NAME (HTTP $HTTP_CODE: $ERROR_MSG)"
    fi
    rm -f "$TEMP_RESP"
done < "$TEMP_RUNS"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Error: $FAILED/$TOTAL runs failed to upload"
    exit 1
fi

echo ""
echo "Success: Uploaded $UPLOADED/$TOTAL runs to project '$PROJECT_NAME'"
