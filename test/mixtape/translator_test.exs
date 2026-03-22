defmodule Mixtape.TranslatorTest do
  use ExUnit.Case, async: true

  alias Mixtape.Translator

  describe "to_mlx/1" do
    test "converts Anthropic request with system prompt to OpenAI format" do
      req = %{
        "model" => "coder",
        "system" => "You are helpful.",
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "max_tokens" => 1024
      }

      result = Translator.to_mlx(req)

      assert result["model"] == "mlx-model"
      assert result["stream"] == true
      assert result["max_tokens"] == 1024

      assert result["messages"] == [
               %{"role" => "system", "content" => "You are helpful."},
               %{"role" => "user", "content" => "Hello"}
             ]
    end

    test "converts request without system prompt" do
      req = %{
        "model" => "coder",
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "max_tokens" => 512
      }

      result = Translator.to_mlx(req)
      assert result["messages"] == [%{"role" => "user", "content" => "Hello"}]
    end

    test "defaults max_tokens to 2048" do
      req = %{"messages" => [%{"role" => "user", "content" => "Hi"}]}
      result = Translator.to_mlx(req)
      assert result["max_tokens"] == 2048
    end

    test "passes through temperature when present" do
      req = %{
        "messages" => [%{"role" => "user", "content" => "Hi"}],
        "temperature" => 0.7
      }

      result = Translator.to_mlx(req)
      assert result["temperature"] == 0.7
    end

    test "omits temperature when not present" do
      req = %{"messages" => [%{"role" => "user", "content" => "Hi"}]}
      result = Translator.to_mlx(req)
      refute Map.has_key?(result, "temperature")
    end
  end

  describe "from_mlx/1" do
    test "translates content delta chunk" do
      chunk = %{"choices" => [%{"delta" => %{"content" => "Hello"}}]}
      result = Translator.from_mlx(chunk)

      assert result == %{
               type: "content_block_delta",
               index: 0,
               delta: %{type: "text_delta", text: "Hello"}
             }
    end

    test "translates finish_reason stop" do
      chunk = %{"choices" => [%{"finish_reason" => "stop"}]}
      result = Translator.from_mlx(chunk)
      assert result == %{type: "message_delta", delta: %{stop_reason: "end_turn"}}
    end

    test "translates finish_reason length" do
      chunk = %{"choices" => [%{"finish_reason" => "length"}]}
      result = Translator.from_mlx(chunk)
      assert result == %{type: "message_delta", delta: %{stop_reason: "max_tokens"}}
    end

    test "returns nil for unrecognized chunk" do
      assert Translator.from_mlx(%{"something" => "else"}) == nil
    end
  end

  describe "envelope_start/1" do
    test "returns message_start and content_block_start events" do
      [msg_start, block_start] = Translator.envelope_start("coder")

      assert msg_start.type == "message_start"
      assert msg_start.message.type == "message"
      assert msg_start.message.role == "assistant"
      assert msg_start.message.model == "coder"
      assert msg_start.message.content == []
      assert msg_start.message.stop_reason == nil
      assert String.starts_with?(msg_start.message.id, "msg_")

      assert block_start == %{
               type: "content_block_start",
               index: 0,
               content_block: %{type: "text", text: ""}
             }
    end
  end

  describe "envelope_stop/1" do
    test "returns stop events with correct stop reason" do
      [block_stop, msg_delta, msg_stop] = Translator.envelope_stop("end_turn")

      assert block_stop == %{type: "content_block_stop", index: 0}

      assert msg_delta == %{
               type: "message_delta",
               delta: %{stop_reason: "end_turn"},
               usage: %{output_tokens: 0}
             }

      assert msg_stop == %{type: "message_stop"}
    end
  end
end
