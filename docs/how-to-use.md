# How to Use Mixtape

Mixtape is an Elixir/OTP gateway that lets Claude Code (or any Anthropic-compatible client) talk to local MLX-LM models running on your Mac. Point your client at `localhost:4000` and it handles the rest -- spawning model processes, translating between API schemas, and streaming responses.

## Prerequisites

Before starting, make sure you have:

- **Apple Silicon Mac** -- MLX only runs on Apple Silicon (M1/M2/M3/M4)
- **Elixir 1.19+** -- install via `brew install elixir` or [asdf](https://github.com/asdf-vm/asdf)
- **Python 3** with the `mlx-lm` package:
  ```bash
  pip install mlx-lm
  ```
- **Model weights** downloaded to `~/models/`:
  ```
  ~/models/qwen2.5-coder-32b-q8
  ~/models/qwen2.5-72b-q6
  ```

  You can download these with `mlx-lm`:
  ```bash
  mlx_lm.convert --hf-path Qwen/Qwen2.5-Coder-32B --q-bits 8 -o ~/models/qwen2.5-coder-32b-q8
  mlx_lm.convert --hf-path Qwen/Qwen2.5-72B --q-bits 6 -o ~/models/qwen2.5-72b-q6
  ```

## Installation

```bash
git clone git@github.com:real-limoges/athanor.git mixtape
cd mixtape
mix deps.get
```

## Starting the Server

```bash
iex -S mix
```

On startup, Mixtape does the following:

1. Spawns two MLX-LM model processes (coder on port 8080, architect on port 8081)
2. Starts an HTTP server on port 4000
3. Polls each model's health endpoint every 2 seconds until it responds

You'll see log messages as each model comes online:

```
[info] Model coder is ready on port 8080
[info] Model architect is ready on port 8081
```

Wait for both "ready" messages before sending requests. If you send a request while a model is still loading, you'll get a `503` response.

## Using with Claude Code

This is the primary use case. Set two environment variables and launch Claude Code:

```bash
ANTHROPIC_BASE_URL=http://localhost:4000 ANTHROPIC_API_KEY=local claude
```

That's it. Claude Code will send requests to Mixtape, which translates them to the local model format and streams responses back.

### Model Routing

Mixtape serves two models. The `model` field in the request determines which one handles it:

| Model value | Backend | What it's for |
|---|---|---|
| `coder` (default) | Qwen2.5-Coder-32B-Q8 | Code generation and editing |
| `architect` | Qwen2.5-72B-Q6 | Planning and reasoning |

## Using with opencode

Mixtape also exposes an OpenAI-compatible `/v1/chat/completions` endpoint, so it works with [opencode](https://opencode.ai) and any other OpenAI-compatible client.

Add this to your `opencode.json`:

```json
{
  "provider": {
    "openai-compatible": {
      "baseURL": "http://localhost:4000",
      "apiKey": "local",
      "model": "coder"
    }
  }
}
```

Then launch opencode as usual. Requests go through Mixtape to your local MLX-LM models.

## Using with curl

You can also send requests directly:

```bash
curl -X POST http://localhost:4000/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: local" \
  -d '{
    "model": "coder",
    "max_tokens": 1024,
    "messages": [
      {"role": "user", "content": "Write a fizzbuzz function in Python"}
    ]
  }'
```

The response streams back as Server-Sent Events (SSE) in Anthropic format:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_local","type":"message","role":"assistant","content":[],"model":"coder","stop_reason":null}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"def fizzbuzz"}}

...

event: message_stop
data: {"type":"message_stop"}
```

### With a system prompt

```bash
curl -X POST http://localhost:4000/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: local" \
  -d '{
    "model": "architect",
    "max_tokens": 2048,
    "system": "You are a software architect. Think step by step.",
    "messages": [
      {"role": "user", "content": "Design a caching layer for a REST API"}
    ]
  }'
```

## Health Check

Verify the server is running:

```bash
curl http://localhost:4000/health
# Returns: 200 ok
```

## Stopping the Server

In the `iex` session, press `Ctrl+C` twice, or type:

```elixir
System.stop()
```

This will cleanly shut down both model processes and the HTTP server.

## Troubleshooting

### Models return 503

The model is still loading. Wait for the "ready" log message. Large models like the 72B can take a few minutes to load into memory.

### Model process crashes

Check the logs for error messages. Common causes:

- **Wrong model path** -- verify the model exists at `~/models/<name>`
- **Not enough RAM** -- the 72B model needs significant memory. Close other applications.
- **MLX-LM not installed** -- ensure `mlx_lm.server` is available on your PATH

### Port already in use

If port 4000, 8080, or 8081 is taken:

```bash
# Find what's using the port
lsof -i :4000

# Kill it if needed
kill -9 <PID>
```

To change ports, edit `lib/mixtape/application.ex` and update the port values.

### Claude Code can't connect

- Make sure Mixtape is running and both models are ready
- Verify the env vars are set: `echo $ANTHROPIC_BASE_URL` should show `http://localhost:4000`
- Check that `ANTHROPIC_API_KEY` is set to any non-empty value (e.g., `local`)
