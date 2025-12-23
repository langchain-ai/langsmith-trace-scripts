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

# Create project
SESSION_RESP=$(curl -sf -X POST \
    -H "x-api-key: $LANGSMITH_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$PROJECT_NAME\", \"description\": \"Customer debug trace\"}" \
    "$API_BASE/api/v1/sessions" || echo '{"id":""}')

SESSION_ID=$(echo "$SESSION_RESP" | jq -r '.id')

if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ] || [ "$SESSION_ID" = "" ]; then
    echo "Error: Failed to create project"
    echo "$SESSION_RESP"
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
trap "rm -f $TEMP_RUNS" EXIT

jq -c 'sort_by(.dotted_order)[]' "$TRACE_FILE" > "$TEMP_RUNS"

while read -r run; do
    # Add session_id
    run=$(echo "$run" | jq --arg sid "$SESSION_ID" '.session_id = $sid')

    RUN_ID=$(echo "$run" | jq -r '.id')
    RUN_NAME=$(echo "$run" | jq -r '.name')

    HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null \
        -X POST \
        -H "x-api-key: $LANGSMITH_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$run" \
        "$API_BASE/api/v1/runs" 2>/dev/null)

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
        UPLOADED=$((UPLOADED + 1))
        echo "  ✓ [$UPLOADED/$TOTAL] $RUN_NAME"
    elif [ "$HTTP_CODE" = "409" ]; then
        UPLOADED=$((UPLOADED + 1))
        echo "  ⊘ [$UPLOADED/$TOTAL] $RUN_NAME (already exists)"
    else
        FAILED=$((FAILED + 1))
        echo "  ✗ Failed: $RUN_NAME (HTTP $HTTP_CODE)"
    fi
done < "$TEMP_RUNS"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Error: $FAILED/$TOTAL runs failed to upload"
    exit 1
fi

echo ""
echo "Success: Uploaded $UPLOADED/$TOTAL runs to project '$PROJECT_NAME'"
