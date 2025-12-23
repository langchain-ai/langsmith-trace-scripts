#!/bin/bash
set -euo pipefail

# Extract a LangSmith trace by ID
# Usage: ./extract_langsmith_run.sh <trace_id> [output_file]

show_help() {
    cat << EOF
Extract a LangSmith trace by trace ID

USAGE:
    $0 <trace_id> [output_file]

ARGUMENTS:
    trace_id     - The trace ID (UUID)
    output_file  - Optional output file (default: trace_<trace_id>.json)

ENVIRONMENT:
    LANGSMITH_API_KEY  - Your LangSmith API key (required)

EXAMPLE:
    export LANGSMITH_API_KEY='lsv2_pt_...'
    $0 00000000-0000-0000-f319-b36446ca3f23

EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

TRACE_ID="${1:-}"
OUTPUT_FILE="${2:-trace_${TRACE_ID}.json}"

if [ -z "$TRACE_ID" ]; then
    echo "Error: trace_id required"
    echo "Run '$0 --help' for usage"
    exit 1
fi

if [ -z "${LANGSMITH_API_KEY:-}" ]; then
    echo "Error: LANGSMITH_API_KEY not set"
    echo "Run: export LANGSMITH_API_KEY='your-api-key'"
    exit 1
fi

API_BASE="${LANGSMITH_ENDPOINT:-https://api.smith.langchain.com}"
TEMP=$(mktemp)
trap "rm -f $TEMP" EXIT

echo "Extracting trace $TRACE_ID..."

HTTP_CODE=$(curl -sf -w "%{http_code}" -o "$TEMP" \
    -X POST \
    -H "x-api-key: $LANGSMITH_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"trace\": \"$TRACE_ID\"}" \
    "$API_BASE/api/v1/runs/query" || echo "000")

if [ "$HTTP_CODE" != "200" ]; then
    echo "Error: Failed to fetch trace (HTTP $HTTP_CODE)"
    [ -f "$TEMP" ] && cat "$TEMP"
    exit 1
fi

# Extract runs array
if command -v jq &> /dev/null; then
    jq '.runs' "$TEMP" > "$OUTPUT_FILE"
    RUN_COUNT=$(jq 'length' "$OUTPUT_FILE")
else
    echo "Warning: jq not found, saving raw response"
    mv "$TEMP" "$OUTPUT_FILE"
    RUN_COUNT="unknown"
fi

if [ "$RUN_COUNT" = "0" ]; then
    echo "Error: No runs found for trace $TRACE_ID"
    exit 1
fi

echo "Success: Extracted $RUN_COUNT runs to $OUTPUT_FILE"
