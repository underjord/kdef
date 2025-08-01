defmodule Kdef.ParserTest do
  use ExUnit.Case
  doctest Kdef.Parser

  alias Kdef.Parser
  alias Kdef.Formatter
  alias Kdef.Builder
  alias Kdef.Config
  alias Kdef.Config.Entry

  describe "parsing basic config lines" do
    test "parses boolean enabled config" do
      {:ok, config} = Parser.parse("CONFIG_DEBUG=y")

      entry = Config.get_entry(config, "DEBUG")
      assert entry.key == "DEBUG"
      assert entry.value == true
      assert entry.type == :bool
    end

    test "parses boolean disabled config" do
      {:ok, config} = Parser.parse("# CONFIG_DEBUG is not set")

      entry = Config.get_entry(config, "DEBUG")
      assert entry.key == "DEBUG"
      assert entry.value == false
      assert entry.type == :bool
    end

    test "parses tristate module config" do
      {:ok, config} = Parser.parse("CONFIG_MODULE_SUPPORT=m")

      entry = Config.get_entry(config, "MODULE_SUPPORT")
      assert entry.key == "MODULE_SUPPORT"
      assert entry.value == :module
      assert entry.type == :tristate
    end

    test "parses string config" do
      {:ok, config} = Parser.parse("CONFIG_VERSION=\"5.4.0-rc1\"")

      entry = Config.get_entry(config, "VERSION")
      assert entry.key == "VERSION"
      assert entry.value == "5.4.0-rc1"
      assert entry.type == :string
    end

    test "parses integer config" do
      {:ok, config} = Parser.parse("CONFIG_MAX_THREADS=32")

      entry = Config.get_entry(config, "MAX_THREADS")
      assert entry.key == "MAX_THREADS"
      assert entry.value == 32
      assert entry.type == :int
    end

    test "parses negative integer config" do
      {:ok, config} = Parser.parse("CONFIG_OFFSET=-128")

      entry = Config.get_entry(config, "OFFSET")
      assert entry.key == "OFFSET"
      assert entry.value == -128
      assert entry.type == :int
    end

    test "parses hexadecimal config" do
      {:ok, config} = Parser.parse("CONFIG_BASE_ADDR=0x1000")

      entry = Config.get_entry(config, "BASE_ADDR")
      assert entry.key == "BASE_ADDR"
      assert entry.value == 0x1000
      assert entry.type == :hex
    end

    test "parses uppercase hex config" do
      {:ok, config} = Parser.parse("CONFIG_MEMORY_SIZE=0XFF00")

      entry = Config.get_entry(config, "MEMORY_SIZE")
      assert entry.key == "MEMORY_SIZE"
      assert entry.value == 0xFF00
      assert entry.type == :hex
    end
  end

  describe "parsing comments and formatting" do
    test "parses regular comments" do
      {:ok, config} = Parser.parse("# This is a configuration comment")

      assert length(config.entries) == 1
      entry = hd(config.entries)
      assert entry.type == :comment
      assert entry.comment == "This is a configuration comment"
    end

    test "parses blank lines" do
      {:ok, config} = Parser.parse("CONFIG_DEBUG=y\n\nCONFIG_VERBOSE=n")

      assert length(config.entries) == 3
      assert Enum.at(config.entries, 1).type == :blank
    end

    test "preserves line numbers" do
      content = """
      # Header comment
      CONFIG_DEBUG=y

      CONFIG_VERBOSE=n
      """

      {:ok, config} = Parser.parse(content)

      assert length(config.entries) == 5
      assert Enum.at(config.entries, 0).line_number == 1
      assert Enum.at(config.entries, 1).line_number == 2
      assert Enum.at(config.entries, 2).line_number == 3
      assert Enum.at(config.entries, 3).line_number == 4
      assert Enum.at(config.entries, 4).line_number == 5
    end

    test "handles complex multiline config" do
      content =
        """
        # Kernel Configuration
        # Generated automatically

        CONFIG_64BIT=y
        CONFIG_X86_64=y
        # CONFIG_X86_32 is not set
        CONFIG_ARCH="x86_64"
        CONFIG_NR_CPUS=256
        CONFIG_PHYSICAL_START=0x1000000

        # Memory management
        CONFIG_MMU=y
        CONFIG_HIGHMEM=n
        """
        |> String.trim()

      {:ok, config} = Parser.parse(content, source: "test.config")

      assert length(config.entries) == 13
      assert config.metadata.source == "test.config"

      # Verify specific entries
      assert Config.get_entry(config, "64BIT").value == true
      assert Config.get_entry(config, "X86_32").value == false
      assert Config.get_entry(config, "ARCH").value == "x86_64"
      assert Config.get_entry(config, "NR_CPUS").value == 256
      assert Config.get_entry(config, "PHYSICAL_START").value == 0x1000000
    end
  end

  describe "formatter" do
    test "formats config back to string" do
      config =
        Builder.new()
        |> Builder.comment("Test configuration")
        |> Builder.blank()
        |> Builder.bool("DEBUG", true)
        |> Builder.bool("VERBOSE", false)
        |> Builder.string("VERSION", "1.0")
        |> Builder.int("THREADS", 4)
        |> Builder.hex("BASE_ADDR", 0x1000)
        |> Builder.blank()

      formatted = Formatter.format(config)

      expected = """
      # Test configuration

      CONFIG_DEBUG=y
      # CONFIG_VERBOSE is not set
      CONFIG_VERSION="1.0"
      CONFIG_THREADS=4
      CONFIG_BASE_ADDR=0x1000
      """

      assert formatted == expected
    end

    test "formats minimal config without comments" do
      config =
        Builder.new()
        |> Builder.comment("This comment will be filtered")
        |> Builder.bool("DEBUG", true)
        |> Builder.blank()
        |> Builder.string("VERSION", "1.0")
        |> Builder.blank()

      formatted = Formatter.format_minimal(config)

      expected =
        """
        CONFIG_DEBUG=y
        CONFIG_VERSION="1.0"
        """
        |> String.trim()

      assert formatted == expected
    end

    test "formats diff output" do
      base =
        Builder.new()
        |> Builder.bool("DEBUG", true)
        |> Builder.string("VERSION", "1.0")

      target =
        Builder.new()
        |> Builder.bool("DEBUG", false)
        |> Builder.string("VERSION", "1.0")
        |> Builder.int("THREADS", 8)

      diff = Kdef.Config.Operations.diff(base, target)
      formatted_diff = Formatter.format_diff(diff)

      assert String.contains?(formatted_diff, "Added entries:")
      assert String.contains?(formatted_diff, "+ CONFIG_THREADS=8")
      assert String.contains?(formatted_diff, "Changed entries:")
      assert String.contains?(formatted_diff, "- CONFIG_DEBUG=y")
      assert String.contains?(formatted_diff, "+ # CONFIG_DEBUG is not set")
      assert String.contains?(formatted_diff, "Unchanged entries: 1")
    end
  end

  describe "builder pattern" do
    test "builds config with fluent interface" do
      config =
        Builder.new(metadata: %{source: "test"})
        |> Builder.comment("Configuration file")
        |> Builder.blank()
        |> Builder.enable("DEBUG")
        |> Builder.disable("VERBOSE", type: :tristate)
        |> Builder.module("USB_SUPPORT")
        |> Builder.string("HOSTNAME", "localhost")
        |> Builder.int("PORT", 8080)
        |> Builder.hex("MEMORY_BASE", 0xC0000000)

      assert length(config.entries) == 8
      assert config.metadata.source == "test"

      # Verify entries
      assert Config.get_entry(config, "DEBUG").value == true
      assert Config.get_entry(config, "VERBOSE").value == false
      assert Config.get_entry(config, "USB_SUPPORT").value == :module
      assert Config.get_entry(config, "HOSTNAME").value == "localhost"
      assert Config.get_entry(config, "PORT").value == 8080
      assert Config.get_entry(config, "MEMORY_BASE").value == 0xC0000000
    end
  end

  describe "round-trip parsing and formatting" do
    test "parses and formats maintaining content" do
      original_content = """
      # Linux Kernel Configuration
      # Architecture: x86_64

      CONFIG_64BIT=y
      # CONFIG_X86_32 is not set
      CONFIG_SMP=y
      CONFIG_NR_CPUS=8
      CONFIG_LOCALVERSION_AUTO=y
      CONFIG_KERNEL_GZIP=y
      CONFIG_PHYSICAL_START=0x1000000
      CONFIG_CMDLINE=""

      # Networking support
      CONFIG_NET=y
      CONFIG_PACKET=m
      # CONFIG_UNIX is not set
      """

      {:ok, config} = Parser.parse(original_content)
      formatted = Formatter.format(config)

      # Parse the formatted output again
      {:ok, reparsed_config} = Parser.parse(formatted)

      # Compare key configuration values
      original_keys = Config.keys(config)
      reparsed_keys = Config.keys(reparsed_config)

      assert original_keys == reparsed_keys

      # Check specific values are preserved
      assert Config.get_entry(config, "64BIT").value ==
               Config.get_entry(reparsed_config, "64BIT").value

      assert Config.get_entry(config, "NR_CPUS").value ==
               Config.get_entry(reparsed_config, "NR_CPUS").value

      assert Config.get_entry(config, "PHYSICAL_START").value ==
               Config.get_entry(reparsed_config, "PHYSICAL_START").value
    end
  end

  describe "error handling" do
    test "handles invalid config lines gracefully" do
      content = """
      CONFIG_VALID=y
      invalid line without equals
      CONFIG_ANOTHER=m
      """

      {:ok, config} = Parser.parse(content)

      # Invalid line should be treated as comment
      assert length(config.entries) == 4

      # Should still parse valid entries
      assert Config.get_entry(config, "VALID").value == true
      assert Config.get_entry(config, "ANOTHER").value == :module
    end

    test "provides meaningful error for file read failures" do
      {:error, message} = Parser.parse_file("/nonexistent/path.config")
      assert String.contains?(message, "Failed to read file")
    end
  end

  describe "validation" do
    test "validates entries" do
      valid_entry = Entry.bool("DEBUG", true)
      assert Kdef.Config.Validator.validate_entry(valid_entry) == :ok

      # Test validation with different types
      assert Kdef.Config.Validator.validate_entry(Entry.tristate("MOD", :module)) == :ok
      assert Kdef.Config.Validator.validate_entry(Entry.string("VER", "1.0")) == :ok
      assert Kdef.Config.Validator.validate_entry(Entry.int("NUM", 42)) == :ok
      assert Kdef.Config.Validator.validate_entry(Entry.hex("ADDR", 0x1000)) == :ok
      assert Kdef.Config.Validator.validate_entry(Entry.comment("text")) == :ok
      assert Kdef.Config.Validator.validate_entry(Entry.blank()) == :ok
    end

    test "validates entire config" do
      config =
        Builder.new()
        |> Builder.bool("DEBUG", true)
        |> Builder.string("VERSION", "1.0")
        |> Builder.comment("Valid config")

      assert Kdef.Config.Validator.validate_config(config) == :ok
    end
  end

  describe "edge cases" do
    test "handles empty config" do
      {:ok, config} = Parser.parse("")
      assert [%Entry{type: :blank}] = config.entries
    end

    test "handles config with only comments" do
      content =
        """
        # Just comments
        # Nothing else
        """
        |> String.trim()

      {:ok, config} = Parser.parse(content)
      assert length(config.entries) == 2
      assert Enum.all?(config.entries, &(&1.type == :comment))
    end

    test "handles config with only blank lines" do
      content = "\n\n\n"

      {:ok, config} = Parser.parse(content)
      assert length(config.entries) == 4
      assert Enum.all?(config.entries, &(&1.type == :blank))
    end

    test "handles strings with special characters" do
      {:ok, config} = Parser.parse("CONFIG_CMDLINE=\"console=ttyS0,115200 root=/dev/sda1\"")

      entry = Config.get_entry(config, "CMDLINE")
      assert entry.value == "console=ttyS0,115200 root=/dev/sda1"
    end

    test "handles zero values correctly" do
      content = """
      CONFIG_ZERO_INT=0
      CONFIG_ZERO_HEX=0x0
      CONFIG_EMPTY_STRING=""
      """

      {:ok, config} = Parser.parse(content)

      assert Config.get_entry(config, "ZERO_INT").value == 0
      assert Config.get_entry(config, "ZERO_HEX").value == 0
      assert Config.get_entry(config, "EMPTY_STRING").value == ""
    end

    test "handles large hex values" do
      {:ok, config} = Parser.parse("CONFIG_LARGE_ADDR=0xFFFFFFFFFFFFFFFF")

      entry = Config.get_entry(config, "LARGE_ADDR")
      assert entry.value == 0xFFFFFFFFFFFFFFFF
      assert entry.type == :hex
    end
  end

  describe "real-world config examples" do
    test "parses typical kernel config fragment" do
      content = """
      #
      # Automatically generated file; DO NOT EDIT.
      # Linux/x86 5.4.0 Kernel Configuration
      #
      CONFIG_CC_VERSION_TEXT="gcc (Ubuntu 9.3.0-17ubuntu1~20.04) 9.3.0"
      CONFIG_CC_IS_GCC=y
      CONFIG_GCC_VERSION=90300
      CONFIG_CLANG_VERSION=0
      CONFIG_CC_CAN_LINK=y
      CONFIG_CC_HAS_ASM_GOTO=y
      CONFIG_IRQ_WORK=y
      CONFIG_BUILDTIME_EXTABLE_SORT=y

      #
      # General setup
      #
      CONFIG_BROKEN_ON_SMP=y
      CONFIG_INIT_ENV_ARG_LIMIT=32
      # CONFIG_COMPILE_TEST is not set
      CONFIG_LOCALVERSION=""
      # CONFIG_LOCALVERSION_AUTO is not set
      CONFIG_BUILD_SALT=""
      CONFIG_HAVE_KERNEL_GZIP=y
      CONFIG_HAVE_KERNEL_BZIP2=y
      CONFIG_KERNEL_GZIP=y
      # CONFIG_KERNEL_BZIP2 is not set
      """

      {:ok, config} = Parser.parse(content, source: "kernel.config")

      # Should parse all entries
      assert length(config.entries) > 15

      # Check specific values
      assert Config.get_entry(config, "CC_IS_GCC").value == true
      assert Config.get_entry(config, "GCC_VERSION").value == 90300
      assert Config.get_entry(config, "LOCALVERSION").value == ""
      assert Config.get_entry(config, "COMPILE_TEST").value == false
      assert Config.get_entry(config, "KERNEL_BZIP2").value == false

      # Check that comments are preserved
      comments = Enum.filter(config.entries, &(&1.type == :comment))
      assert length(comments) > 5
    end

    test "handles defconfig-style minimal config" do
      content =
        String.trim("""
        CONFIG_SYSVIPC=y
        CONFIG_POSIX_MQUEUE=y
        CONFIG_AUDIT=y
        CONFIG_NO_HZ=y
        CONFIG_HIGH_RES_TIMERS=y
        CONFIG_PREEMPT=y
        CONFIG_CGROUPS=y
        CONFIG_BLK_DEV_INITRD=y
        CONFIG_CC_OPTIMIZE_FOR_SIZE=y
        """)

      {:ok, config} = Parser.parse(content)

      # All should be boolean true
      config_entries = Kdef.Config.Operations.config_only(config).entries
      assert Enum.all?(config_entries, &(&1.value == true))
      assert Enum.all?(config_entries, &(&1.type == :bool))
    end
  end

  describe "integration with operations" do
    test "parses, merges, and formats configs" do
      base_content = """
      # Base configuration
      CONFIG_DEBUG=y
      CONFIG_VERBOSE=n
      CONFIG_THREADS=4
      """

      override_content = """
      # Override configuration
      CONFIG_VERBOSE=y
      CONFIG_THREADS=8
      CONFIG_NEW_FEATURE=y
      """

      {:ok, base_config} = Parser.parse(base_content, source: "base.config")
      {:ok, override_config} = Parser.parse(override_content, source: "override.config")

      merged = Kdef.Config.Operations.merge(base_config, override_config)
      formatted = Formatter.format(merged)

      # Parse the result to verify
      {:ok, final_config} = Parser.parse(formatted)

      assert Config.get_entry(final_config, "DEBUG").value == true
      assert Config.get_entry(final_config, "VERBOSE").value == true
      assert Config.get_entry(final_config, "THREADS").value == 8
      assert Config.get_entry(final_config, "NEW_FEATURE").value == true
    end

    test "demonstrates diff workflow" do
      old_content = """
      CONFIG_FEATURE_A=y
      CONFIG_FEATURE_B=n
      CONFIG_VERSION="1.0"
      """

      new_content = """
      CONFIG_FEATURE_A=y
      CONFIG_FEATURE_B=y
      CONFIG_VERSION="2.0"
      CONFIG_NEW_FEATURE=m
      """

      {:ok, old_config} = Parser.parse(old_content)
      {:ok, new_config} = Parser.parse(new_content)

      diff = Kdef.Config.Operations.diff(old_config, new_config)

      assert length(diff.added) == 1
      assert diff.added |> hd() |> Map.get(:key) == "NEW_FEATURE"

      assert length(diff.changed) == 2
      changed_keys = diff.changed |> Enum.map(fn {_, new_entry} -> new_entry.key end)
      assert "FEATURE_B" in changed_keys
      assert "VERSION" in changed_keys

      assert diff.unchanged_count == 1
    end
  end

  describe "metadata preservation" do
    test "preserves source information through operations" do
      {:ok, config1} = Parser.parse("CONFIG_A=y", source: "config1.txt")
      {:ok, config2} = Parser.parse("CONFIG_B=y", source: "config2.txt")

      merged = Kdef.Config.Operations.merge(config1, config2)

      # Check entry-level source tracking
      entry_a = Config.get_entry(merged, "A")
      entry_b = Config.get_entry(merged, "B")

      assert entry_a.source == "config1.txt"
      assert entry_b.source == "config2.txt"
    end

    test "preserves line numbers during parsing" do
      content = """
      CONFIG_FIRST=y
      # Comment on line 2

      CONFIG_FOURTH=n
      """

      {:ok, config} = Parser.parse(content)

      first_entry = Config.get_entry(config, "FIRST")
      fourth_entry = Config.get_entry(config, "FOURTH")
      comment_entry = Enum.find(config.entries, &(&1.type == :comment))

      assert first_entry.line_number == 1
      assert comment_entry.line_number == 2
      assert fourth_entry.line_number == 4
    end
  end

  describe "prefix support" do
    test "infers CONFIG_ prefix automatically" do
      content = """
      CONFIG_ARM64=y
      CONFIG_64BIT=y
      """

      {:ok, config} = Parser.parse(content)
      assert config.prefix == "CONFIG_"

      entry = Config.get_entry(config, "ARM64")
      assert entry.key == "ARM64"
      assert entry.value == true
    end

    test "infers BR2_ prefix automatically" do
      content = """
      BR2_PACKAGE_BUSYBOX=y
      BR2_TOOLCHAIN_GCC=y
      """

      {:ok, config} = Parser.parse(content)
      assert config.prefix == "BR2_"

      entry = Config.get_entry(config, "PACKAGE_BUSYBOX")
      assert entry.key == "PACKAGE_BUSYBOX"
      assert entry.value == true
    end

    test "uses explicit prefix when provided" do
      content = """
      MY_CUSTOM_OPTION=y
      MY_CUSTOM_VALUE="test"
      """

      {:ok, config} = Parser.parse(content, prefix: "MY_CUSTOM_")
      assert config.prefix == "MY_CUSTOM_"

      entry = Config.get_entry(config, "OPTION")
      assert entry.key == "OPTION"
      assert entry.value == true
    end

    test "falls back to CONFIG_ when no prefix can be inferred" do
      content = """
      # Just a comment
      # Another comment
      """

      {:ok, config} = Parser.parse(content)
      assert config.prefix == "CONFIG_"
    end

    test "handles disabled config comments with different prefixes" do
      content = """
      BR2_PACKAGE_BUSYBOX=y
      # BR2_PACKAGE_DROPBEAR is not set
      """

      {:ok, config} = Parser.parse(content)
      assert config.prefix == "BR2_"

      enabled_entry = Config.get_entry(config, "PACKAGE_BUSYBOX")
      assert enabled_entry.value == true

      disabled_entry = Config.get_entry(config, "PACKAGE_DROPBEAR")
      assert disabled_entry.value == false
      assert disabled_entry.metadata.disabled_comment == true
    end

    test "formats entries with correct prefix" do
      {:ok, config} = Parser.parse("BR2_PACKAGE_BUSYBOX=y")
      formatted = Formatter.format(config)
      assert formatted == "BR2_PACKAGE_BUSYBOX=y"
    end

    test "formats disabled entries with correct prefix" do
      content = """
      BR2_PACKAGE_BUSYBOX=y
      # BR2_PACKAGE_DROPBEAR is not set
      """

      {:ok, config} = Parser.parse(content)
      formatted = Formatter.format(config)

      assert String.contains?(formatted, "BR2_PACKAGE_BUSYBOX=y")
      assert String.contains?(formatted, "# BR2_PACKAGE_DROPBEAR is not set")
    end

    test "infers prefix from first config line, ignoring comments" do
      content = """
      # This is a comment
      # Another comment
      BR2_PACKAGE_BUSYBOX=y
      BR2_TOOLCHAIN_GCC=y
      """

      {:ok, config} = Parser.parse(content)
      assert config.prefix == "BR2_"
    end

    test "handles mixed content with custom prefix" do
      content = """
      # Custom configuration
      CUSTOM_OPTION_A=y
      CUSTOM_OPTION_B="value"
      CUSTOM_OPTION_C=42
      # CUSTOM_OPTION_D is not set
      """

      {:ok, config} = Parser.parse(content, prefix: "CUSTOM_")
      assert config.prefix == "CUSTOM_"

      assert Config.get_entry(config, "OPTION_A").value == true
      assert Config.get_entry(config, "OPTION_B").value == "value"
      assert Config.get_entry(config, "OPTION_C").value == 42
      assert Config.get_entry(config, "OPTION_D").value == false
    end

    test "preserves prefix in round-trip parsing and formatting" do
      original_content = """
      BR2_PACKAGE_BUSYBOX=y
      BR2_PACKAGE_DROPBEAR=m
      # BR2_PACKAGE_OPENSSH is not set
      BR2_TARGET_ROOTFS_EXT2=y
      """

      {:ok, config} = Parser.parse(original_content)
      formatted = Formatter.format(config)
      {:ok, reparsed_config} = Parser.parse(formatted)

      assert config.prefix == reparsed_config.prefix
      assert config.prefix == "BR2_"

      # Check that the key-value pairs are preserved
      assert Config.get_entry(config, "PACKAGE_BUSYBOX").value ==
               Config.get_entry(reparsed_config, "PACKAGE_BUSYBOX").value
    end
  end
end
