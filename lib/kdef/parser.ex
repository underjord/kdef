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
    explicit_prefix = Keyword.get(opts, :prefix)

    try do
      lines = String.split(content, "\n")

      # Infer prefix from first config line if not explicitly provided
      prefix = explicit_prefix || infer_prefix(content) || "CONFIG_"

      entries =
        lines
        |> Enum.with_index(1)
        |> Enum.map(fn {line, line_number} ->
          parse_line(line, line_number, source, prefix)
        end)
        |> Enum.reject(&is_nil/1)

      config = %Config{
        entries: entries,
        prefix: prefix,
        metadata: %{
          source: source,
          parsed_at: DateTime.utc_now(),
          line_count: length(lines),
          prefix: prefix
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

  defp parse_line(line, line_number, source, prefix) do
    trimmed = String.trim(line)

    cond do
      # Blank line
      trimmed == "" ->
        Entry.blank(line_number: line_number, source: source)

      # Comment line
      String.starts_with?(trimmed, "#") ->
        parse_comment_line(trimmed, line_number, source, prefix)

      # Config line
      String.starts_with?(trimmed, prefix) ->
        parse_config_line(trimmed, line_number, source, prefix)

      # Unknown line format - treat as comment
      true ->
        Entry.comment(trimmed, line_number: line_number, source: source)
    end
  end

  defp parse_comment_line(line, line_number, source, prefix) do
    # Create regex pattern for disabled config comments with dynamic prefix
    escaped_prefix = Regex.escape(prefix)
    disabled_pattern = ~r/^#\s*#{escaped_prefix}(\w+)\s+is not set\s*$/

    cond do
      # Disabled config: # PREFIX_SOMETHING is not set
      Regex.match?(disabled_pattern, line) ->
        case Regex.run(disabled_pattern, line) do
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

  defp parse_config_line(line, line_number, source, prefix) do
    case parse_config_assignment(line, prefix) do
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

  defp parse_config_assignment(line, prefix) do
    escaped_prefix = Regex.escape(prefix)
    pattern = ~r/^#{escaped_prefix}(\w+)=(.+)$/

    case Regex.run(pattern, String.trim(line)) do
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

  # Infer prefix from the first config line found in the content
  defp infer_prefix(content) when is_binary(content) do
    # Look for the first line that matches config assignment pattern
    # Try to match common prefixes first
    cond do
      Regex.match?(~r/^CONFIG_\w+=.*$/m, content) ->
        "CONFIG_"

      Regex.match?(~r/^BR2_\w+=.*$/m, content) ->
        "BR2_"

      # Generic fallback - look for any CAPS_PREFIX pattern
      true ->
        case Regex.run(~r/^([A-Z]+_)\w+=.*$/m, content) do
          [_, prefix] -> prefix
          _ -> nil
        end
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
    |> Enum.map(&Entry.to_string(&1, config.prefix))
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
  def format_diff(diff_result, prefix \\ "CONFIG_") do
    lines = []

    lines =
      if length(diff_result.added) > 0 do
        added_lines = [
          "Added entries:",
          ""
          | Enum.map(diff_result.added, fn entry ->
              "+ #{Entry.to_string(entry, prefix)}"
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
              "- #{Entry.to_string(entry, prefix)}"
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
                "- #{Entry.to_string(old_entry, prefix)}",
                "+ #{Entry.to_string(new_entry, prefix)}"
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
