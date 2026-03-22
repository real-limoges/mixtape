defmodule Mixtape.Translator do
  def to_mlx(%{"messages" => messages} = req) do
    system_msg =
      case req["system"] do
        nil -> []
        s -> [%{"role" => "system", "content" => s}]
      end

    result = %{
      "model" => "mlx-model",
      "messages" => system_msg ++ messages,
      "max_tokens" => req["max_tokens"] || 2048,
      "stream" => true
    }

    case req["temperature"] do
      nil -> result
      temp -> Map.put(result, "temperature", temp)
    end
  end

  def from_mlx(%{"choices" => [%{"delta" => %{"content" => text}}]})
      when is_binary(text) do
    %{type: "content_block_delta", index: 0, delta: %{type: "text_delta", text: text}}
  end

  def from_mlx(%{"choices" => [%{"finish_reason" => reason}]})
      when is_binary(reason) do
    %{type: "message_delta", delta: %{stop_reason: translate_stop(reason)}}
  end

  def from_mlx(_), do: nil

  def envelope_start(model) do
    id = "msg_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)

    [
      %{
        type: "message_start",
        message: %{
          id: id,
          type: "message",
          role: "assistant",
          model: model,
          content: [],
          stop_reason: nil,
          usage: %{input_tokens: 0, output_tokens: 0}
        }
      },
      %{
        type: "content_block_start",
        index: 0,
        content_block: %{type: "text", text: ""}
      }
    ]
  end

  def envelope_stop(stop_reason) do
    [
      %{type: "content_block_stop", index: 0},
      %{
        type: "message_delta",
        delta: %{stop_reason: stop_reason},
        usage: %{output_tokens: 0}
      },
      %{type: "message_stop"}
    ]
  end

  defp translate_stop("stop"), do: "end_turn"
  defp translate_stop("length"), do: "max_tokens"
  defp translate_stop(other), do: other
end
