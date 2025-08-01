defmodule Kdef.Config.Entry do
  @moduledoc """
  Represents a single configuration entry in a Kconfig file.
  """

  defstruct [
    :key,
    :value,
    :type,
    :line_number,
    :source,
    :comment,
    metadata: %{}
  ]

  @type config_type :: :bool | :tristate | :string | :int | :hex
  @type config_value :: boolean() | :module | String.t() | integer()

  @type t :: %__MODULE__{
          key: String.t() | nil,
          value: config_value() | nil,
          type: config_type() | :comment | :blank,
          line_number: non_neg_integer() | nil,
          source: String.t() | nil,
          comment: String.t() | nil,
          metadata: map()
        }

  @doc """
  Creates a new boolean config entry.
  """
  def bool(key, value, opts \\ []) when is_boolean(value) do
    %__MODULE__{
      key: key,
      value: value,
      type: :bool,
      line_number: Keyword.get(opts, :line_number),
      source: Keyword.get(opts, :source),
      comment: Keyword.get(opts, :comment),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a new tristate config entry (y/n/m).
  """
  def tristate(key, value, opts \\ [])
      when value in [true, false, :module] do
    %__MODULE__{
      key: key,
      value: value,
      type: :tristate,
      line_number: Keyword.get(opts, :line_number),
      source: Keyword.get(opts, :source),
      comment: Keyword.get(opts, :comment),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a new string config entry.
  """
  def string(key, value, opts \\ []) when is_binary(value) do
    %__MODULE__{
      key: key,
      value: value,
      type: :string,
      line_number: Keyword.get(opts, :line_number),
      source: Keyword.get(opts, :source),
      comment: Keyword.get(opts, :comment),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a new integer config entry.
  """
  def int(key, value, opts \\ []) when is_integer(value) do
    %__MODULE__{
      key: key,
      value: value,
      type: :int,
      line_number: Keyword.get(opts, :line_number),
      source: Keyword.get(opts, :source),
      comment: Keyword.get(opts, :comment),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a new hexadecimal config entry.
  """
  def hex(key, value, opts \\ []) when is_integer(value) do
    %__MODULE__{
      key: key,
      value: value,
      type: :hex,
      line_number: Keyword.get(opts, :line_number),
      source: Keyword.get(opts, :source),
      comment: Keyword.get(opts, :comment),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a comment entry.
  """
  def comment(text, opts \\ []) do
    %__MODULE__{
      key: nil,
      value: nil,
      type: :comment,
      line_number: Keyword.get(opts, :line_number),
      source: Keyword.get(opts, :source),
      comment: text,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a blank line entry.
  """
  def blank(opts \\ []) do
    %__MODULE__{
      key: nil,
      value: nil,
      type: :blank,
      line_number: Keyword.get(opts, :line_number),
      source: Keyword.get(opts, :source),
      comment: nil,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Converts an entry to its Kconfig string representation using the default CONFIG_ prefix.
  """
  def to_string(%__MODULE__{} = entry) do
    to_string(entry, "CONFIG_")
  end

  @doc """
  Converts an entry to its Kconfig string representation with a custom prefix.
  """
  def to_string(%__MODULE__{type: :comment, comment: comment}, _prefix) do
    "# #{comment}"
  end

  def to_string(%__MODULE__{type: :blank}, _prefix) do
    ""
  end

  def to_string(%__MODULE__{key: key, value: true, type: type}, prefix)
      when type in [:bool, :tristate] do
    "#{prefix}#{key}=y"
  end

  def to_string(%__MODULE__{key: key, value: false, type: type}, prefix)
      when type in [:bool, :tristate] do
    "# #{prefix}#{key} is not set"
  end

  def to_string(%__MODULE__{key: key, value: :module, type: :tristate}, prefix) do
    "#{prefix}#{key}=m"
  end

  def to_string(%__MODULE__{key: key, value: value, type: :string}, prefix) do
    "#{prefix}#{key}=\"#{value}\""
  end

  def to_string(%__MODULE__{key: key, value: value, type: :int}, prefix) do
    "#{prefix}#{key}=#{value}"
  end

  def to_string(%__MODULE__{key: key, value: value, type: :hex}, prefix) do
    "#{prefix}#{key}=0x#{Integer.to_string(value, 16)}"
  end

  @doc """
  Checks if two entries represent the same configuration key.
  """
  def same_key?(%__MODULE__{key: key}, %__MODULE__{key: key})
      when not is_nil(key),
      do: true

  def same_key?(_, _), do: false

  @doc """
  Checks if two entries have conflicting values for the same key.
  """
  def conflicts?(%__MODULE__{} = entry1, %__MODULE__{} = entry2) do
    same_key?(entry1, entry2) and entry1.value != entry2.value
  end
end

defmodule Kdef.Config.Operations do
  @moduledoc """
  Operations for working with Kconfig configurations including
  diffing, merging, and overriding.
  """

  alias Kdef.Config
  alias Kdef.Config.Entry

  @doc """
  Merges two configurations, with the second config taking precedence.

  Maintains the order from the base config, appending new entries from
  the override config at the end.
  """
  def merge(%Config{} = base, %Config{} = override) do
    # Start with base config
    result_entries = base.entries

    # Process each entry in override config
    final_entries =
      Enum.reduce(override.entries, result_entries, fn override_entry, acc ->
        case override_entry.key do
          nil ->
            # Comments and blank lines are always appended
            acc ++ [override_entry]

          key ->
            # Replace existing entry with same key or append if new
            case find_entry_index(acc, key) do
              nil ->
                acc ++ [override_entry]

              index ->
                List.replace_at(acc, index, override_entry)
            end
        end
      end)

    merged_metadata = Map.merge(base.metadata, override.metadata)

    %Config{
      entries: final_entries,
      metadata: merged_metadata
    }
  end

  @doc """
  Creates a diff between two configurations.

  Returns a structure showing what changed between the base and target configs.
  """
  def diff(%Config{} = base, %Config{} = target) do
    base_map = entries_to_map(base.entries)
    target_map = entries_to_map(target.entries)

    added =
      target_map
      |> Map.drop(Map.keys(base_map))
      |> Map.values()

    removed =
      base_map
      |> Map.drop(Map.keys(target_map))
      |> Map.values()

    changed =
      for {key, target_entry} <- target_map,
          base_entry = Map.get(base_map, key),
          base_entry != nil,
          Entry.conflicts?(base_entry, target_entry) do
        {base_entry, target_entry}
      end

    %{
      added: added,
      removed: removed,
      changed: changed,
      unchanged_count: count_unchanged(base_map, target_map)
    }
  end

  @doc """
  Overrides specific entries in a config with values from another config.

  Similar to merge but only updates entries that exist in the override config,
  maintaining the exact order of the base config.
  """
  def override(%Config{} = base, %Config{} = override) do
    override_map = entries_to_map(override.entries)

    updated_entries =
      Enum.map(base.entries, fn entry ->
        case entry.key do
          nil ->
            entry

          key ->
            case Map.get(override_map, key) do
              nil -> entry
              override_entry -> override_entry
            end
        end
      end)

    %Config{
      entries: updated_entries,
      metadata: Map.merge(base.metadata, override.metadata)
    }
  end

  @doc """
  Filters a config to only include entries matching the given predicate.
  """
  def filter(%Config{} = config, predicate_fn) do
    filtered_entries = Enum.filter(config.entries, predicate_fn)
    %Config{config | entries: filtered_entries}
  end

  @doc """
  Extracts only the configuration entries (no comments or blanks).
  """
  def config_only(%Config{} = config) do
    filter(config, fn entry ->
      entry.type not in [:comment, :blank]
    end)
  end

  @doc """
  Groups entries by their source.
  """
  def group_by_source(%Config{} = config) do
    Enum.group_by(config.entries, & &1.source)
  end

  # Private helper functions

  defp entries_to_map(entries) do
    entries
    |> Enum.filter(fn entry -> entry.key != nil end)
    |> Enum.into(%{}, fn entry -> {entry.key, entry} end)
  end

  defp find_entry_index(entries, key) do
    entries
    |> Enum.with_index()
    |> Enum.find_value(fn {entry, index} ->
      if entry.key == key, do: index, else: nil
    end)
  end

  defp count_unchanged(base_map, target_map) do
    common_keys =
      MapSet.intersection(MapSet.new(Map.keys(base_map)), MapSet.new(Map.keys(target_map)))

    Enum.count(common_keys, fn key ->
      Map.get(base_map, key) == Map.get(target_map, key)
    end)
  end
end

defmodule Kdef.Config.Validator do
  @moduledoc """
  Validation functions for Kconfig entries and configurations.
  """

  alias Kdef.Config.Entry

  @doc """
  Validates a configuration entry.
  """
  def validate_entry(%Entry{} = entry) do
    with :ok <- validate_key(entry.key, entry.type),
         :ok <- validate_value(entry.value, entry.type) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates an entire configuration.
  """
  def validate_config(%Kdef.Config{} = config) do
    config.entries
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {entry, index}, :ok ->
      case validate_entry(entry) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {index, reason}}}
      end
    end)
  end

  # Private validation functions

  defp validate_key(nil, type) when type in [:comment, :blank], do: :ok
  defp validate_key(key, _type) when is_binary(key) and byte_size(key) > 0, do: :ok
  defp validate_key(_, _), do: {:error, "Invalid key"}

  defp validate_value(nil, type) when type in [:comment, :blank], do: :ok
  defp validate_value(value, :bool) when is_boolean(value), do: :ok
  defp validate_value(value, :tristate) when value in [true, false, :module], do: :ok
  defp validate_value(value, :string) when is_binary(value), do: :ok
  defp validate_value(value, :int) when is_integer(value), do: :ok
  defp validate_value(value, :hex) when is_integer(value) and value >= 0, do: :ok
  defp validate_value(_, _), do: {:error, "Invalid value for type"}
end

defimpl String.Chars, for: Kdef.Config do
  def to_string(%Kdef.Config{} = config) do
    config.entries
    |> Enum.map(&Kdef.Config.Entry.to_string(&1, config.prefix))
    |> Enum.join("\n")
  end
end

defimpl Inspect, for: Kdef.Config.Entry do
  def inspect(%Kdef.Config.Entry{} = entry, _opts) do
    case entry.type do
      :comment ->
        "#Kdef.Config.Entry<comment: \"#{entry.comment}\">"

      :blank ->
        "#Kdef.Config.Entry<blank>"

      _ ->
        "#Kdef.Config.Entry<#{entry.key}: #{inspect(entry.value)} (#{entry.type})>"
    end
  end
end
