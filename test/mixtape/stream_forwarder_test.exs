defmodule Mixtape.StreamForwarderTest do
  use ExUnit.Case, async: true

  alias Mixtape.StreamForwarder

  describe "parse_sse_event/1" do
    test "parses a complete SSE data line" do
      event = ~s(data: {"choices":[{"delta":{"content":"hi"}}]})
      result = StreamForwarder.parse_sse_event(event)
      assert result == %{"choices" => [%{"delta" => %{"content" => "hi"}}]}
    end

    test "returns :done for [DONE] sentinel" do
      assert StreamForwarder.parse_sse_event("data: [DONE]") == :done
    end

    test "skips event: prefix lines and parses data: line" do
      event = "event: message\ndata: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}"
      result = StreamForwarder.parse_sse_event(event)
      assert result == %{"choices" => [%{"delta" => %{"content" => "hi"}}]}
    end

    test "returns :skip for empty or whitespace-only data" do
      assert StreamForwarder.parse_sse_event("") == :skip
      assert StreamForwarder.parse_sse_event("   ") == :skip
    end
  end

  describe "extract_events/1" do
    test "splits complete events from buffer, returns remainder" do
      buffer =
        ~s(data: {"choices":[{"delta":{"content":"a"}}]}\n\ndata: {"choices":[{"delta":{"content":"b"}}]}\n\n)

      {events, remainder} = StreamForwarder.extract_events(buffer)

      assert length(events) == 2
      assert remainder == ""
    end

    test "carries partial data as remainder" do
      buffer = ~s(data: {"choices":[{"delta":{"content":"a"}}]}\n\ndata: {"ch)
      {events, remainder} = StreamForwarder.extract_events(buffer)

      assert length(events) == 1
      assert remainder == ~s(data: {"ch)
    end

    test "returns empty events for incomplete buffer" do
      buffer = ~s(data: {"partial)
      {events, remainder} = StreamForwarder.extract_events(buffer)

      assert events == []
      assert remainder == ~s(data: {"partial)
    end

    test "handles [DONE] sentinel" do
      buffer = "data: [DONE]\n\n"
      {events, remainder} = StreamForwarder.extract_events(buffer)

      assert events == [:done]
      assert remainder == ""
    end
  end
end
