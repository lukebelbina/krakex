defmodule Krakex.Websocket.Client do
  use WebSockex

  alias Krakex.Websocket.{
    BookResponse,
    OhlcResponse,
    SpreadResponse,
    TickerResponse,
    TradeResponse
  }

  @url "wss://ws.kraken.com"

  defmodule State do
    @moduledoc false
    defstruct callbacks: %{}, heartbeats: 0, subscriptions: MapSet.new()
  end

  def start_link(opts \\ []) do
    WebSockex.start_link(@url, __MODULE__, %State{}, opts)
  end

  def handle_connect(_conn, state) do
    IO.puts("connected!")
    {:ok, state}
  end

  def handle_cast({:subscribe, name, pairs, callback, opts}, state) do
    callbacks = for pair <- pairs, cb <- [callback], into: %{}, do: {{name, pair}, cb}
    {:reply, subscription_frame(name, pairs, opts), %{state | callbacks: callbacks}}
  end

  def handle_disconnect(_conn, state) do
    IO.puts("disconnected")
    {:ok, state}
  end

  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, decoded} ->
        handle_msg(decoded, state)

      {:error, %Jason.DecodeError{} = error} ->
        IO.puts("error decoding json: #{msg}, error: #{Jason.DecodeError.message(error)}")
        {:ok, state}
    end
  end

  def handle_msg(%{"event" => "heartbeat"}, state) do
    {:ok, %{state | heartbeats: state.heartbeats + 1}}
  end

  def handle_msg(
        %{
          "event" => "subscriptionStatus",
          "pair" => pair,
          "channelID" => channel_id,
          "subscription" => %{"name" => name}
        },
        state
      ) do
    {:ok, %{state | subscriptions: MapSet.put(state.subscriptions, {channel_id, name, pair})}}
  end

  def handle_msg([_channel_id, payload, "ticker", pair], state) do
    if Map.has_key?(state.callbacks, {"ticker", pair}) do
      response = TickerResponse.from_payload(pair, payload)
      state.callbacks[{"ticker", pair}].(response)
    else
      IO.inspect(state)
    end

    {:ok, state}
  end

  def handle_msg([_channel_id, payload, "ohlc-" <> interval, pair], state) do
    if Map.has_key?(state.callbacks, {"ohlc", pair}) do
      response = OhlcResponse.from_payload(pair, interval, payload)
      state.callbacks[{"ohlc", pair}].(response)
    else
      IO.inspect(state)
    end

    {:ok, state}
  end

  def handle_msg([_channel_id, payload, "trade", pair], state) do
    if Map.has_key?(state.callbacks, {"trade", pair}) do
      response = payload |> Enum.map(&TradeResponse.from_payload(pair, &1))
      state.callbacks[{"trade", pair}].(response)
    else
      IO.inspect(state)
    end

    {:ok, state}
  end

  def handle_msg([_channel_id, payload, "spread", pair], state) do
    if Map.has_key?(state.callbacks, {"spread", pair}) do
      response = SpreadResponse.from_payload(pair, payload)
      state.callbacks[{"spread", pair}].(response)
    else
      IO.inspect(state)
    end

    {:ok, state}
  end

  def handle_msg([_channel_id, payload, "book-" <> depth, pair], state) do
    if Map.has_key?(state.callbacks, {"book", pair}) do
      response = BookResponse.from_payload(pair, depth, payload)
      state.callbacks[{"book", pair}].(response)
    else
      IO.inspect(state)
    end

    {:ok, state}
  end

  def handle_msg(msg, state) do
    IO.inspect(msg, label: "not handled")

    {:ok, state}
  end

  defp subscription_frame(name, pairs, opts) do
    payload = %{
      event: "subscribe",
      pair: pairs,
      subscription: Map.merge(%{name: name}, Map.new(opts))
    }

    {:text, Jason.encode!(payload)}
  end

  # defp prune_nils({k, v}, acc) when is_map(v),
  #   do: Map.put(acc, k, Enum.reduce(v, %{}, &prune_nils/2))

  # defp prune_nils({_, nil}, acc), do: acc
  # defp prune_nils({k, v}, acc), do: Map.put(acc, k, v)
end
