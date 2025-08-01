defmodule Kdef.ConfigTest do
  use ExUnit.Case
  doctest Kdef.Config

  alias Kdef.Config
  alias Kdef.Config.Entry
  alias Kdef.Config.Operations

  describe "Config struct" do
    test "creates new empty config" do
      config = Config.new()
      assert config.entries == []
      assert config.metadata == %{}
    end

    test "creates new config with metadata" do
      metadata = %{source: "test.config"}
      config = Config.new(metadata: metadata)
      assert config.metadata == metadata
    end
  end

  describe "Entry creation" do
    test "creates boolean entry" do
      entry = Entry.bool("DEBUG", true)
      assert entry.key == "DEBUG"
      assert entry.value == true
      assert entry.type == :bool
    end

    test "creates tristate entry" do
      entry = Entry.tristate("MODULE_SUPPORT", :module)
      assert entry.key == "MODULE_SUPPORT"
      assert entry.value == :module
      assert entry.type == :tristate
    end

    test "creates string entry" do
      entry = Entry.string("VERSION", "5.4.0")
      assert entry.key == "VERSION"
      assert entry.value == "5.4.0"
      assert entry.type == :string
    end

    test "creates integer entry" do
      entry = Entry.int("MAX_THREADS", 32)
      assert entry.key == "MAX_THREADS"
      assert entry.value == 32
      assert entry.type == :int
    end

    test "creates hex entry" do
      entry = Entry.hex("BASE_ADDR", 0x1000)
      assert entry.key == "BASE_ADDR"
      assert entry.value == 0x1000
      assert entry.type == :hex
    end

    test "creates comment entry" do
      entry = Entry.comment("This is a comment")
      assert entry.key == nil
      assert entry.comment == "This is a comment"
      assert entry.type == :comment
    end

    test "creates blank entry" do
      entry = Entry.blank()
      assert entry.key == nil
      assert entry.type == :blank
    end
  end

  describe "Entry string conversion" do
    test "converts boolean true to string" do
      entry = Entry.bool("DEBUG", true)
      assert Entry.to_string(entry) == "CONFIG_DEBUG=y"
    end

    test "converts boolean false to string" do
      entry = Entry.bool("DEBUG", false)
      assert Entry.to_string(entry) == "# CONFIG_DEBUG is not set"
    end

    test "converts tristate module to string" do
      entry = Entry.tristate("MODULE_SUPPORT", :module)
      assert Entry.to_string(entry) == "CONFIG_MODULE_SUPPORT=m"
    end

    test "converts string entry to string" do
      entry = Entry.string("VERSION", "5.4.0")
      assert Entry.to_string(entry) == "CONFIG_VERSION=\"5.4.0\""
    end

    test "converts integer entry to string" do
      entry = Entry.int("MAX_THREADS", 32)
      assert Entry.to_string(entry) == "CONFIG_MAX_THREADS=32"
    end

    test "converts hex entry to string" do
      entry = Entry.hex("BASE_ADDR", 0x1000)
      assert Entry.to_string(entry) == "CONFIG_BASE_ADDR=0x1000"
    end

    test "converts comment to string" do
      entry = Entry.comment("This is a comment")
      assert Entry.to_string(entry) == "# This is a comment"
    end

    test "converts blank to string" do
      entry = Entry.blank()
      assert Entry.to_string(entry) == ""
    end
  end

  describe "Config operations" do
    test "adds entry to config" do
      config = Config.new()
      entry = Entry.bool("DEBUG", true)

      updated_config = Config.add_entry(config, entry)
      assert length(updated_config.entries) == 1
      assert hd(updated_config.entries) == entry
    end

    test "gets entry by key" do
      config = Config.new()
      entry = Entry.bool("DEBUG", true)
      config = Config.add_entry(config, entry)

      found_entry = Config.get_entry(config, "DEBUG")
      assert found_entry == entry
    end

    test "gets nil for non-existent key" do
      config = Config.new()
      assert Config.get_entry(config, "NONEXISTENT") == nil
    end

    test "removes entry by key" do
      config = Config.new()
      entry = Entry.bool("DEBUG", true)
      config = Config.add_entry(config, entry)

      updated_config = Config.remove_entry(config, "DEBUG")
      assert updated_config.entries == []
    end

    test "sets entry replacing existing" do
      config = Config.new()
      entry1 = Entry.bool("DEBUG", true)
      entry2 = Entry.bool("DEBUG", false)

      config = Config.add_entry(config, entry1)
      config = Config.set_entry(config, entry2)

      assert length(config.entries) == 1
      assert hd(config.entries).value == false
    end

    test "lists all keys" do
      config =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.comment("A comment"))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))

      keys = Config.keys(config)
      assert keys == ["DEBUG", "VERSION"]
    end
  end

  describe "merge operations" do
    test "merges two configs with non-overlapping keys" do
      base =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))

      override =
        Config.new()
        |> Config.add_entry(Entry.bool("VERBOSE", true))
        |> Config.add_entry(Entry.int("THREADS", 4))

      merged = Operations.merge(base, override)

      assert length(merged.entries) == 4
      assert Config.get_entry(merged, "DEBUG").value == true
      assert Config.get_entry(merged, "VERBOSE").value == true
    end

    test "merges with override taking precedence" do
      base =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))

      override =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", false))
        |> Config.add_entry(Entry.string("ARCH", "x86_64"))

      merged = Operations.merge(base, override)

      assert Config.get_entry(merged, "DEBUG").value == false
      assert Config.get_entry(merged, "VERSION").value == "1.0"
      assert Config.get_entry(merged, "ARCH").value == "x86_64"
    end

    test "preserves order during merge" do
      base =
        Config.new()
        |> Config.add_entry(Entry.bool("A", true))
        |> Config.add_entry(Entry.bool("B", true))
        |> Config.add_entry(Entry.bool("C", true))

      override =
        Config.new()
        |> Config.add_entry(Entry.bool("B", false))
        |> Config.add_entry(Entry.bool("D", true))

      merged = Operations.merge(base, override)
      keys = Config.keys(merged)

      assert keys == ["A", "B", "C", "D"]
    end

    test "preserves comments during merge" do
      base =
        Config.new()
        |> Config.add_entry(Entry.comment("Base config"))
        |> Config.add_entry(Entry.bool("DEBUG", true))

      override =
        Config.new()
        |> Config.add_entry(Entry.comment("Override config"))
        |> Config.add_entry(Entry.bool("VERBOSE", true))

      merged = Operations.merge(base, override)

      assert length(merged.entries) == 4
      # Check that both comments are preserved
      comments = Enum.filter(merged.entries, &(&1.type == :comment))
      assert length(comments) == 2
    end
  end

  describe "diff operations" do
    test "diffs two identical configs" do
      config1 =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))

      config2 =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))

      diff = Operations.diff(config1, config2)

      assert diff.added == []
      assert diff.removed == []
      assert diff.changed == []
      assert diff.unchanged_count == 2
    end

    test "diffs configs with added entries" do
      base =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))

      target =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))

      diff = Operations.diff(base, target)

      assert length(diff.added) == 1
      assert hd(diff.added).key == "VERSION"
      assert diff.removed == []
      assert diff.changed == []
      assert diff.unchanged_count == 1
    end

    test "diffs configs with removed entries" do
      base =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))

      target =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))

      diff = Operations.diff(base, target)

      assert diff.added == []
      assert length(diff.removed) == 1
      assert hd(diff.removed).key == "VERSION"
      assert diff.changed == []
      assert diff.unchanged_count == 1
    end

    test "diffs configs with changed entries" do
      base =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))

      target =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", false))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))

      diff = Operations.diff(base, target)

      assert diff.added == []
      assert diff.removed == []
      assert length(diff.changed) == 1

      {old_entry, new_entry} = hd(diff.changed)
      assert old_entry.value == true
      assert new_entry.value == false
      assert diff.unchanged_count == 1
    end
  end

  describe "override operations" do
    test "overrides existing entries" do
      base =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))
        |> Config.add_entry(Entry.int("THREADS", 2))

      override =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", false))
        |> Config.add_entry(Entry.int("THREADS", 8))

      result = Operations.override(base, override)

      assert Config.get_entry(result, "DEBUG").value == false
      # unchanged
      assert Config.get_entry(result, "VERSION").value == "1.0"
      assert Config.get_entry(result, "THREADS").value == 8
    end

    test "maintains order during override" do
      base =
        Config.new()
        |> Config.add_entry(Entry.bool("A", true))
        |> Config.add_entry(Entry.bool("B", true))
        |> Config.add_entry(Entry.bool("C", true))

      override =
        Config.new()
        |> Config.add_entry(Entry.bool("B", false))

      result = Operations.override(base, override)
      keys = Config.keys(result)

      assert keys == ["A", "B", "C"]
      assert length(result.entries) == 3
    end

    test "does not add new entries during override" do
      base =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))

      override =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", false))
        |> Config.add_entry(Entry.string("NEW_OPTION", "value"))

      result = Operations.override(base, override)

      assert length(result.entries) == 1
      assert Config.get_entry(result, "DEBUG").value == false
      assert Config.get_entry(result, "NEW_OPTION") == nil
    end
  end

  describe "filtering operations" do
    test "filters entries by predicate" do
      config =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.comment("A comment"))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))
        |> Config.add_entry(Entry.blank())

      config_only = Operations.config_only(config)

      assert length(config_only.entries) == 2
      assert Enum.all?(config_only.entries, &(&1.type not in [:comment, :blank]))
    end

    test "groups entries by source" do
      config =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true, source: "base.config"))
        |> Config.add_entry(Entry.bool("VERBOSE", true, source: "override.config"))
        |> Config.add_entry(Entry.string("VERSION", "1.0", source: "base.config"))

      grouped = Operations.group_by_source(config)

      assert Map.has_key?(grouped, "base.config")
      assert Map.has_key?(grouped, "override.config")
      assert length(grouped["base.config"]) == 2
      assert length(grouped["override.config"]) == 1
    end
  end

  describe "entry comparison" do
    test "identifies same key entries" do
      entry1 = Entry.bool("DEBUG", true)
      entry2 = Entry.bool("DEBUG", false)
      entry3 = Entry.bool("VERBOSE", true)

      assert Entry.same_key?(entry1, entry2) == true
      assert Entry.same_key?(entry1, entry3) == false
    end

    test "identifies conflicting entries" do
      entry1 = Entry.bool("DEBUG", true)
      entry2 = Entry.bool("DEBUG", false)
      entry3 = Entry.bool("DEBUG", true)
      entry4 = Entry.bool("VERBOSE", false)

      assert Entry.conflicts?(entry1, entry2) == true
      assert Entry.conflicts?(entry1, entry3) == false
      assert Entry.conflicts?(entry1, entry4) == false
    end
  end

  describe "config string conversion" do
    test "converts config to string" do
      config =
        Config.new()
        |> Config.add_entry(Entry.comment("Test configuration"))
        |> Config.add_entry(Entry.blank())
        |> Config.add_entry(Entry.bool("DEBUG", true))
        |> Config.add_entry(Entry.bool("VERBOSE", false))
        |> Config.add_entry(Entry.string("VERSION", "1.0"))
        |> Config.add_entry(Entry.blank())

      expected = """
      # Test configuration

      CONFIG_DEBUG=y
      # CONFIG_VERBOSE is not set
      CONFIG_VERSION="1.0"
      """

      assert to_string(config) == expected
    end
  end

  describe "entry validation" do
    test "validates entry with metadata" do
      entry =
        Entry.bool("DEBUG", true,
          line_number: 10,
          source: "test.config",
          comment: "inline comment",
          metadata: %{priority: :high}
        )

      assert entry.line_number == 10
      assert entry.source == "test.config"
      assert entry.comment == "inline comment"
      assert entry.metadata.priority == :high
    end

    test "maintains entry ordering" do
      config =
        Config.new()
        |> Config.add_entry(Entry.bool("Z_OPTION", true))
        |> Config.add_entry(Entry.bool("A_OPTION", true))
        |> Config.add_entry(Entry.bool("M_OPTION", true))

      keys = Config.keys(config)
      assert keys == ["Z_OPTION", "A_OPTION", "M_OPTION"]
    end
  end

  describe "complex scenarios" do
    test "handles multiple entries with same key" do
      config =
        Config.new()
        |> Config.add_entry(Entry.bool("DEBUG", true, source: "base.config"))
        |> Config.add_entry(Entry.bool("DEBUG", false, source: "override.config"))

      entries = Config.get_entries(config, "DEBUG")
      assert length(entries) == 2
      assert Enum.map(entries, & &1.value) == [true, false]
    end

    test "preserves metadata through operations" do
      base_metadata = %{source: "base.config", priority: 1}
      override_metadata = %{source: "override.config", priority: 2}

      base =
        Config.new(metadata: base_metadata)
        |> Config.add_entry(Entry.bool("DEBUG", true))

      override =
        Config.new(metadata: override_metadata)
        |> Config.add_entry(Entry.bool("VERBOSE", true))

      merged = Operations.merge(base, override)

      assert merged.metadata.source == "override.config"
      assert merged.metadata.priority == 2
    end

    test "handles tristate values correctly" do
      config =
        Config.new()
        |> Config.add_entry(Entry.tristate("MODULE_A", true))
        |> Config.add_entry(Entry.tristate("MODULE_B", false))
        |> Config.add_entry(Entry.tristate("MODULE_C", :module))

      assert Entry.to_string(Config.get_entry(config, "MODULE_A")) == "CONFIG_MODULE_A=y"

      assert Entry.to_string(Config.get_entry(config, "MODULE_B")) ==
               "# CONFIG_MODULE_B is not set"

      assert Entry.to_string(Config.get_entry(config, "MODULE_C")) == "CONFIG_MODULE_C=m"
    end

    test "handles hex values with different formats" do
      config =
        Config.new()
        |> Config.add_entry(Entry.hex("ADDR_1", 0x1000))
        |> Config.add_entry(Entry.hex("ADDR_2", 0xFFFF))
        |> Config.add_entry(Entry.hex("ADDR_3", 0x0))

      assert Entry.to_string(Config.get_entry(config, "ADDR_1")) == "CONFIG_ADDR_1=0x1000"
      assert Entry.to_string(Config.get_entry(config, "ADDR_2")) == "CONFIG_ADDR_2=0xFFFF"
      assert Entry.to_string(Config.get_entry(config, "ADDR_3")) == "CONFIG_ADDR_3=0x0"
    end
  end
end
