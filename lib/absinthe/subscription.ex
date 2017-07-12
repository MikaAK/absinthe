defmodule Absinthe.Subscription do
  require Logger
  alias __MODULE__

  defdelegate start_link(pubsub), to: Subscription.Supervisor

  @doc "Publish a mutation"
  def publish_mutation(pubsub, %Absinthe.Resolution{} = info, mutation_result) do
    subscribed_fields = get_subscription_fields(info)
    publish_mutation(pubsub, subscribed_fields, mutation_result)
  end
  def publish_mutation(pubsub, subscribed_fields, mutation_result) do
    _ = publish_remote(pubsub, subscribed_fields, mutation_result)
    _ = Subscription.Local.publish_mutation(pubsub, subscribed_fields, mutation_result)
    :ok
  end

  defp get_subscription_fields(resolution_info) do
    resolution_info.definition.schema_node.triggers || []
  end

  def subscribe(pubsub, field_key, doc_id, doc) do
    pubsub
    |> registry_name
    |> Registry.register(field_key, {doc_id, doc})
  end

  def get(pubsub, key) do
    pubsub
    |> registry_name
    |> Registry.lookup(key)
    |> Enum.map(&elem(&1, 1))
    |> Map.new
  end

  @doc false
  def registry_name(pubsub) do
    Module.concat([pubsub, Registry])
  end

  @doc false
  def publish_remote(pubsub, subscribed_fields, mutation_result) do
    {:ok, pool_size} =
      pubsub
      |> registry_name
      |> Registry.meta(:pool_size)

    shard = :erlang.phash2(mutation_result, pool_size)

    proxy_topic = Subscription.Proxy.topic(shard)

    :ok = pubsub.publish_mutation(proxy_topic, subscribed_fields, mutation_result)
  end

  ## Middleware callback
  @doc false
  def call(%{state: :resolved, errors: [], value: value} = res, _) do
    if pubsub = res.context[:pubsub] do
      publish_mutation(pubsub, res, value)
    end
    res
  end
  def call(res, _), do: res

  @doc false
  def add_middleware(middleware) do
    middleware ++ [{__MODULE__, []}]
  end
end