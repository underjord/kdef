defmodule Kdef.Builder do
  @moduledoc """
  Builder pattern for constructing Kconfig configurations programmatically.
  """

  alias Kdef.Config
  alias Kdef.Config.Entry

  @doc """
  Creates a new config builder.
  """
  def new(opts \\ []) do
    Config.new(opts)
  end

  @doc """
  Adds a boolean configuration entry.
  """
  def bool(%Config{} = config, key, value, opts \\ []) do
    entry = Entry.bool(key, value, opts)
    Config.add_entry(config, entry)
  end

  @doc """
  Adds a tristate configuration entry.
  """
  def tristate(%Config{} = config, key, value, opts \\ []) do
    entry = Entry.tristate(key, value, opts)
    Config.add_entry(config, entry)
  end

  @doc """
  Adds a string configuration entry.
  """
  def string(%Config{} = config, key, value, opts \\ []) do
    entry = Entry.string(key, value, opts)
    Config.add_entry(config, entry)
  end

  @doc """
  Adds an integer configuration entry.
  """
  def int(%Config{} = config, key, value, opts \\ []) do
    entry = Entry.int(key, value, opts)
    Config.add_entry(config, entry)
  end

  @doc """
  Adds a hexadecimal configuration entry.
  """
  def hex(%Config{} = config, key, value, opts \\ []) do
    entry = Entry.hex(key, value, opts)
    Config.add_entry(config, entry)
  end

  @doc """
  Adds a comment to the configuration.
  """
  def comment(%Config{} = config, text, opts \\ []) do
    entry = Entry.comment(text, opts)
    Config.add_entry(config, entry)
  end

  @doc """
  Adds a blank line to the configuration.
  """
  def blank(%Config{} = config, opts \\ []) do
    entry = Entry.blank(opts)
    Config.add_entry(config, entry)
  end

  @doc """
  Enables a boolean or tristate config option.
  """
  def enable(%Config{} = config, key, opts \\ []) do
    # Default to boolean unless specified
    type = Keyword.get(opts, :type, :bool)

    case type do
      :bool -> bool(config, key, true, opts)
      :tristate -> tristate(config, key, true, opts)
    end
  end

  @doc """
  Disables a boolean or tristate config option.
  """
  def disable(%Config{} = config, key, opts \\ []) do
    # Default to boolean unless specified
    type = Keyword.get(opts, :type, :bool)

    case type do
      :bool -> bool(config, key, false, opts)
      :tristate -> tristate(config, key, false, opts)
    end
  end

  @doc """
  Sets a config option as a module (tristate only).
  """
  def module(%Config{} = config, key, opts \\ []) do
    tristate(config, key, :module, opts)
  end
end
