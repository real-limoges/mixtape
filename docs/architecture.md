# Architecture

## Overview

Mixtape is an Elixir/OTP application that acts as an API gateway between Anthropic-schema clients (like Claude Code) and locally-running MLX-LM inference servers. It translates requests between Anthropic and OpenAI formats, proxies SSE streams, and monitors model availability.

## System Diagram

```
                         ┌─────────────────────────────────┐
                         │           Mixtape (OTP)          │
                         │                                  │
   Client Request        │  ┌──────────┐   ┌────────────┐  │     ┌──────────────────┐
   (Anthropic schema) ──────▶  Router   ├──▶│   Stream   │──────▶│  MLX-LM :coder   │
   POST /v1/messages     │  │          │   │  Forwarder  │  │     │  (port 8080)     │
                         │  └──────────┘   └────────────┘  │     └──────────────────┘
                         │       │              │           │
                         │       │         Translator       │     ┌──────────────────┐
                         │       │      (Anthropic ↔ OpenAI)│     │  MLX-LM :architect│
                         │       │              │           │     │  (port 8081)     │
                         │       └──────────────┼───────────────▶│                  │
                         │                      │           │     └──────────────────┘
                         │  ┌──────────────────────────┐    │
                         │  │  ModelServer (x2)        │    │           ▲
                         │  │  Health-checks upstream   ├───────────────┘
                         │  │  every 5s via GET /v1/   │    │     (polls /v1/models)
                         │  │  models                  │    │
                         │  └──────────────────────────┘    │
                         │                                  │
                         │  Bandit HTTP server (port 4000)  │
                         └─────────────────────────────────┘
```

## Modules

| Module | File | Role |
|---|---|---|
| `Mixtape.Application` | `lib/mixtape/application.ex` | OTP app entry point. Starts supervisor with two ModelServers and Bandit. |
| `Mixtape.ModelServer` | `lib/mixtape/model_server.ex` | GenServer that health-checks an upstream MLX-LM server. Tracks `:up`/`:down` status. |
| `Mixtape.Router` | `lib/mixtape/router.ex` | Plug.Router handling `/v1/messages` (Anthropic), `/v1/chat/completions` (OpenAI passthrough), and `/health`. |
| `Mixtape.Translator` | `lib/mixtape/translator.ex` | Stateless schema conversion between Anthropic and OpenAI formats. Generates SSE envelope events. |
| `Mixtape.StreamForwarder` | `lib/mixtape/stream_forwarder.ex` | Proxies streaming requests to MLX-LM, translating SSE chunks on the fly. |

## Request Lifecycle

### Anthropic-schema request (`POST /v1/messages`)

1. Client sends an Anthropic-format request to `localhost:4000/v1/messages`
2. **Router** extracts the `model` field and resolves it to an upstream URL and atom (`:coder` or `:architect`)
3. **Router** checks `ModelServer.ready?(model_atom)` -- returns 503 if the model is down
4. **StreamForwarder.forward/3** is called with the connection, upstream URL, and model name
5. **Translator.to_mlx/1** converts the Anthropic request body to OpenAI `/v1/chat/completions` format
6. StreamForwarder sends the chunked response header and emits **envelope start** events (`message_start`, `content_block_start`)
7. **Req** streams the upstream response; each SSE chunk is parsed and passed through **Translator.from_mlx/1**
8. Translated chunks are emitted as Anthropic SSE events (`content_block_delta`)
9. When the stream ends, **envelope stop** events are emitted (`content_block_stop`, `message_delta`, `message_stop`)

### OpenAI-schema request (`POST /v1/chat/completions`)

Same flow but without translation -- chunks are forwarded as-is via `StreamForwarder.forward_raw/3`.

## Schema Translation

### Request (Anthropic → OpenAI)

```
Anthropic input:                    OpenAI output:
{                                   {
  "model": "coder",                   "model": "mlx-model",
  "system": "Be helpful.",            "stream": true,
  "max_tokens": 1024,                 "max_tokens": 1024,
  "messages": [                        "messages": [
    {"role": "user",                     {"role": "system",
     "content": "Hello"}                  "content": "Be helpful."},
  ]                                      {"role": "user",
}                                         "content": "Hello"}
                                       ]
                                     }
```

### Response (OpenAI SSE → Anthropic SSE)

Each OpenAI chunk like `{"choices":[{"delta":{"content":"Hello"}}]}` becomes:

```
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
```

## Health Checking

Each `ModelServer` GenServer polls its upstream MLX-LM server's `GET /v1/models` endpoint every 5 seconds. Status transitions:

- **`:down` → `:up`**: Upstream responds with HTTP 200
- **`:up` → `:down`**: Upstream fails to respond (connection refused, timeout, non-200)

Status transitions are logged. The `/health` endpoint exposes per-model status as JSON.

Models are managed externally -- the user starts/stops MLX-LM servers independently. Mixtape detects availability automatically.

## Error Responses

| Scenario | Status | Format |
|---|---|---|
| Unknown model name | 400 | `{"type":"error","error":{"type":"invalid_request_error","message":"Unknown model: X"}}` |
| Model not running | 503 | `{"type":"error","error":{"type":"overloaded_error","message":"Model 'X' is not available..."}}` |
| Upstream connection failure | 200 (SSE) | Error text emitted as a `content_block_delta` in the stream |
| Unknown route | 404 | `not found` |

## Dependencies

| Package | Purpose |
|---|---|
| Bandit | HTTP server (replaces Cowboy) |
| Plug | HTTP routing and request handling |
| Jason | JSON encoding/decoding |
| Req | HTTP client for upstream requests with streaming support |
| Bypass | Test-only mock HTTP server |
