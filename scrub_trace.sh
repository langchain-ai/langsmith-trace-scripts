#!/bin/bash
set -euo pipefail

# Scrub PII from a LangSmith trace
# Usage: ./scrub_trace.sh <trace_file> <field1,field2,...>

show_help() {
    cat << EOF
Scrub PII from a LangSmith trace by redacting fields

USAGE:
    $0 <trace_file> <fields>

ARGUMENTS:
    trace_file  - JSON file with extracted trace
    fields      - Comma-separated field names to redact (recursively)

OUTPUT:
    Creates <trace_file>.scrubbed.json

EXAMPLES:
    # Redact all 'content' and 'email' fields anywhere in the trace
    $0 trace.json "content,email"

    # Redact nested metadata fields
    $0 trace.json "api_key,session_id,user_id"

COMMON FIELDS:
    content      - Message content (finds all content fields)
    email        - Email addresses
    messages     - Entire messages arrays
    session_id   - Session IDs
    user_id      - User IDs
    api_key      - API keys

NOTE: Fields are matched recursively at any depth, including inside arrays.

EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

TRACE_FILE="${1:-}"
FIELDS="${2:-}"

if [ -z "$TRACE_FILE" ] || [ -z "$FIELDS" ]; then
    echo "Error: trace_file and fields required"
    echo "Run '$0 --help' for usage"
    exit 1
fi

if [ ! -f "$TRACE_FILE" ]; then
    echo "Error: File not found: $TRACE_FILE"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq required. Install with: brew install jq"
    exit 1
fi

OUTPUT_FILE="${TRACE_FILE%.json}.scrubbed.json"

echo "Scrubbing trace..."
echo "Input: $TRACE_FILE"
echo "Output: $OUTPUT_FILE"
echo "Fields: $FIELDS"
echo ""

# Build jq filter for recursive redaction
IFS=',' read -ra FIELD_LIST <<< "$FIELDS"
JQ_FILTER='walk(if type == "object" then'

for field in "${FIELD_LIST[@]}"; do
    # Trim whitespace
    field="${field#"${field%%[![:space:]]*}"}"  # trim leading
    field="${field%"${field##*[![:space:]]}"}"  # trim trailing

    # Add recursive field check
    JQ_FILTER="$JQ_FILTER if has(\"$field\") then .\"$field\" = \"[REDACTED]\" else . end |"
done

# Remove trailing pipe and close
JQ_FILTER="${JQ_FILTER% |} else . end)"

# Apply redactions
if ! jq "$JQ_FILTER" "$TRACE_FILE" > "$OUTPUT_FILE"; then
    echo "Error: Failed to apply redactions"
    rm -f "$OUTPUT_FILE"
    exit 1
fi

# Verify output
if ! jq -e . "$OUTPUT_FILE" &>/dev/null; then
    echo "Error: Output is invalid JSON"
    rm -f "$OUTPUT_FILE"
    exit 1
fi

echo "Success: Scrubbed trace saved to $OUTPUT_FILE"
echo ""
echo "IMPORTANT: Manually review $OUTPUT_FILE before sending to ensure all PII is removed!"
