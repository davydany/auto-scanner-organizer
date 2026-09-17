# Claude Messages API — Raw HTTPS Reference for Swift/URLSession (M2)

> **Scope note (2026-09-14):** compiled from the claude-api skill docs and live documentation fetches for Milestone 2. The request examples in §2 and §3 use illustrative schemas and tool names (`list_folders`, `choose_folder`). The app's real tools are `list_folder`, `read_note`, and `submit_placement` (spec §8.3), and its schemas are defined in the Milestone 2 plan. The wire shapes (placement of `output_config`, `strict`, `tool_result`, `cache_control`, `stop_details`, `usage`) are what this file pins. Items marked UNCONFIRMED are not relied on: the app does not send `fallbacks`.

Models in scope: `claude-sonnet-5`, `claude-opus-5`, `claude-haiku-4-5-20251001` (alias `claude-haiku-4-5`).
No official Swift SDK exists — every shape below is the literal wire JSON to send/parse with `URLSession`.

---

## 1. Endpoint and headers

**URL:** `POST https://api.anthropic.com/v1/messages`
Source: `curl/examples.md:16`

**Required headers** (source: `curl/examples.md:251-256`):

| Header | Value | Notes |
|---|---|---|
| `content-type` | `application/json` | required |
| `x-api-key` | your API key | required (or `Authorization: Bearer <token>` for OAuth — never both `x-api-key` and OAuth header; sending both `ANTHROPIC_API_KEY`-style key + OAuth token is a 401, per `shared/error-codes.md:61`) |
| `anthropic-version` | `2023-06-01` | required, literal string, not tied to model version |
| `anthropic-beta` | comma-separated beta IDs | only for beta features |

**Beta headers for M2 features — none required.** For all three models:
- Structured outputs (`output_config.format`) — GA, no beta header (`shared/tool-use-concepts.md:473-511`, confirmed by WebFetch of the structured-outputs doc).
- Strict tool use (`strict: true`) — GA, no beta header (`shared/tool-use-concepts.md` "Quick Reference" / Common Pitfalls: "Strict tool use (no beta)").
- Vision (base64 images) — GA, no beta header.
- Prompt caching (`cache_control`) — GA, no beta header.

If you later add features, these betas apply (not needed for the two M2 request shapes below):
- Fast mode (Opus 5 / Opus 4.8 only, Claude API only): `fast-mode-2026-02-01`.
- Server-side refusal fallback (`"default"` form): `server-side-fallback-2026-07-01`. (Array form uses `server-side-fallback-2026-06-01`; the two are mutually exclusive — pairing the wrong header with a form is a 400.)
- Mid-conversation tool changes: `mid-conversation-tool-changes-2026-07-01` (Opus 5 onward only).

---

## 2. Request: "read a stack of scanned pages" (structured output over images)

Source: `curl/examples.md` (Basic/Caching examples), `shared/prompt-caching.md`, `shared/tool-use-concepts.md` (Structured Outputs), WebFetch of `vision.md` and `structured-outputs.md`.

```json
{
  "model": "claude-sonnet-5",
  "max_tokens": 4096,
  "system": [
    {
      "type": "text",
      "text": "You are a document-filing assistant. Extract structured fields from scanned pages exactly as instructed.",
      "cache_control": { "type": "ephemeral" }
    }
  ],
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "Page 1:" },
        {
          "type": "image",
          "source": {
            "type": "base64",
            "media_type": "image/jpeg",
            "data": "<BASE64_JPEG_BYTES_PAGE_1>"
          }
        },
        { "type": "text", "text": "Page 2:" },
        {
          "type": "image",
          "source": {
            "type": "base64",
            "media_type": "image/jpeg",
            "data": "<BASE64_JPEG_BYTES_PAGE_2>"
          }
        },
        { "type": "text", "text": "Extract the document metadata as JSON matching the schema." }
      ]
    }
  ],
  "output_config": {
    "format": {
      "type": "json_schema",
      "schema": {
        "type": "object",
        "properties": {
          "document_type": { "type": "string", "enum": ["invoice", "receipt", "letter", "form", "other"] },
          "vendor_or_sender": { "type": "string" },
          "date": { "type": "string", "format": "date" },
          "total_amount": { "type": "string" },
          "currency": { "type": "string" },
          "summary": { "type": "string" }
        },
        "required": ["document_type", "vendor_or_sender", "date", "total_amount", "currency", "summary"],
        "additionalProperties": false
      }
    }
  }
}
```

**Placement notes:**
- `output_config` is a **top-level sibling of `model`/`max_tokens`/`messages`**, not nested inside `messages`.
- `output_config.format.type` must be the literal string `"json_schema"`; the schema is `output_config.format.schema`.
- `cache_control` goes on the last block of the *stable* prefix. Render order is `tools → system → messages`, so a breakpoint on the last `system` block caches system (+ tools) together. Don't mark per-request content (images/OCR text) — only genuinely stable content (system prompt, a stable "vault folder index").
- Recommended (not enforced): images before the text referring to them ("Claude works best when images come before text" — WebFetch `vision.md`).
- Label each image ("Page 1:", "Page 2:") so later turns can refer to it by index.

### JSON Schema support/limits for `output_config.format.schema`
Source: WebFetch `structured-outputs.md`, corroborated by `shared/tool-use-concepts.md:486-503`.

**Supported:** `object`, `array`, `string`, `integer`, `number`, `boolean`, `null`; `enum` (scalars only — no complex types inside enum); `const`; `anyOf`/`allOf` (with limitations); internal `$ref`/`$def`/`definitions`; `default`; `required`; `additionalProperties: false`; string `format`: `date-time`, `time`, `date`, `duration`, `email`, `hostname`, `uri`, `ipv4`, `ipv6`, `uuid`; array `minItems` of `0` or `1` only.

**NOT supported (will fail or be silently stripped by SDKs — you must hand-write compliant schemas since there is no Swift SDK to auto-strip them):**
- Recursive schemas
- Numeric constraints: `minimum`, `maximum`, `multipleOf`
- String constraints: `minLength`, `maxLength`, `pattern` (regex)
- Array constraints beyond `minItems` 0/1 (no `maxItems`, no `uniqueItems`, etc.)
- `additionalProperties` set to anything other than `false` (every `object` must set `additionalProperties: false`)
- External `$ref` (e.g. `$ref: "http://..."`)

Workaround for constraints you need enforced (e.g. `age` 0–150): move the constraint into the field's natural-language `description` and validate client-side in Swift after decoding — there is no server-side enforcement path for it.

**Incompatible combinations:** `output_config.format` cannot be combined with `citations` (400) or with assistant message prefill (prefill is removed entirely on these three models anyway — see §10).

### `thinking` and `effort` with structured outputs, per model

| Model | `thinking` when using structured outputs | `effort` allowed? |
|---|---|---|
| `claude-sonnet-5` | Omit it (or send `{"type":"adaptive"}`, equivalent) — thinking is adaptive-on by default; no request-shape conflict with `output_config.format`. `{"type":"disabled"}` is accepted if you want it off. `budget_tokens` always 400s. | Yes — `low`/`medium`/`high`/`xhigh`/`max`, default `high`. Goes in `output_config.effort` alongside `format`, e.g. `"output_config": {"format": {...}, "effort": "medium"}`. |
| `claude-opus-5` | Omit it — thinking is **on by default**. `{"type":"disabled"}` is accepted only at `effort` `high` or below (400 at `xhigh`/`max`). `budget_tokens` always 400s. | Yes — full ladder `low`…`max`, default `high`, same `output_config.effort` placement. |
| `claude-haiku-4-5` | Uses the **older thinking model**: omit `thinking` entirely for no thinking, or send `{"type":"enabled","budget_tokens":N}` (N must be < `max_tokens`, minimum 1024) to turn it on. No `adaptive` type on this model. | **No** — `effort` errors on Haiku 4.5 (per `shared/model-migration.md:302` and the official models table: "Default effort: Not supported"). Do not send `output_config.effort` for this model. |

Source: `shared/model-migration.md` §§ "Migrating to Claude Sonnet 5", "Migrating to Claude Opus 5"; official models-overview table (WebFetch) row "Thinking"/"Default effort".

---

## 3. Request: "choose a folder with read-only tools" (tool-use loop)

Source: `curl/examples.md:99-156`, `shared/tool-use-concepts.md` (Tool Definition Structure, Tool Choice Options, Strict tool use, Handling Tool Results).

### Tool definitions

```json
{
  "model": "claude-sonnet-5",
  "max_tokens": 2048,
  "tools": [
    {
      "name": "list_folders",
      "description": "List candidate destination folders under the filing vault root. Call this when you need to see what folders currently exist before deciding where to file a document.",
      "input_schema": {
        "type": "object",
        "properties": {
          "path": { "type": "string", "description": "Vault-relative path to list, e.g. '' for root or 'Finance/Invoices'." }
        },
        "required": ["path"]
      }
    },
    {
      "name": "choose_folder",
      "description": "Final answer: report the single destination folder chosen for this document. Call this exactly once, after you have enough information.",
      "strict": true,
      "input_schema": {
        "type": "object",
        "properties": {
          "folder_path": { "type": "string", "description": "Vault-relative destination folder path." },
          "confidence": { "type": "string", "enum": ["high", "medium", "low"] },
          "reasoning": { "type": "string" }
        },
        "required": ["folder_path", "confidence", "reasoning"],
        "additionalProperties": false
      }
    }
  ],
  "tool_choice": { "type": "auto" },
  "messages": [
    { "role": "user", "content": "Here is the extracted document metadata: {...}. Choose the best destination folder." }
  ]
}
```

**Key shape notes:**
- `strict: true` is a **top-level field on the tool definition** (sibling of `name`/`description`/`input_schema`), **not** on `tool_choice`. Schema must set `additionalProperties: false` and list `required` fields (no beta header — GA).
- Read-only tools (e.g. `list_folders`, a `read_folder_index` with an empty schema) don't need `strict`; only the final-answer tool needs the guarantee.

### `tool_choice` per model

| Value | Behavior | Rejected on any of the 3 models? |
|---|---|---|
| `{"type": "auto"}` | Claude decides (default) | No — accepted everywhere |
| `{"type": "any"}` | Must use at least one tool | No — accepted on Sonnet 5, Opus 5, Haiku 4.5 (forced tool use is only rejected on Claude Fable 5.1 / Mythos 5.1 / Mythos Preview, not these three) |
| `{"type": "tool", "name": "..."}` | Must use the named tool | No — accepted on all three |
| `{"type": "none"}` | No tool use | No |

`disable_parallel_tool_use: true` can be added to any `tool_choice` value to cap Claude to one tool call per turn. Source: `shared/tool-use-concepts.md:45-58`; the forced-tool-use rejection is model-specific to Fable/Mythos 5.1, not these three (`shared/error-codes.md:124`). (Bedrock-only, not first-party API: Sonnet 5 there requires `thinking:{"type":"disabled"}` alongside forced `tool_choice`.)

### Assistant `tool_use` block shape (what comes back from Claude)

```json
{
  "id": "msg_01Abc...",
  "type": "message",
  "role": "assistant",
  "model": "claude-sonnet-5",
  "content": [
    { "type": "text", "text": "I'll check the existing folder structure first." },
    {
      "type": "tool_use",
      "id": "toolu_01XYZ...",
      "name": "read_folder_index",
      "input": {}
    }
  ],
  "stop_reason": "tool_use",
  "stop_sequence": null,
  "usage": { "input_tokens": 512, "output_tokens": 40 }
}
```

A single assistant turn may contain **multiple `tool_use` blocks** (parallel tool calls, default on) — execute all of them, then return **all** results in **one** follow-up user message (`shared/tool-use-concepts.md:117`; splitting them across messages "silently trains Claude to stop making parallel calls").

### Follow-up user message with `tool_result` blocks

```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "toolu_01XYZ...",
      "content": "{\"folders\": [\"Finance/Invoices\", \"Finance/Receipts\", \"Personal/Letters\"]}"
    },
    {
      "type": "tool_result",
      "tool_use_id": "toolu_02OTHER...",
      "content": "Error: path does not exist",
      "is_error": true
    }
  ]
}
```

- `content` can be a plain string or an array of content blocks (e.g. `text`/`image`) — a plain string is the common case for read-only tool output.
- `is_error: true` marks a failed tool call — **do not drop failed calls**; return them as errors so Claude can adapt (`shared/tool-use-concepts.md:115`).
- Always parse `tool_use.input` as JSON (`JSON.parse`/`JSONSerialization` in Swift) — **never string-match it**. Sonnet 5/Opus 5/Haiku-4.5-generation models can emit different but valid JSON escaping (Unicode escapes, forward-slash escaping) for the same logical value (`shared/model-migration.md:348-350`, Common Pitfalls).

### Appending the assistant's content back into the conversation

Always append the **full, unmodified `response.content` array** (not just extracted text) as the next `assistant` message before sending the `tool_result` follow-up — this preserves `tool_use` blocks (and `thinking` blocks, if thinking is enabled) exactly as the model produced them:

```json
{ "role": "assistant", "content": [ /* verbatim response.content from the previous turn */ ] }
```

If `thinking` was enabled and thinking blocks were returned, they must also be echoed back unchanged on the next turn on the *same* model — this is required for Sonnet 5/Opus 5 (both preserve prior-turn thinking blocks by default) so the messages cache stays valid; on Haiku 4.5 (and earlier-generation models) a following plain user message strips previously-cached thinking blocks from context regardless (`shared/prompt-caching.md:240`). Never hand-edit or delete earlier `tool_use`/`tool_result`/`thinking` blocks from history — treat the transcript as append-only.

### Loop termination

Loop while `stop_reason == "tool_use"`; the loop ends when `stop_reason` is `"end_turn"` (or a terminal value from §4's full enum: `end_turn`, `max_tokens`, `stop_sequence`, `tool_use`, `pause_turn`, `refusal`, `model_context_window_exceeded`). For a `choose_folder`-driven loop you can also stop as soon as a `tool_use` block names `choose_folder` (defined as call-once), but still check `stop_reason` for refusals/truncation.

`pause_turn` applies only to **server-side** tools (web search, code execution) hitting their internal iteration cap — not the client-side tools here — but a shared loop should still handle it: resend the same `user` turn + assistant `response.content` with no new user message; the server resumes automatically.

---

## 4. Response body

Source: `curl/examples.md`, `shared/tool-use-concepts.md`, `shared/error-codes.md`, `shared/prompt-caching.md`, WebFetch structured-outputs doc.

### Top-level envelope

```json
{
  "id": "msg_01Abc123...",
  "type": "message",
  "role": "assistant",
  "model": "claude-sonnet-5",
  "content": [ /* array of content blocks, see below */ ],
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "stop_details": null,
  "usage": {
    "input_tokens": 1024,
    "output_tokens": 256,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 800,
    "cache_creation": {
      "ephemeral_5m_input_tokens": 0,
      "ephemeral_1h_input_tokens": 0
    }
  }
}
```

### `content` block types relevant to M2

| `type` | Fields | When |
|---|---|---|
| `text` | `text` | Normal assistant text, and where the **structured-output JSON appears** (see below) |
| `tool_use` | `id`, `name`, `input` (object) | Model wants to call a tool |
| `thinking` | `thinking` (text, possibly empty string), `signature` | Only if `thinking` is enabled/adaptive; text is empty when `display` is `"omitted"` (the default on Sonnet 5/Opus 5) |

Haiku 4.5 uses the older `enabled`/`budget_tokens` thinking mode, not adaptive; its `thinking` blocks behave the same shape-wise when `thinking.type: "enabled"` is set.

### Where structured-output JSON appears

With `output_config.format` set, the JSON result appears **as a string inside a normal `text` content block** — it is not a separate block type:

```json
{
  "content": [
    { "type": "text", "text": "{\"document_type\":\"invoice\",\"vendor_or_sender\":\"Acme Corp\",\"date\":\"2026-01-15\",\"total_amount\":\"482.50\",\"currency\":\"USD\",\"summary\":\"Office supplies invoice\"}" }
  ],
  "stop_reason": "end_turn"
}
```
`response.content[0].text` is guaranteed to be valid JSON matching your schema **when `stop_reason == "end_turn"`**. On `stop_reason == "max_tokens"` the JSON may be truncated/incomplete; on `stop_reason == "refusal"` it may not match the schema at all — always branch on `stop_reason` before parsing.
Source: WebFetch `structured-outputs.md` § Response Shape.

### `stop_reason` values

| Value | Meaning |
|---|---|
| `end_turn` | Natural completion |
| `max_tokens` | Hit the requested `max_tokens` cap (thinking + text share this budget on Sonnet 5 / Opus 5) |
| `stop_sequence` | Hit a custom stop sequence you supplied |
| `tool_use` | Model produced one or more `tool_use` blocks and is waiting on results |
| `pause_turn` | Server-side tool loop hit its internal cap (10 iterations); resend to resume |
| `refusal` | Safety classifier or model declined; `content` may be empty or partial |
| `model_context_window_exceeded` | Context window limit hit (distinct from `max_tokens`, which is the output cap) |

Source: `shared/tool-use-concepts.md`, `shared/model-migration.md:437-448`, `shared/tool-use-concepts.md` "Stop details" quick reference.

### `stop_details` (only populated on refusal)

```json
{
  "stop_reason": "refusal",
  "stop_details": {
    "type": "refusal",
    "category": "cyber",
    "explanation": "..."
  }
}
```
`stop_details` is `null` for every other `stop_reason` (`end_turn`, `max_tokens`, `tool_use`, `pause_turn`, ...) — **guard before reading it**; `category` is an open set (`"cyber"`, `"bio"`, `"reasoning_extraction"`, `"frontier_llm"`, or `null` — `null` is a valid permanent state, not "unset"). Always branch on `stop_reason`, never on `stop_details`, since `stop_details` can itself be `null` on a refusal. Source: "Other API Surfaces (Quick Reference)" § Stop details, and `shared/model-migration.md:1362`.

### `usage` fields

| Field | Meaning |
|---|---|
| `input_tokens` | Uncached tokens processed at full price (the uncached remainder only — NOT total prompt size) |
| `output_tokens` | Generated tokens (thinking + visible text combined where thinking counts against output) |
| `cache_creation_input_tokens` | Tokens written to cache this request (~1.25×/2× cost — see §7) |
| `cache_read_input_tokens` | Tokens served from cache this request (~0.1× cost on all three of these models) |
| `cache_creation.ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens` | Breakdown of `cache_creation_input_tokens` by TTL |

Total prompt size = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. If `cache_read_input_tokens` is 0 across repeated identical-prefix requests, caching is silently broken. Source: `shared/prompt-caching.md:180-208`.

---

## 5. Errors and retries

Source: `shared/error-codes.md`.

### Error JSON body shape

```json
{
  "type": "error",
  "error": {
    "type": "invalid_request_error",
    "message": "messages: roles must alternate between \"user\" and \"assistant\""
  },
  "request_id": "req_011CSHoEeqs5C35K2UUqR7Fy"
}
```

### HTTP status codes / error `type` / retryability

| Code | `error.type` | Retryable | Common cause |
|---|---|---|---|
| 400 | `invalid_request_error` | No | Malformed JSON, missing `model`/`max_tokens`/`messages`, bad schema, unsupported param combo, unknown `anthropic-beta` value |
| 401 | `authentication_error` | No | Missing/invalid `x-api-key`, or OAuth token sent via wrong header, or both key+token set |
| 402 | `billing_error` | No | Billing/payment problem |
| 403 | `permission_error` | No | Org/workspace not permitted for this operation/model/region |
| 404 | `not_found_error` | No | Unknown/typo'd model ID, or a model your org can't use (same response either way — API doesn't reveal existence) |
| 413 | `request_too_large` | No | Request body exceeds size limit |
| 429 | `rate_limit_error` | **Yes** | RPM/TPM/TPD exceeded |
| 500 | `api_error` | **Yes** | Anthropic-side issue |
| 529 | `overloaded_error` | **Yes** | Temporary overload |

Not in the summary table but present in the typed-exception list: **422** `UnprocessableEntityError`-class (validated request that fails semantic processing) — treat as non-retryable like 400.

**Retryable set in practice (matches SDK default retry policy):** 408, 409, 429, and all 5xx, plus network/connection failures before any response. Non-retryable: 400, 401, 402, 403, 404, 413, 422. (`shared/error-codes.md` "Client config" quick reference: `max_retries` default 2, retries `408/409/429/5xx` + connection errors.)

### `retry-after` header (on 429)

Seconds to wait before retrying. Also inspect `x-ratelimit-limit-*` / `x-ratelimit-remaining-*` for RPM/TPM/TPD quota state. Implement exponential backoff on top of `retry-after` for 429/500/529. Source: `shared/error-codes.md:147-153`.

### Request size limit

**32 MB** for standard Claude API endpoints (lower on some partner platforms — e.g. Bedrock/Vertex). This can be hit before the 100/600-image count limit when sending many base64 images; prefer the Files API (`file_id` references) for large multi-image payloads to keep the JSON body small. Source: WebFetch `vision.md` § Request limits.

---

## 6. Images

Source: WebFetch `vision.md` (authoritative — supersedes any cached skill defaults).

| Limit | Value |
|---|---|
| Max images per API request | **600** for models with >200K context (Sonnet 5, Opus 5); **100** for models with a 200K context window (Haiku 4.5) |
| Max image dimensions | 8000×8000 px (hard cap; if >20 image/document blocks are in one request, a stricter effective limit kicks in — see below) |
| Max image size (base64-encoded), first-party Claude API | **10 MB** per image |
| Supported media types | `image/jpeg`, `image/png`, `image/gif`, `image/webp` (GIF/WebP animations unsupported — only first frame used) |

**>20-image-blocks-per-request rule:** if a single request contains more than 20 total `image` (+ document, on Bedrock/Vertex) blocks — counting every image across all turns you resend, plus images nested in `tool_result` blocks — a stricter per-image pixel limit applies to *every* image in that request, and oversized images are rejected with `invalid_request_error` (not silently downscaled) referencing "many-image requests." Practical fix: resize every image to ≤2000px per side, or keep the request to ≤20 image/document blocks.

### Resolution tier and token cost formula

Claude tiles images into 28×28-pixel patches ("visual tokens"):

```
tokens = ceil(width / 28) × ceil(height / 28)
```

| Resolution tier | Models | Max long edge | Max visual tokens |
|---|---|---|---|
| High-resolution | Claude 4.7-and-later (**Sonnet 5, Opus 5** qualify) | 2576 px | 4784 |
| Standard | All other models (**Haiku 4.5** — pre-4.7 generation) | 1568 px | 1568 |

Images larger than the tier's long-edge/token limit are downscaled preserving aspect ratio (unless the image block sets `"transformations"`/`"oversized_image": "error"`, in which case it's rejected instead of resized). High-res tier images can cost ~3× the visual tokens of the same image on standard tier — downsample before sending to Haiku 4.5 workflows if you don't need the extra fidelity, or before sending to Sonnet 5/Opus 5 if you don't need the high-res gain.

### base64 image content block shape

```json
{
  "type": "image",
  "source": {
    "type": "base64",
    "media_type": "image/jpeg",
    "data": "<BASE64_BYTES_NO_NEWLINES>"
  }
}
```

### Image-before-text rule

Recommendation, not enforced (see §2): images before referring text perform best; after/interleaved "still perform[s] well" (WebFetch `vision.md`).

---

## 7. Prompt caching

Source: `shared/prompt-caching.md`.

### `cache_control` block shape

```json
"cache_control": { "type": "ephemeral" }              // 5-minute TTL (default)
"cache_control": { "type": "ephemeral", "ttl": "1h" }  // 1-hour TTL
```

Goes on any content block: system text blocks, tool definitions, message content blocks (`text`, `image`, `tool_use`, `tool_result`, `document`). Render order is `tools → system → messages`; a breakpoint anywhere caches everything rendered before it too.

### Max breakpoints

**4 per request** (explicit `cache_control` markers; a top-level automatic-caching field also counts as one of the 4 if used).

### Minimum cacheable prefix per model

| Model | Minimum tokens |
|---|---:|
| `claude-opus-5` | **512** |
| `claude-sonnet-5` | **1024** |
| `claude-haiku-4-5` | **4096** |

Shorter prefixes silently don't cache — no error, just `cache_creation_input_tokens: 0`. Not monotonic across generations (Opus 5 is lower than Sonnet 5, which is lower than Haiku 4.5). Source: `shared/prompt-caching.md:133-140`.

### Cache pricing multipliers (relative to that model's base input price; absolute $/MTok in §9)

- Cache read: **~0.1×** base input price (all three models — the 0.025× rate is Fable 5.1/Mythos 5.1 only).
- Cache write: **1.25×** for 5-minute TTL, **2×** for 1-hour TTL.
- Break-even: 5-min TTL pays off after 2 requests sharing the prefix; 1-hour TTL needs ≥3 requests.

### Invalidation rules relevant to a stable system prompt + stable vault folder index

- Keep the system prompt **and** the vault folder index byte-identical across requests; place `cache_control` on the last block of that combined stable prefix.
- Don't interpolate timestamps/request IDs/per-request state into the system prompt or folder index — any byte change invalidates everything after that point in render order.
- Tools and `model` are also part of the prefix — adding/removing/reordering tools, or switching models, invalidates the **entire** cache (no escape hatch on Haiku 4.5/Sonnet 5; Opus 5 has a mid-conversation tool-change beta, out of scope for M2). Serialize tools deterministically.
- Put the folder index before the last breakpoint and before per-request content (OCR text, per-document questions) — mark the end of the shared portion, not the end of the whole prompt.
- Verify hits via `usage.cache_read_input_tokens` after every prompt-assembly change — a silent regression shows as reads staying at 0 with no error.

---

## 8. Refusals and fallbacks

Source: `shared/model-migration.md` (Opus 5 / Sonnet 5 sections), `shared/tool-use-concepts.md`, `curl/examples.md`, `shared/platform-availability.md`.

### What a refusal looks like

HTTP **200** (not an error status), with:
```json
{
  "stop_reason": "refusal",
  "stop_details": { "type": "refusal", "category": "cyber", "explanation": "..." },
  "content": []
}
```
A refusal that fires **before any output** returns empty `content` and is **not billed at all** (no input or output tokens, no rate-limit consumption). A refusal firing **mid-stream** bills the already-streamed partial output at normal rates — discard it rather than treating it as complete. Both **Claude Opus 5** and **Claude Sonnet 5** ship "elevated"/cyber-capable-model safety classifiers that can produce this outcome on benign security/life-sciences prompts; **always check `stop_reason` before indexing `response.content[0]`.**

### `fallbacks` availability per model — CONFIRMED for Opus 5, UNCONFIRMED for Sonnet 5 and Haiku 4.5

- **`claude-opus-5`:** documented and recommended. Use the `"default"` scalar form:
  ```http
  POST /v1/messages
  anthropic-beta: server-side-fallback-2026-07-01

  {"model": "claude-opus-5", "fallbacks": "default", "max_tokens": 1024,
   "messages": [{"role": "user", "content": "..."}]}
  ```
  Routes by refusal category automatically (cyber refusals → `claude-opus-4-8`). The older array form (`"fallbacks": [{"model": "claude-opus-4-8"}]`) uses beta header `server-side-fallback-2026-06-01` instead — the two header/form pairs are mutually exclusive (pairing either header with the wrong form is a 400). Documented permitted fallback **targets** are `claude-opus-4-8` and `claude-opus-5` only. Source: `shared/model-migration.md:980-990,1377-1409`.

- **`claude-sonnet-5`:** documented as having the same cyber-safeguard refusals as Opus 4.7/4.8 (`shared/model-migration.md:1191`), and platform-availability lists `fallbacks` as a platform-level beta (1P + Claude Platform on AWS), not scoped to one request model. But no bundled doc shows a worked example with `"model": "claude-sonnet-5"` as the primary/refusing model, or confirms Sonnet 5 is an accepted source model for the parameter. **UNCONFIRMED** — check the live `fallbacks` reference or `/v1/models` `allowed_fallback_models` before relying on it; implement `stop_reason == "refusal"` handling regardless (that part is confirmed).

- **`claude-haiku-4-5`:** no mention of `refusal` stop reason, cyber safeguards, or `fallbacks` for this model anywhere in the bundled docs. **UNCONFIRMED** whether Haiku 4.5 can even return `stop_reason: "refusal"`. Implement the `refusal` branch defensively for all three models regardless, but don't assume `fallbacks` is meaningful with Haiku 4.5 as the primary model until confirmed live.

### Platform/beta requirement recap

`fallbacks` (either form) is **1P Claude API and Claude Platform on AWS only** — not available on Amazon Bedrock, Google Cloud Vertex AI, or Microsoft Foundry (`shared/platform-availability.md:49`, `curl/examples.md:245`). Rejected on the Batches API.

---

## 9. Pricing table

Source: WebFetch `about-claude/models/overview.md` (authoritative, live-fetched) + `shared/models.md`.

| Model | Input $/MTok | Output $/MTok | Cache write 5m $/MTok | Cache write 1h $/MTok | Cache read $/MTok | Batch (50% off base) |
|---|---:|---:|---:|---:|---:|---|
| `claude-opus-5` | $5.00 | $25.00 | $6.25 | $10.00 | $0.50 | Input $2.50 / Output $12.50 |
| `claude-sonnet-5` | $2.00 | $10.00 | $2.50 | $4.00 | $0.20 | Input $1.00 / Output $5.00 |
| `claude-haiku-4-5` | $1.00 | $5.00 | $1.25 | $2.00 | $0.10 | Input $0.50 / Output $2.50 |

Cache write/batch figures are computed from the documented multipliers (1.25×/2× write, 0.1× read, 0.5× batch) applied to the officially confirmed base input/output prices — the base prices themselves are directly quoted from the live models-overview page; the derived cache/batch columns are **not separately spot-quoted** in the fetched page and should be cross-checked against `https://platform.claude.com/docs/en/about-claude/pricing` before finalizing a cost model.

---

## 10. Gotchas list (raw-HTTP / URLSession-specific)

1. **No assistant prefill.** A `messages` array ending in `role: "assistant"` is a 400 on all three models. Use `output_config.format` or a system-prompt instruction instead.
2. **Sampling params rejected on Sonnet 5/Opus 5.** `temperature`, `top_p`, `top_k` 400 on those two; omit on Haiku 4.5 too for a uniform client.
3. **`budget_tokens` always 400s on Sonnet 5/Opus 5** — use `thinking:{"type":"adaptive"}` + `output_config.effort`. Haiku 4.5 is the opposite: no `adaptive` mode; needs `budget_tokens` (< `max_tokens`, min 1024) for thinking at all.
4. **`effort` 400s on Haiku 4.5** — never send `output_config.effort` for that model.
5. **Parse tool input JSON, never string-match it.** Sonnet 5/Opus 5 can emit different (still-valid) escaping — Unicode/forward-slash — for the same value.
6. **`max_tokens` caps thinking + visible text together** on Sonnet 5/Opus 5 (thinking-on-by-default). A tight cap sized only for the expected answer can truncate mid-response (`stop_reason: "max_tokens"`) — size generously and check `stop_reason`.
7. **Non-streaming timeouts.** ~16K output tokens is the practical non-streaming ceiling before HTTP timeouts; raise `URLSessionConfiguration.timeoutIntervalForRequest` or switch to SSE and accumulate `content_block_delta` yourself — no Swift SDK helper exists.
8. **No SDK auto-retry in raw HTTP.** Implement your own exponential backoff for 429/500/529 + network errors, honoring `retry-after`; fail fast on 400/401/402/403/404/413.
9. **Check `stop_reason` before reading `content`.** A refusal can return an empty `content` array.
10. **`stop_details` is `null` except on refusal** — branch on `stop_reason`, not on `stop_details` presence.
11. **Parallel `tool_use` blocks are normal** — execute all, return all `tool_result`s in one follow-up message, never split across requests.
12. **Tool-use history is append-only** — always resend the model's full `response.content` (thinking blocks included) verbatim; editing/dropping earlier blocks risks 400s and breaks cache reuse.
13. **32 MB request ceiling can be hit before the 600-image cap** — for many-page scans, use the Files API (`file_id`) instead of re-sending base64 on every turn.
14. **`anthropic-version: 2023-06-01` is a fixed literal**, unrelated to today's date or model release date — never bump it.
15. **Compress scanned pages carefully** — heavy JPEG compression can make OCR text illegible before it reaches the model; inspect actual bytes sent, not just file size.
