# LangSmith Trace Export Tools

Simple bash scripts to extract, scrub, and upload LangSmith traces.

## Quick Start

### Extract

Extract a trace from LangSmith:

```bash
export LANGSMITH_API_KEY='your-source-workspace-api-key'
./extract_trace.sh 00000000-0000-0000-f319-b36446ca3f23
```

### Scrub PII (Optional)

If your trace contains sensitive data, scrub it before sharing:

```bash
# Recursively redacts field names
./scrub_trace.sh trace_00000000-0000-0000-f319-b36446ca3f23.json "content,email"

# Review scrubbed file manually before sharing
```

### Upload

Upload a trace to a tracing project:

```bash
export LANGSMITH_API_KEY='your-destination-workspace-api-key'
./upload_trace.sh trace_00000000-0000-0000-f319-b36446ca3f23.json "YOUR_PROJECT_NAME"
```

Replace `YOUR_PROJECT_NAME` with your desired tracing project name (e.g., `my-debug-trace`, `issue-123`, etc.). The script will create a new tracing project with this name and upload the runs to it.

**Note:** The trace will be uploaded to the workspace associated with your API key. If extracting from one workspace and uploading to another, use different API keys for each operation.

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

Field names are matched recursively at any depth in the JSON structure, including inside arrays and nested objects. For example, specifying `content` will redact all fields named `content` anywhere in the trace.

### `upload_trace.sh`

Upload a trace to a LangSmith tracing project.

```bash
./upload_trace.sh <trace_file> <project_name>
```

Creates a new tracing project with the specified name and uploads all runs to it. Run IDs are automatically regenerated to avoid conflicts while preserving parent-child relationships.

The trace file can be either a raw extracted trace or a scrubbed trace.

## Complete Examples

**Example 1: Extract and upload within same workspace**
```bash
export LANGSMITH_API_KEY='lsv2_pt_...'

# Extract
./extract_trace.sh a1b2c3d4-5678-90ab-cdef-1234567890ab

# Upload to new project
./upload_trace.sh trace_a1b2c3d4-5678-90ab-cdef-1234567890ab.json "my-debug-project"
```

**Example 2: Extract, scrub PII, and upload to different workspace**
```bash
# Extract from source workspace
export LANGSMITH_API_KEY='lsv2_pt_source_workspace_key'
./extract_trace.sh a1b2c3d4-5678-90ab-cdef-1234567890ab

# Scrub sensitive data
./scrub_trace.sh trace_a1b2c3d4-5678-90ab-cdef-1234567890ab.json "content,email,api_key"

# Review scrubbed file manually

# Upload to destination workspace
export LANGSMITH_API_KEY='lsv2_pt_destination_workspace_key'
./upload_trace.sh trace_a1b2c3d4-5678-90ab-cdef-1234567890ab.scrubbed.json "shared-trace-123"
```

## Help

Each script has a `--help` flag:

```bash
./extract_trace.sh --help
./scrub_trace.sh --help
./upload_trace.sh --help
```

## Regional Endpoints

By default, scripts use the US region (`https://api.smith.langchain.com`). For other regions, set `LANGSMITH_ENDPOINT`:

**EU Region:**
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

**If scrubbing PII, always manually review the scrubbed file before sharing** to ensure all sensitive data is properly removed.
