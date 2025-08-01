defmodule Kdef.Parser do
  @moduledoc """
  Parser for Kconfig configuration files.

  Converts Kconfig text format into the structured data format defined
  in `Kdef.Config` while preserving ordering, comments, and metadata.
  """

  alias Kdef.Config
  alias Kdef.Config.Entry

  @doc """
  Parses a Kconfig string into a Config struct.

  """
  def parse(content, opts \\ []) when is_binary(content) do
    source = Keyword.get(opts, :source, "unknown")

    try do
      entries =
        content
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map(fn {line, line_number} ->
          parse_line(line, line_number, source)
        end)
        |> Enum.reject(&is_nil/1)

      config = %Config{
        entries: entries,
        metadata: %{
          source: source,
          parsed_at: DateTime.utc_now(),
          line_count: length(String.split(content, "\n"))
        }
      }

      {:ok, config}
    rescue
      error -> {:error, "Parse error: #{Exception.message(error)}"}
    end
  end

  @doc """
  Parses a Kconfig file from the filesystem.
  """
  def parse_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, content} ->
        source = Keyword.get(opts, :source, path)
        parse(content, Keyword.put(opts, :source, source))

      {:error, reason} ->
        {:error, "Failed to read file #{path}: #{reason}"}
    end
  end

  # Private parsing functions

  defp parse_line(line, line_number, source) do
    trimmed = String.trim(line)

    cond do
      # Blank line
      trimmed == "" ->
        Entry.blank(line_number: line_number, source: source)

      # Comment line
      String.starts_with?(trimmed, "#") ->
        parse_comment_line(trimmed, line_number, source)

      # Config line
      String.starts_with?(trimmed, "CONFIG_") ->
        parse_config_line(trimmed, line_number, source)

      # Unknown line format - treat as comment
      true ->
        Entry.comment(trimmed, line_number: line_number, source: source)
    end
  end

  defp parse_comment_line(line, line_number, source) do
    cond do
      # Disabled config: # CONFIG_SOMETHING is not set
      Regex.match?(~r/^#\s*CONFIG_(\w+)\s+is not set\s*$/, line) ->
        case Regex.run(~r/^#\s*CONFIG_(\w+)\s+is not set\s*$/, line) do
          [_, key] ->
            Entry.bool(key, false,
              line_number: line_number,
              source: source,
              metadata: %{disabled_comment: true}
            )

          _ ->
            nil
        end

      # Regular comment
      true ->
        comment_text =
          line
          |> String.trim_leading("#")
          |> String.trim()

        Entry.comment(comment_text, line_number: line_number, source: source)
    end
  end

  defp parse_config_line(line, line_number, source) do
    case parse_config_assignment(line) do
      {:ok, key, value, type} ->
        case type do
          :bool -> Entry.bool(key, value, line_number: line_number, source: source)
          :tristate -> Entry.tristate(key, value, line_number: line_number, source: source)
          :string -> Entry.string(key, value, line_number: line_number, source: source)
          :int -> Entry.int(key, value, line_number: line_number, source: source)
          :hex -> Entry.hex(key, value, line_number: line_number, source: source)
        end

      {:error, _reason} ->
        # If we can't parse as config, treat as comment
        Entry.comment(line, line_number: line_number, source: source)
    end
  end

  defp parse_config_assignment(line) do
    case Regex.run(~r/^CONFIG_(\w+)=(.+)$/, String.trim(line)) do
      [_, key, value_str] ->
        parse_config_value(key, String.trim(value_str))

      _ ->
        {:error, "Invalid config format"}
    end
  end

  defp parse_config_value(key, value_str) do
    cond do
      # Boolean/Tristate: y, n, m
      value_str in ["y", "Y"] ->
        {:ok, key, true, :bool}

      value_str in ["n", "N"] ->
        {:ok, key, false, :bool}

      value_str in ["m", "M"] ->
        {:ok, key, :module, :tristate}

      # Quoted string
      Regex.match?(~r/^".*"$/, value_str) ->
        string_value =
          value_str
          |> String.trim_leading("\"")
          |> String.trim_trailing("\"")

        {:ok, key, string_value, :string}

      # Hexadecimal
      Regex.match?(~r/^0[xX][0-9a-fA-F]+$/, value_str) ->
        case parse_hex(value_str) do
          {:ok, int_value} -> {:ok, key, int_value, :hex}
          {:error, _} -> {:error, "Invalid hex value"}
        end

      # Integer
      Regex.match?(~r/^-?\d+$/, value_str) ->
        case Integer.parse(value_str) do
          {int_value, ""} -> {:ok, key, int_value, :int}
          _ -> {:error, "Invalid integer value"}
        end

      # Default to string if nothing else matches
      true ->
        {:ok, key, value_str, :string}
    end
  end

  defp parse_hex("0x" <> hex_str), do: parse_hex_digits(hex_str)
  defp parse_hex("0X" <> hex_str), do: parse_hex_digits(hex_str)
  defp parse_hex(_), do: {:error, "Invalid hex format"}

  defp parse_hex_digits(hex_str) do
    case Integer.parse(hex_str, 16) do
      {value, ""} -> {:ok, value}
      _ -> {:error, "Invalid hex digits"}
    end
  end
end

defmodule Kdef.Formatter do
  @moduledoc """
  Formats Kconfig data structures back to text format.
  """

  alias Kdef.Config
  alias Kdef.Config.Entry

  @doc """
  Formats a Config struct back to Kconfig text format.

  ## Options

  - `:preserve_comments` - Include comments and blank lines (default: true)
  - `:sort_entries` - Sort config entries alphabetically (default: false)
  - `:indent` - Indentation string for nested structures (default: "")

  """
  def format(%Config{} = config, opts \\ []) do
    preserve_comments = Keyword.get(opts, :preserve_comments, true)
    sort_entries = Keyword.get(opts, :sort_entries, false)

    entries =
      if sort_entries do
        sort_config_entries(config.entries, preserve_comments)
      else
        config.entries
      end

    entries
    |> maybe_filter_comments(preserve_comments)
    |> Enum.map(&Entry.to_string/1)
    |> Enum.join("\n")
  end

  @doc """
  Formats a Config struct as a minimal configuration (config only, no comments).
  """
  def format_minimal(%Config{} = config) do
    format(config, preserve_comments: false, sort_entries: true)
  end

  @doc """
  Formats a diff result in a human-readable format.
  """
  def format_diff(diff_result) do
    lines = []

    lines =
      if length(diff_result.added) > 0 do
        added_lines = [
          "Added entries:",
          ""
          | Enum.map(diff_result.added, fn entry ->
              "+ #{Entry.to_string(entry)}"
            end)
        ]

        lines ++ added_lines ++ [""]
      else
        lines
      end

    lines =
      if length(diff_result.removed) > 0 do
        removed_lines = [
          "Removed entries:",
          ""
          | Enum.map(diff_result.removed, fn entry ->
              "- #{Entry.to_string(entry)}"
            end)
        ]

        lines ++ removed_lines ++ [""]
      else
        lines
      end

    lines =
      if length(diff_result.changed) > 0 do
        changed_lines = [
          "Changed entries:",
          ""
          | Enum.map(diff_result.changed, fn {old_entry, new_entry} ->
              [
                "- #{Entry.to_string(old_entry)}",
                "+ #{Entry.to_string(new_entry)}"
              ]
            end)
            |> List.flatten()
        ]

        lines ++ changed_lines ++ [""]
      else
        lines
      end

    lines = lines ++ ["Unchanged entries: #{diff_result.unchanged_count}"]

    Enum.join(lines, "\n")
  end

  # Private helper functions

  defp maybe_filter_comments(entries, true), do: entries

  defp maybe_filter_comments(entries, false) do
    Enum.filter(entries, fn entry ->
      entry.type not in [:comment, :blank]
    end)
  end

  defp sort_config_entries(entries, preserve_comments) do
    if preserve_comments do
      # Keep comments and blanks in place, only sort config entries
      entries
    else
      # Sort all config entries, filter out comments
      entries
      |> Enum.filter(fn entry -> entry.type not in [:comment, :blank] end)
      |> Enum.sort_by(fn entry -> entry.key end)
    end
  end
end
