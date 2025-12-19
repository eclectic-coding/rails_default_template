require 'rspec'

RSpec.describe 'skip_tests? helper' do
  before(:all) do
    template_path = File.expand_path('../../../template.rb', __FILE__)
    template = File.read(template_path)

    method_match = template.match(/def skip_tests\?.*?\nend\n/m)
    raise 'skip_tests? method not found in template.rb' unless method_match

    @method_src = method_match[0]

    # Create an isolated module containing only the skip_tests? method so we
    # can call it on instances without executing the rest of template.rb.
    @mod = Module.new
    @mod.module_eval(@method_src)

    mod = @mod
    @klass = Class.new { include mod }
  end

  around(:each) do |example|
    # Preserve globals
    original_argv = ARGV.dup
    original_template_options = defined?($TEMPLATE_OPTIONS) ? $TEMPLATE_OPTIONS.dup : nil
    example.run
    ARGV.replace(original_argv)
    if original_template_options.nil?
      remove_instance_variable(:@_restore_template_options) if defined?(@_restore_template_options)
      $TEMPLATE_OPTIONS = nil
    else
      $TEMPLATE_OPTIONS = original_template_options
    end
    # Cleanup TemplateCLI constant if it was set by a test
    Object.send(:remove_const, :TemplateCLI) if Object.const_defined?(:TemplateCLI) && !defined?(TemplateCLI).nil?
  end

  it 'returns true when TemplateCLI.cli_flag? reports skip_test' do
    stub_const('TemplateCLI', Class.new)
    # Define a concrete singleton method so rspec's verifying doubles don't raise
    def TemplateCLI.cli_flag?(flag)
      flag == :skip_test
    end

    # Ensure respond_to? reflects the method
    def TemplateCLI.respond_to?(sym)
      sym == :cli_flag? || super
    end

    instance = @klass.new
    expect(instance.send(:skip_tests?)).to eq(true)
  end

  it 'returns true when options contains skip_test' do
    instance = @klass.new
    # Define an instance method `options` that returns the hash
    def instance.options
      { skip_test: true }
    end

    expect(instance.send(:skip_tests?)).to eq(true)
  end

  it 'returns true when $TEMPLATE_OPTIONS contains skip-test' do
    $TEMPLATE_OPTIONS = { 'skip-test' => true }
    instance = @klass.new
    expect(instance.send(:skip_tests?)).to eq(true)
  end

  it 'returns true when ARGV contains -T' do
    ARGV.replace(['-T'])
    instance = @klass.new
    expect(instance.send(:skip_tests?)).to eq(true)
  end

  it 'returns false when no skip indicators present' do
    # Ensure globals are clear
    Object.send(:remove_const, :TemplateCLI) if Object.const_defined?(:TemplateCLI)
    $TEMPLATE_OPTIONS = nil
    ARGV.replace([])

    instance = @klass.new
    expect(instance.send(:skip_tests?)).to eq(false)
  end
end

