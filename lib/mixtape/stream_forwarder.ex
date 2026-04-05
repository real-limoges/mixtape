defmodule Mixtape.StreamForwarder do
  require Logger
  alias Mixtape.Translator

  def forward(conn, upstream_url, model) do
    body = Translator.to_mlx(conn.body_params)

    conn =
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.send_chunked(200)

    emit_events(conn, Translator.envelope_start(model))

    # Process dictionary is used for SSE buffer and stop reason because Req's
    # `into:` callback only allows returning {req, resp} — no custom accumulator.
    Process.put(:sse_buffer, "")
    Process.put(:last_stop_reason, "end_turn")

    try do
      Req.post!(upstream_url <> "/v1/chat/completions",
        json: body,
        receive_timeout: 300_000,
        connect_options: [timeout: 5_000],
        into: fn {:data, data}, {req, resp} ->
          buffer = Process.get(:sse_buffer, "") <> data
          {events, remainder} = extract_events(buffer)
          Process.put(:sse_buffer, remainder)

          Enum.each(events, fn
            :done ->
              :ok

            parsed ->
              maybe_track_stop_reason(parsed)

              case Translator.from_mlx(parsed) do
                nil -> :ok
                event -> emit_events(conn, [event])
              end
          end)

          {:cont, {req, resp}}
        end
      )
    rescue
      e ->
        Logger.error("Upstream request failed: #{Exception.message(e)}")

        emit_events(conn, [
          %{
            type: "content_block_delta",
            index: 0,
            delta: %{type: "text_delta", text: "\n\n[Upstream error: #{Exception.message(e)}]"}
          }
        ])
    end

    stop_reason = Process.get(:last_stop_reason, "end_turn")
    emit_events(conn, Translator.envelope_stop(stop_reason))

    Process.delete(:sse_buffer)
    Process.delete(:last_stop_reason)

    conn
  end

  def forward_raw(conn, upstream_url, body_params) do
    body =
      body_params
      |> Map.put("model", "mlx-model")
      |> Map.put("stream", true)

    conn =
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.send_chunked(200)

    Process.put(:sse_buffer, "")

    try do
      Req.post!(upstream_url <> "/v1/chat/completions",
        json: body,
        receive_timeout: 300_000,
        connect_options: [timeout: 5_000],
        into: fn {:data, data}, {req, resp} ->
          buffer = Process.get(:sse_buffer, "") <> data
          {events, remainder} = extract_events(buffer)
          Process.put(:sse_buffer, remainder)

          Enum.each(events, fn
            :done ->
              Plug.Conn.chunk(conn, "data: [DONE]\n\n")

            parsed ->
              sse = "data: #{Jason.encode!(parsed)}\n\n"
              Plug.Conn.chunk(conn, sse)
          end)

          {:cont, {req, resp}}
        end
      )
    rescue
      e ->
        Logger.error("Upstream request failed: #{Exception.message(e)}")
    end

    Process.delete(:sse_buffer)

    conn
  end

  @doc """
  Parses a single complete SSE event string into its data payload.
  Returns the decoded JSON map, `:done`, or `:skip`.
  """
  def parse_sse_event(event_str) do
    event_str = String.trim(event_str)

    if event_str == "" do
      :skip
    else
      data_line =
        event_str
        |> String.split("\n")
        |> Enum.find(fn line -> String.starts_with?(line, "data: ") end)

      case data_line do
        nil ->
          :skip

        "data: [DONE]" ->
          :done

        "data: " <> json ->
          case Jason.decode(json) do
            {:ok, parsed} ->
              parsed

            {:error, _} ->
              Logger.warning("Malformed SSE JSON: #{inspect(json)}")
              :skip
          end
      end
    end
  end

  @doc """
  Splits a binary buffer on `\\n\\n` boundaries.
  Returns `{parsed_events, remainder}` where remainder is the incomplete trailing data.
  """
  def extract_events(buffer) do
    parts = String.split(buffer, "\n\n")
    {complete, [remainder]} = Enum.split(parts, length(parts) - 1)

    events =
      complete
      |> Enum.map(&parse_sse_event/1)
      |> Enum.reject(&(&1 == :skip))

    {events, remainder}
  end

  defp maybe_track_stop_reason(%{"choices" => [%{"finish_reason" => reason}]})
       when is_binary(reason) do
    translated =
      case reason do
        "stop" -> "end_turn"
        "length" -> "max_tokens"
        other -> other
      end

    Process.put(:last_stop_reason, translated)
  end

  defp maybe_track_stop_reason(_), do: :ok

  defp emit_events(conn, events) do
    Enum.each(events, fn event ->
      sse = "event: #{event.type}\ndata: #{Jason.encode!(event)}\n\n"
      Plug.Conn.chunk(conn, sse)
    end)
  end
end
