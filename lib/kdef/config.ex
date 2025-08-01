defmodule Kdef.Config do
  @moduledoc """
  Core data structures for representing Kconfig configuration files.

  This module provides structures that can represent all fundamental Kconfig
  data types while supporting diffing, merging, overriding, and maintaining
  source ordering.
  """

  defstruct entries: [], metadata: %{}, prefix: "CONFIG_"

  @type t :: %__MODULE__{
          entries: [Kdef.Config.Entry.t()],
          metadata: map(),
          prefix: String.t()
        }

  @doc """
  Creates a new empty config.
  """
  def new(opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    prefix = Keyword.get(opts, :prefix, "CONFIG_")
    %__MODULE__{entries: [], metadata: metadata, prefix: prefix}
  end

  @doc """
  Adds an entry to the config, maintaining order.
  """
  def add_entry(%__MODULE__{} = config, entry) do
    %{config | entries: config.entries ++ [entry]}
  end

  @doc """
  Gets an entry by key, returning the first match.
  """
  def get_entry(%__MODULE__{} = config, key) do
    Enum.find(config.entries, fn entry ->
      case entry do
        %Kdef.Config.Entry{key: ^key} -> true
        _ -> false
      end
    end)
  end

  @doc """
  Gets all entries with the given key.
  """
  def get_entries(%__MODULE__{} = config, key) do
    Enum.filter(config.entries, fn entry ->
      case entry do
        %Kdef.Config.Entry{key: ^key} -> true
        _ -> false
      end
    end)
  end

  @doc """
  Removes all entries with the given key.
  """
  def remove_entry(%__MODULE__{} = config, key) do
    entries =
      Enum.reject(config.entries, fn entry ->
        case entry do
          %Kdef.Config.Entry{key: ^key} -> true
          _ -> false
        end
      end)

    %{config | entries: entries}
  end

  @doc """
  Sets an entry, replacing any existing entries with the same key.
  """
  def set_entry(%__MODULE__{} = config, entry) do
    config
    |> remove_entry(entry.key)
    |> add_entry(entry)
  end

  @doc """
  Lists all config keys in order.
  """
  def keys(%__MODULE__{} = config) do
    config.entries
    |> Enum.map(fn
      %Kdef.Config.Entry{key: key} -> key
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
end
