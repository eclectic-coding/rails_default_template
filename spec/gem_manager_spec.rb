require 'fileutils'
require 'tmpdir'
require_relative '../scripts/gem_manager'

RSpec.describe GemManager do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  let(:tpl) do
    # minimal stub that responds to the methods used by GemManager
    Struct.new(:js_choice) do
      def run(cmd); `#{cmd}`; end
      def copy_file(src, dest, force: false)
        # In the generator this copies from template source to destination. In tests
        # we sometimes use the same path for src and dest (to simulate copying an
        # existing file into place). Avoid copying a file onto itself which raises
        # ArgumentError in FileUtils.cp.
        return if File.expand_path(src) == File.expand_path(dest)

        FileUtils.mkdir_p(File.dirname(dest))
        if File.exist?(src)
          FileUtils.cp(src, dest)
        else
          File.write(dest, "")
        end
      end
      def gsub_file(path, pattern, replacement)
        text = File.read(path)
        File.write(path, text.gsub(pattern, replacement))
      end
      def inject_into_file(path, after:, &block)
        text = File.read(path)
        insert_idx = text.index(after) || -1
        insert_text = block.call
        if insert_idx == -1
          File.write(path, text + insert_text)
        else
          new_text = text.sub(after, after + insert_text)
          File.write(path, new_text)
        end
      end
      def instance_variable_get(name)
        nil
      end
    end.new('importmap')
  end

  it 'delegates to GemManagerImportmap when js_choice is importmap' do
    FileUtils.mkdir_p('config/gems')
    File.write('config/gems/app.rb', "# gem 'strong_migrations'\nsource 'https://rubygems.org'\n")
    File.write('Gemfile', "source \"https://rubygems.org\"\n")

    GemManager.apply(tpl)

    content = File.read('config/gems/app.rb')
    # GemManager now delegates to GemManagerImportmap, so the importmap gems should be present
    expect(content).to include('gem "bootstrap"')
    expect(content).to include('gem "dartsass-rails"')
    expect(content).to include('gem "openssl", "~> 3.3"')
  end

  it 'enables cssbundling when js_choice is not importmap' do
    tpl_non = tpl.dup
    tpl_non.js_choice = 'esbuild'

    FileUtils.mkdir_p('config/gems')
    File.write('config/gems/app.rb', "# gem 'cssbundling-rails'\n")
    File.write('Gemfile', "source \"https://rubygems.org\"\n")

    GemManager.apply(tpl_non)

    content = File.read('config/gems/app.rb')
    expect(content).to include('gem "cssbundling-rails"')
  end
end

