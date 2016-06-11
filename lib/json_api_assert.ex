defmodule JsonApiAssert do
  import ExUnit.Assertions, only: [assert: 2, refute: 2]

  @moduledoc """
  JsonApiAssert is a collection of composable test helpers to ease
  the pain of testing [JSON API](http://jsonapi.org) payloads.

  You can use the functions individually but they are optimally used in a composable
  fashion with the pipe operator:

      payload
      |> assert_data(user1)
      |> assert_data(user2)
      |> refute_data(user3)
      |> assert_relationship(pet1, as: "pets", for: user1)
      |> assert_relationship(pet2, as: "pets", for: user2)
      |> assert_included(pet1)
      |> assert_included(pet2)

  If you've tested JSON API payloads before the benefits of this pattern should
  be obvious. Hundreds of lines of codes can be reduced to just a handful. Brittle tests are
  now flexible and don't care about inseration / render order.
  """

  @doc """
  Asserts that the "jsonapi" object exists in the payload

      payload
      |> assert_jsonapi(version: "1.0")

  The members argument should be a key/value pair of members you expect to be be in
  the "jsonapi" object of the payload.
  """
  @spec assert_jsonapi(map, list) :: map
  def assert_jsonapi(payload, members \\ [])

  def assert_jsonapi(%{"jsonapi" => jsonapi} = payload, members) do
    Enum.reduce(members, [], fn({key, value}, unmatched) ->
      actual_value = jsonapi[Atom.to_string(key)]
      if actual_value != value do
        unmatched = unmatched ++ ["Expected:\n  `#{key}` \"#{value}\"\nGot:\n  `#{key}` \"#{actual_value}\""]
      end

      unmatched
    end)
    |> case do
      [] -> payload
      unmatched ->
        raise ExUnit.AssertionError, "jsonapi object mismatch\n#{Enum.join(unmatched, ", ")}"
    end
  end

  def assert_jsonapi(_payload, _members),
    do: raise ExUnit.AssertionError, "jsonapi object not found"

  @doc """
  Asserts that a given record is included in the `data` object of the payload.

      payload
      |> assert_data(user1)
  """
  @spec assert_data(map, map | struct) :: map
  def assert_data(payload, record) do
    assert_record(payload["data"], record)

    payload
  end

  @doc """
  Refutes that a given record is included in the `data` object of the payload.

      payload
      |> refute_data(user1)
  """
  @spec refute_data(map, map | struct) :: map
  def refute_data(payload, record) do
    refute_record(payload["data"], record)

    payload
  end

  @doc """
  Asserts that a given record is included in the `included` object of the payload.

      payload
      |> assert_included(pet1)
  """
  @spec assert_included(map, map | struct) :: map
  def assert_included(payload, record) do
    assert_record(payload["included"], record)

    payload
  end


  @doc """
  Refutes that a given record is included in the `included` object of the payload.

      payload
      |> refute_included(pet1)
  """
  @spec refute_included(map, map | struct) :: map
  def refute_included(payload, record) do
    refute_record(payload["included"], record)

    payload
  end

  @doc """
  Asserts that the proper relationship meta data exists between a parent and child record

      payload
      |> assert_relationship(pet1, as: "pets", for: owner1)

  The `as:` atom must be passed the name of the relationship. It will not be derived from the child.
  """
  @spec assert_relationship(map, map, [as: binary, for: binary]) :: map
  def assert_relationship(payload, child_record, [as: as, for: parent_record]) do
    parent_record =
      merge_data([], payload["data"])
      |> merge_data(payload["included"])
      |> assert_record(parent_record)

    relationships = parent_record["relationships"]

    if !relationships do
      raise ExUnit.AssertionError, "could not find any relationships for record matching `id` #{parent_record["id"]} and `type` \"#{parent_record["type"]}\""
    end

    relationship = relationships[as]

    if !relationship do
      raise ExUnit.AssertionError, "could not find the relationship `#{as}` for record matching `id` #{parent_record["id"]} and `type` \"#{parent_record["type"]}\""
    end

    relationship =
      get_in(parent_record, ["relationships", as, "data"])
      |> List.wrap()
      |> Enum.find(&(meta_data_compare(&1, child_record)))

    assert relationship, "could not find relationship `#{as}` with `id` #{child_record["id"]} and `type` \"#{child_record["type"]}\" for record matching `id` #{parent_record["id"]} and `type` \"#{parent_record["type"]}\""
  end
  def assert_relationship(_, _, [for: _]),
    do: raise ExUnit.AssertionError, "you must pass `as:` with the name of the relationship"
  def assert_relationship(_, _, [as: _]),
    do: raise ExUnit.AssertionError, "you must pass `for:` with the parent record"

  @doc """
  Refutes a relationship between two records

      payload
      |> refute_relationship(pet1, as: "pets", for: owner1)

  The `as:` atom must be passed the name of the relationship. It will not be derived from the child.
  """
  @spec refute_relationship(map, map, [as: binary, for: binary]) :: map
  def refute_relationship(payload, child_record, [as: as, for: parent_record]) do
    merge_data([], payload["data"])
    |> merge_data(payload["included"])
    |> assert_record(parent_record)
    |> get_in(["relationships", as, "data"])
    |> List.wrap()
    |> Enum.find(&(meta_data_compare(&1, child_record)))
    |> refute("was not expecting to find the relationship `#{as}` with `id` #{child_record["id"]} and `type` \"#{child_record["type"]}\" for record matching `id` #{parent_record["id"]} and `type` \"#{parent_record["type"]}\"")
  end
  def refute_relationship(_, _, [for: _]),
    do: raise ExUnit.AssertionError, "you must pass `as:` with the name of the relationship"
  def refute_relationship(_, _, [as: _]),
    do: raise ExUnit.AssertionError, "you must pass `for:` with the parent record"

  defp assert_record(data, record) do
    find_record(data, record)
    |> case do
      nil ->
        assert nil, "could not find a record with matching `id` #{record["id"]} and `type` \"#{record["type"]}\""
      %{"attributes" => attributes} = found_record ->
        Enum.reduce(attributes, [], fn({key, value}, attrs) ->
          if value != record["attributes"][key] do
            attrs ++ [key]
          else
            attrs
          end
        end)
        |> case do
          [] -> found_record
          keys ->
            opts = [
            left: Enum.into(keys, %{}, fn(key) -> {key, attributes[key]} end),
              right: Enum.into(keys, %{}, fn(key) -> {key, record["attributes"][key]} end),
              message: "record with `id` #{record["id"]} and `type` \"#{record["type"]}\" was found but had mis-matching attributes"
            ]
            raise(ExUnit.AssertionError, opts)
        end
    end
  end

  defp refute_record(data, record) do
    find_record(data, record)
    |> case do
      %{"attributes" => attributes} ->
        matching =
          attributes
          |> Enum.reduce([], fn({key, value}, attrs) ->
            if value == record["attributes"][key] do
              attrs ++ [{key, value}]
            else
              attrs
            end
          end)

        refute Map.keys(attributes) |> length() == length(matching), "did not expect #{inspect Map.delete(record, "attributes")} to be found."

      nil -> nil
    end
  end

  defp find_record(data, record) do
    data
    |> List.wrap
    |> Enum.find(&(meta_data_compare(&1, record)))
  end

  defp meta_data_compare(record_1, record_2) do
    record_1["id"] == record_2["id"] && record_1["type"] == record_2["type"]
  end

  defp merge_data(payload, nil),
    do: merge_data(payload, %{})
  defp merge_data(payload, data) when is_list(data),
    do: payload ++ data
  defp merge_data(payload, data) when is_map(data),
    do: merge_data(payload, [data])
end