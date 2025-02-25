defmodule ExOauth2Provider.Oidc do
  @moduledoc """
    Functions to add an OIDC layer to this OAuth implementation
  """

  alias ExOauth2Provider.Config
  # alias ExOauth2Provider.Oidc.Token

  def generate_token(resource_owner, %{uid: client_id}, config) do
    resource_owner =
      resource_owner
      |> Jason.encode!()
      |> Jason.decode!()
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    oidc_config = Config.oidc(config)

    audience = Keyword.get(oidc_config, :audience, client_id)
    issuer = Keyword.get(oidc_config, :issuer, "https://retailpay.africa")
    resource_owner_claims = Keyword.get(oidc_config, :resource_owner_claims, [:id])

    signer =
      Joken.Signer.create(
        "HS512",
        "l57+4+ChYKGGX6c7Aiscu1KQaXakALMuQ1i4HG2Qv842VhjkCDStolV/LbL3qGF0"
      )

    joken_config =
      %{}
      |> Joken.Config.add_claim("iss", fn -> issuer end, &(&1 == issuer))
      |> Joken.Config.add_claim("aud", fn -> audience end, &(&1 == audience))

    extra_claims = recursive_take(resource_owner, resource_owner_claims, config)
    Joken.generate_and_sign!(joken_config, extra_claims, signer)
  end

  defp recursive_take(map, fields, config, preload? \\ true) do
    take = fn
      maps, fields when is_list(maps) -> Enum.map(maps, &recursive_take(&1, fields, config))
      map, fields when is_map(map) -> recursive_take(map, fields, config)
    end

    {plain, nested} =
      Enum.reduce(fields, {[], []}, fn field, {plain, nested} ->
        if is_tuple(field), do: {plain, nested ++ [field]}, else: {plain ++ [field], nested}
      end)

    # preload nested fields
    map = (preload? && Config.repo(config).preload(map, Keyword.keys(nested))) || map

    initial_map = Map.take(map, plain)

    Enum.reduce(nested, initial_map, fn {key, fields}, accum ->
      value =
        map
        |> Map.fetch!(key)
        |> take.(fields)

      Map.put(accum, key, value)
    end)
  end
end
