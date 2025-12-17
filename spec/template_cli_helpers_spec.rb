require 'tmpdir'
require_relative '../scripts/template_cli_helpers'

RSpec.describe TemplateCLI do
  around do |example|
    orig_argv = ARGV.dup
    orig_template = defined?($TEMPLATE_OPTIONS) ? $TEMPLATE_OPTIONS : nil
    begin
      example.run
    ensure
      ARGV.replace(orig_argv)
      if orig_template.nil?
        $TEMPLATE_OPTIONS = nil
      else
        $TEMPLATE_OPTIONS = orig_template
      end
    end
  end

  describe '.cli_option' do
    it 'prefers $TEMPLATE_OPTIONS value when present' do
      $TEMPLATE_OPTIONS = { javascript: 'esbuild' }
      expect(TemplateCLI.cli_option(:javascript)).to eq('esbuild')
    end

    it 'reads value from ARGV with --name=value' do
      ARGV.replace(["--javascript=importmap"])
      expect(TemplateCLI.cli_option(:javascript)).to eq('importmap')
    end

    it 'reads value from ARGV with --name value' do
      ARGV.replace(["--javascript", "esbuild"])
      expect(TemplateCLI.cli_option(:javascript)).to eq('esbuild')
    end

    it 'supports hyphenated names mapping to underscore' do
      ARGV.replace(["--some-name=hello"])
      expect(TemplateCLI.cli_option(:'some-name')).to eq('hello')
    end

    it 'returns default when not present' do
      ARGV.replace([])
      $TEMPLATE_OPTIONS = nil
      expect(TemplateCLI.cli_option(:missing, 'default')).to eq('default')
    end
  end

  describe '.cli_flag?' do
    it 'returns true for boolean true in $TEMPLATE_OPTIONS' do
      $TEMPLATE_OPTIONS = { skip_test: true }
      expect(TemplateCLI.cli_flag?(:skip_test)).to eq(true)
    end

    it 'interprets string "true" and "false" correctly from $TEMPLATE_OPTIONS' do
      $TEMPLATE_OPTIONS = { skip_test: 'true' }
      expect(TemplateCLI.cli_flag?(:skip_test)).to eq(true)
      $TEMPLATE_OPTIONS = { skip_test: 'false' }
      expect(TemplateCLI.cli_flag?(:skip_test)).to eq(false)
    end

    it 'interprets numeric and numeric-string forms' do
      $TEMPLATE_OPTIONS = { skip_test: '0' }
      expect(TemplateCLI.cli_flag?(:skip_test)).to eq(false)
      $TEMPLATE_OPTIONS = { skip_test: 0 }
      expect(TemplateCLI.cli_flag?(:skip_test)).to eq(false)
    end

    it 'returns true when ARGV contains --flag' do
      ARGV.replace(["--skip_test"])
      expect(TemplateCLI.cli_flag?(:skip_test)).to eq(true)
    end

    it 'parses --flag=value from ARGV' do
      ARGV.replace(["--skip_test=false"])
      expect(TemplateCLI.cli_flag?(:skip_test)).to eq(false)
      ARGV.replace(["--skip_test=true"])
      expect(TemplateCLI.cli_flag?(:skip_test)).to eq(true)
    end

    it 'handles hyphenated flag names' do
      ARGV.replace(["--some-flag"])
      expect(TemplateCLI.cli_flag?(:'some-flag')).to eq(true)
    end
  end
end

