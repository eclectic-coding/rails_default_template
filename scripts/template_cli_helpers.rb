# CLI helpers extracted from template.rb
# Provide two helpers under the TemplateCLI namespace:
# - TemplateCLI.cli_option(name, default = nil)
# - TemplateCLI.cli_flag?(name)

require 'shellwords'

module TemplateCLI
  module_function

  def cli_option(name, default = nil)
    # Normalize names with hyphens to underscore keys for the options hash
    name_str = name.to_s
    key_str = name_str.tr('-', '_')
    key_sym = key_str.to_sym

    # prefer test harness global if present
    opts = defined?($TEMPLATE_OPTIONS) ? $TEMPLATE_OPTIONS : nil

    # try to obtain an options object if available (handles cases where options is a method)
    if opts.nil?
      begin
        opts = options
      rescue NameError, NoMethodError
        opts = nil
      end
    end

    # prefer the `options` hash provided by Rails templates when present
    if opts
      opts_hash = nil
      begin
        opts_hash = opts.to_hash
      rescue NoMethodError, TypeError
        opts_hash = nil
      end

      if opts_hash
        if opts_hash.key?(key_sym)
          return opts_hash[key_sym]
        elsif opts_hash.key?(key_str)
          return opts_hash[key_str]
        elsif opts_hash.key?(name_str)
          return opts_hash[name_str]
        end
      end
    end

    # helper to remove surrounding quotes from a value
    unquote = ->(v) { v.nil? ? v : v.to_s.gsub(/^['"]|['"]$/, '') }

    # parse ARGV: --name=value
    if (arg = ARGV.find { |a| a.start_with?("--#{name_str}=") })
      return unquote.call(arg.split("=", 2)[1])
    end

    # parse ARGV: --name value
    idx = ARGV.index("--#{name_str}")
    if idx && ARGV[idx + 1] && !ARGV[idx + 1].start_with?("--")
      return unquote.call(ARGV[idx + 1])
    end

    default
  end

  def cli_flag?(name)
    name_str = name.to_s
    key_str = name_str.tr('-', '_')
    key_sym = key_str.to_sym

    # helper to coerce common values to boolean
    to_bool = ->(v) do
      return false if v.nil?
      return v if v == true || v == false
      if v.is_a?(Numeric)
        return v != 0
      end
      s = v.to_s.strip.downcase
      return false if s == ''
      return !(s =~ /\A(false|0)\z/i)
    end

    # prefer test harness global if present
    opts = defined?($TEMPLATE_OPTIONS) ? $TEMPLATE_OPTIONS : nil

    # try to obtain an options object if available (handles cases where options is a method)
    if opts.nil?
      begin
        opts = options
      rescue NameError, NoMethodError
        opts = nil
      end
    end

    if opts
      opts_hash = nil
      begin
        opts_hash = opts.to_hash
      rescue NoMethodError, TypeError
        opts_hash = nil
      end

      if opts_hash
        if opts_hash.key?(key_sym)
          return to_bool.call(opts_hash[key_sym])
        elsif opts_hash.key?(key_str)
          return to_bool.call(opts_hash[key_str])
        elsif opts_hash.key?(name_str)
          return to_bool.call(opts_hash[name_str])
        end
      end
    end

    # if explicitly provided as --flag=value, interpret common boolean forms
    if (arg = ARGV.find { |a| a.start_with?("--#{name_str}=") })
      val = arg.split("=", 2)[1].to_s.gsub(/^['"]|['"]$/, '')
      return to_bool.call(val)
    end

    ARGV.any? { |a| a == "--#{name_str}" || a.start_with?("--#{name_str}=") }
  end
end

