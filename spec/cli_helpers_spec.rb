# frozen_string_literal: true

require 'rspec'

# Load the cli helper methods from template.rb by extracting their definitions and eval'ing them.
TEMPLATE = File.read(File.expand_path('../template.rb', __dir__))

helpers = []
if (m = TEMPLATE.match(/(def\s+cli_option[\s\S]*?^end\s*)/m))
  helpers << m[1]
else
  raise 'Could not find cli_option method in template.rb'
end

if (m = TEMPLATE.match(/(def\s+cli_flag\?[\s\S]*?^end\s*)/m))
  helpers << m[1]
else
  raise 'Could not find cli_flag? method in template.rb'
end

# Eval the helper methods at top-level so they behave like in template context
helpers.each { |code| eval(code) }

RSpec.describe 'cli helpers' do
  after(:each) do
    ARGV.replace([])
    # cleanup any global used for tests
    if Object.respond_to?(:remove_method)
      begin
        Object.send(:remove_method, :options)
      rescue NameError
        # ignore if not defined
      end
    end
  end

  scenarios = {
    'no args' => [],
    '--javascript=esbuild' => ['--javascript=esbuild'],
    '--javascript esbuild' => ['--javascript', 'esbuild'],
    '--javascript=importmap' => ['--javascript=importmap'],
    '--skip-test flag' => ['--skip-test'],
    '--javascript empty value' => ['--javascript='],
    'other flag with value' => ['--other=foo'],
  }

  scenarios.each do |name, args|
    it "parses ARGV correctly for #{name}" do
      ARGV.replace(args)

      js = cli_option(:javascript, 'importmap')
      skip_test_flag = cli_flag?('skip-test')

      case name
      when 'no args'
        expect(js).to eq('importmap')
        expect(skip_test_flag).to be false
      when '--javascript=esbuild', '--javascript esbuild'
        expect(js).to eq('esbuild')
        expect(skip_test_flag).to be false
      when '--javascript=importmap'
        expect(js).to eq('importmap')
        expect(skip_test_flag).to be false
      when '--skip-test flag'
        expect(js).to eq('importmap')
        expect(skip_test_flag).to be true
      when '--javascript empty value'
        expect(js).to eq('')
      when 'other flag with value'
        expect(cli_option(:other, nil)).to eq('foo')
      end
    end
  end

  it 'prefers options hash over ARGV when options is present (symbol key)' do
    # define a top-level options method to simulate Rails template `options`
    Object.send(:define_method, :options) { { javascript: 'esbuild', skip_test: true } }

    ARGV.replace(['--javascript=importmap'])

    expect(cli_option(:javascript, 'importmap')).to eq('esbuild')
    expect(cli_flag?('skip-test')).to be true
  end

  it 'prefers options hash over ARGV when options present (string key)' do
    Object.send(:define_method, :options) { { 'javascript' => 'esbuild' } }

    ARGV.replace(['--javascript=importmap'])

    expect(cli_option(:javascript, 'importmap')).to eq('esbuild')
  end

  it 'treats missing option as default' do
    ARGV.replace([])
    expect(cli_option(:javascript, 'importmap')).to eq('importmap')
  end

  it 'determines uncomment decision for cssbundling-rails' do
    ARGV.replace(['--javascript=esbuild'])
    expect(cli_option(:javascript, 'importmap').to_s).to_not eq('importmap')

    ARGV.replace(['--javascript=importmap'])
    expect(cli_option(:javascript, 'importmap').to_s).to eq('importmap')
  end

  it 'parses boolean flag formats (true/false/0/1 and quoted)' do
    ARGV.replace(['--skip-test=true'])
    expect(cli_flag?('skip-test')).to be true

    ARGV.replace(['--skip-test=false'])
    expect(cli_flag?('skip-test')).to be false

    ARGV.replace(['--skip-test=0'])
    expect(cli_flag?('skip-test')).to be false

    ARGV.replace(['--skip-test=1'])
    expect(cli_flag?('skip-test')).to be true

    ARGV.replace(["--skip-test=\"false\""])
    expect(cli_flag?('skip-test')).to be false
  end

  it 'handles quoted values and values containing spaces' do
    ARGV.replace(["--javascript='es build'"])
    expect(cli_option(:javascript, 'importmap')).to eq('es build')

    ARGV.replace(["--javascript=es build"]) # simulate a single ARGV element that includes a space
    expect(cli_option(:javascript, 'importmap')).to eq('es build')
  end
end
