# Mixtape

An Elixir/OTP API gateway that makes local MLX-LM models speak Anthropic. Point Claude Code at `localhost:4000` and it'll route to your local Qwen models transparently.

## Usage with Claude Code

```bash
ANTHROPIC_BASE_URL=http://localhost:4000 ANTHROPIC_API_KEY=local claude
```

Send requests with `model: "coder"` or `model: "architect"` to route to the corresponding backend.

For a detailed walkthrough including prerequisites, installation, and troubleshooting, see the [How to Use guide](docs/how-to-use.md).

## Setup

```bash
mix deps.get
iex -S mix
```

On startup, Mixtape spawns both MLX-LM model processes and polls their health endpoints until ready. You'll see log messages when each model comes online.

## API

### `POST /v1/messages`

Accepts Anthropic-schema requests. The `model` field determines routing:

| Model | Backend | Port |
|---|---|---|
| `coder` (default) | Qwen2.5-Coder-32B-Q8 | 8080 |
| `architect` | Qwen2.5-72B-Q6 | 8081 |

Returns a streaming SSE response with full Anthropic envelope events (`message_start`, `content_block_start`, deltas, `message_stop`).

If the requested model is still loading, returns `503` with an Anthropic-schema `overloaded_error`.

### `GET /health`

Returns `200 ok`.

## Architecture

See `docs/architecture.md` for full details.

**Request flow:** Client sends Anthropic request to Router, which routes by model field to the correct upstream MLX port. Translator converts to OpenAI `/v1/chat/completions` format. StreamForwarder proxies the SSE stream, translating each chunk back to Anthropic format.

| Module | Role |
|---|---|
| `Mixtape.Application` | OTP app entry, starts supervisor |
| `Mixtape.ModelServer` | GenServer managing one MLX-LM process, with health polling and readiness tracking |
| `Mixtape.Router` | Plug.Router — HTTP routing and readiness gate |
| `Mixtape.Translator` | Anthropic <-> OpenAI schema conversion, envelope events |
| `Mixtape.StreamForwarder` | SSE streaming pipeline with buffering and chunk translation |

## Testing

```bash
mix test              # Run all tests
mix test test/mixtape/translator_test.exs   # Single file
mix test test/mixtape/translator_test.exs:5 # Specific line
mix format --check-formatted                # Check formatting
```