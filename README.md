# LangSmith Trace Export & PII Scrubbing

Simple bash scripts to extract, scrub, and upload LangSmith traces.

## Quick Start

### Customer Workflow

```bash
# 1. Extract trace
export LANGSMITH_API_KEY='your-customer-key'
./extract_langsmith_run.sh 00000000-0000-0000-f319-b36446ca3f23

# 2. Scrub PII
./scrub_trace.sh trace_00000000-0000-0000-f319-b36446ca3f23.json "inputs.messages,inputs.email"

# 3. Review the scrubbed file manually

# 4. Send trace_00000000-0000-0000-f319-b36446ca3f23.scrubbed.json to LangChain support
```

### LangChain Team Workflow

```bash
# Upload customer's scrubbed trace
export LANGSMITH_API_KEY='your-langchain-key'
./upload_trace.sh customer_trace.scrubbed.json "customer-issue-1234"
```

## Requirements

- `bash`
- `curl`
- `jq` (install: `brew install jq` or `apt-get install jq`)

## Scripts

### `extract_langsmith_run.sh`

Extract a trace by ID.

```bash
./extract_langsmith_run.sh <trace_id> [output_file]
```

**Output:** `trace_<id>.json`

### `scrub_trace.sh`

Redact PII fields from trace.

```bash
./scrub_trace.sh <trace_file> "<field1>,<field2>,..."
```

**Output:** `<trace_file>.scrubbed.json`

**Common fields to redact:**
- `inputs.messages` - User messages
- `inputs.email` - Email addresses
- `inputs.query` - Search queries
- `outputs.text` - Generated text
- `extra.metadata.session_id` - Session IDs
- `extra.metadata.user_id` - User IDs
- `extra.metadata.api_key` - API keys

**Handles nested fields:** Use dot notation (e.g., `extra.metadata.api_key`)

### `upload_trace.sh`

Upload scrubbed trace to LangSmith project.

```bash
./upload_trace.sh <trace_file> <project_name>
```

## Complete Example

```bash
# Customer side
export LANGSMITH_API_KEY='lsv2_pt_...'

# Extract
./extract_langsmith_run.sh a1b2c3d4-5678-90ab-cdef-1234567890ab

# Scrub
./scrub_trace.sh trace_a1b2c3d4-5678-90ab-cdef-1234567890ab.json \
  "inputs.messages,inputs.email,extra.metadata.session_id"

# Review trace_a1b2c3d4-5678-90ab-cdef-1234567890ab.scrubbed.json

# Send to support

# ---

# LangChain team side
export LANGSMITH_API_KEY='lsv2_pt_...'

./upload_trace.sh trace_a1b2c3d4-5678-90ab-cdef-1234567890ab.scrubbed.json \
  "customer-acme-issue-5678"
```

## Help

Each script has a `--help` flag:

```bash
./extract_langsmith_run.sh --help
./scrub_trace.sh --help
./upload_trace.sh --help
```

## EU Region

Set `LANGSMITH_ENDPOINT` for EU:

```bash
export LANGSMITH_ENDPOINT='https://eu.api.smith.langchain.com'
```

## Troubleshooting

**"jq required"**
```bash
brew install jq  # macOS
apt-get install jq  # Linux
```

**"No runs found"**
- Trace ID doesn't exist
- Trace not fully ingested (wait a few seconds)
- Wrong API key

**"Failed to create project"**
- API key invalid or expired
- No write permissions

## Important

**Customers must manually review scrubbed files before sending** to ensure all PII is removed.
