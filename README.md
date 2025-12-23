# LangSmith Trace Export & PII Scrubbing

Simple bash scripts to extract, scrub, and upload LangSmith traces.

## Quick Start

### Extract and Scrub PII

Customers extract their trace and scrub sensitive data before sending:

```bash
# 1. Extract trace
export LANGSMITH_API_KEY='your-api-key'
./extract_trace.sh 00000000-0000-0000-f319-b36446ca3f23

# 2. Scrub PII (recursively redacts field names)
./scrub_trace.sh trace_00000000-0000-0000-f319-b36446ca3f23.json "content,email"

# 3. Review scrubbed file manually

# 4. Send trace_00000000-0000-0000-f319-b36446ca3f23.scrubbed.json to support
```

### Upload

LangChain team uploads the scrubbed trace to a tracing project:

```bash
export LANGSMITH_API_KEY='your-api-key'
./upload_trace.sh customer_trace.scrubbed.json "customer-issue-1234"
```

The script will create a new tracing project with the specified name. You can delete the project later if needed.

## Requirements

- `bash`
- `curl`
- `jq` (install: `brew install jq` or `apt-get install jq`)

## Scripts

### `extract_trace.sh`

Extract a trace by ID.

```bash
./extract_trace.sh <trace_id> [output_file]
```

**Output:** `trace_<id>.json`

### `scrub_trace.sh`

Redact PII fields from trace using recursive field name matching.

```bash
./scrub_trace.sh <trace_file> "<field1>,<field2>,..."
```

**Output:** `<trace_file>.scrubbed.json`

**Common fields to redact:**
- `content` - Message content (finds all content fields)
- `email` - Email addresses
- `messages` - Entire message arrays
- `query` - Search queries
- `text` - Generated text
- `session_id` - Session IDs
- `user_id` - User IDs
- `api_key` - API keys

**Recursive matching:** Field names are matched at any depth in the JSON structure, including inside arrays and nested objects. For example, specifying `content` will redact all fields named `content` anywhere in the trace.

### `upload_trace.sh`

Upload scrubbed trace to a LangSmith tracing project.

```bash
./upload_trace.sh <trace_file> <project_name>
```

Creates a new tracing project with the specified name and uploads all runs to it.

## Complete Example

**Extract and Scrub PII:**
```bash
export LANGSMITH_API_KEY='lsv2_pt_...'

# Extract
./extract_trace.sh a1b2c3d4-5678-90ab-cdef-1234567890ab

# Scrub
./scrub_trace.sh trace_a1b2c3d4-5678-90ab-cdef-1234567890ab.json \
  "content,email,session_id"

# Review and send trace_a1b2c3d4-5678-90ab-cdef-1234567890ab.scrubbed.json to support
```

**Upload (creates new tracing project):**
```bash
export LANGSMITH_API_KEY='lsv2_pt_...'

./upload_trace.sh trace_a1b2c3d4-5678-90ab-cdef-1234567890ab.scrubbed.json \
  "customer-acme-issue-5678"

# Creates a tracing project named "customer-acme-issue-5678" with the uploaded runs
```

## Help

Each script has a `--help` flag:

```bash
./extract_trace.sh --help
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
