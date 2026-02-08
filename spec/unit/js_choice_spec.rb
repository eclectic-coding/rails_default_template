# Minimal options method used when template calls options
def options
  nil
end

# Minimal no-op methods used by template so RSpec can stub or call them
def directory(*); end
def rails_command(*); end
def say(*); end
def insert_into_file(*); end
def system(*); true; end

# Minimal blank? helpers used by template during tests (mimic ActiveSupport)
class String
  def blank?
    self.strip == ''
  end
end

class NilClass
  def blank?
    true
  end
end

# Provide minimal environment so requiring template.rb doesn't execute heavy side-effects
def source_paths
  @__source_paths ||= []
end

# return blank responses for interactive prompts used during template load
def ask(_prompt, _color = nil)
  ""
end

# no-op after_bundle used by template (we don't want to run the full setup during spec load)
def after_bundle(&block)
  # Intentionally no-op for tests
end

# Prevent template.rb top-level user_responses call from executing interactive code during spec load
def user_responses; end

require_relative '../../scripts/gem_manager'

require 'tmpdir'
require 'fileutils'

# Prevent GemManager.apply side-effects while loading template.rb by temporarily
# replacing it with a no-op, then restore the original implementation.
orig_gemmanager_apply = nil
if defined?(GemManager) && GemManager.respond_to?(:apply)
  begin
    orig_gemmanager_apply = GemManager.method(:apply)
  rescue NameError
    orig_gemmanager_apply = nil
  end
  def GemManager.apply(*)
    # no-op while loading template for unit tests
  end
end

require_relative '../../template'

# restore GemManager.apply after loading the template so other specs behave normally
if orig_gemmanager_apply
  singleton_class = class << GemManager; self; end
  singleton_class.define_method(:apply, &orig_gemmanager_apply.to_proc)
end

RSpec.describe 'template.rb js_choice and add_bootstrap_importmap' do
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

  before do
    # stub out heavy operations used by the template
    allow(self).to receive(:directory)
    allow(self).to receive(:rails_command)
    allow(self).to receive(:say)
    allow(self).to receive(:insert_into_file)
    allow(self).to receive(:system).and_return(true)

    # Prevent GemManager.apply side-effects during these specs by stubbing it locally
    allow(GemManager).to receive(:apply)

    allow(File).to receive(:read).with('app/javascript/application.js').and_return("import \"controllers\"\n")
  end

  it 'defaults js_choice to importmap when not provided' do
    $TEMPLATE_OPTIONS = nil
    ARGV.replace([])

    # ensure TemplateCLI returns nil so js_choice falls back
    allow(TemplateCLI).to receive(:cli_option).and_return(nil)

    expect(js_choice).to eq('importmap')
  end

  it 'returns provided js_choice normalized' do
    allow(TemplateCLI).to receive(:cli_option).with(:javascript, anything).and_return('EsBuild')
    expect(js_choice).to eq('esbuild')
  end

  it 'does nothing in add_bootstrap_importmap when js_choice is not "importmap"' do
    allow(TemplateCLI).to receive(:cli_option).and_return('esbuild')
    expect(self).not_to receive(:rails_command)
    add_bootstrap_importmap
  end

  it 'runs importmap flow when js_choice is exactly "importmap"' do
    allow(TemplateCLI).to receive(:cli_option).and_return('importmap')

    # simulate bin/importmap present after rails_command
    allow(File).to receive(:exist?).with('bin/importmap').and_return(true)
    # and app/javascript/application.js exists
    allow(File).to receive(:exist?).with('app/javascript/application.js').and_return(true)

    expect(self).to receive(:directory).with('app_bootstrap_importmap', 'app', force: true)
    expect(self).to receive(:system).with('bin/importmap pin bootstrap').and_return(true)
    expect(self).to receive(:say).with(/Pinned bootstrap via importmap/, :green)
    expect(self).to receive(:insert_into_file).with('app/javascript/application.js', before: "import \"controllers\"\n")

    add_bootstrap_importmap
  end
end

