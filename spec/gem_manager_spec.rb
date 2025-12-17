require 'tmpdir'
require 'fileutils'
require_relative '../scripts/gem_manager'

RSpec.describe GemManager do
  def prepare_temp_copy
    Dir.mktmpdir do |dir|
      # copy Gemfile and config/gems
      FileUtils.cp(File.join(Dir.pwd, 'Gemfile'), File.join(dir, 'Gemfile')) if File.exist?('Gemfile')
      FileUtils.mkdir_p(File.join(dir, 'config/gems'))
      %w[app.rb rspec_gemfile.rb minitest_gemfile.rb].each do |f|
        src = File.join('config/gems', f)
        if File.exist?(src)
          FileUtils.cp(src, File.join(dir, 'config/gems', f))
        else
          # create a minimal placeholder if missing
          File.write(File.join(dir, 'config/gems', f), "# placeholder for #{f}\n")
        end
      end

      # also copy .rspec if present
      FileUtils.cp('.rspec', File.join(dir, '.rspec')) if File.exist?('.rspec')

      yield dir
    end
  end

  class FakeTpl
    include FileUtils
    def initialize(work_dir, js_choice:, testing_response:)
      @work_dir = work_dir
      @js_choice = js_choice
      @testing_response = testing_response
      instance_variable_set(:@testing_response, testing_response)
    end

    def js_choice
      @js_choice
    end

    def run(cmd)
      # noop during tests
    end

    def system(cmd)
      # noop
    end

    def copy_file(src, dest, force: false)
      srcp = File.join(@work_dir, src)
      unless File.exist?(srcp)
        alt = File.join(Dir.pwd, src)
        srcp = alt if File.exist?(alt)
      end
      destp = File.join(@work_dir, dest)
      # If source and destination resolve to the same path, do nothing
      if File.exist?(srcp) && File.expand_path(srcp) == File.expand_path(destp)
        return
      end
      FileUtils.mkdir_p(File.dirname(destp))
      FileUtils.cp(srcp, destp) if File.exist?(srcp)
    end

    def gsub_file(path, pattern, replacement)
      p = File.join(@work_dir, path)
      return unless File.exist?(p)
      text = File.read(p)
      new_text = text.gsub(pattern, replacement)
      File.write(p, new_text) if new_text != text
    end

    def inject_into_file(path, after: nil)
      p = File.join(@work_dir, path)
      FileUtils.mkdir_p(File.dirname(p))
      File.write(p, '') unless File.exist?(p)
      text = File.read(p)
      insertion = block_given? ? yield : ''
      if after
        if after.is_a?(Regexp)
          if text =~ after
            pos = Regexp.last_match.end(0)
            new_text = text.dup
            new_text.insert(pos, insertion)
            File.write(p, new_text)
          else
            File.write(p, text + insertion)
          end
        else
          if (idx = text.index(after))
            insert_pos = idx + after.length
            new_text = text.dup
            new_text.insert(insert_pos, insertion)
            File.write(p, new_text)
          else
            File.write(p, text + insertion)
          end
        end
      else
        File.write(p, text + insertion)
      end
    end

    def directory(src, dest = nil, force: false)
      srcp = File.join(@work_dir, src)
      destp = File.join(@work_dir, dest || src)
      if File.exist?(srcp)
        FileUtils.mkdir_p(File.dirname(destp))
        FileUtils.cp_r(srcp, destp)
      else
        alt = File.join(Dir.pwd, src)
        if File.exist?(alt)
          FileUtils.mkdir_p(File.dirname(destp))
          FileUtils.cp_r(alt, destp)
        end
      end
    end

    def instance_variable_get(name)
      super
    end

    def system(cmd)
      # noop
    end
  end

  it 'inserts gems for importmap and adds rspec when selected' do
    prepare_temp_copy do |dir|
      tpl = FakeTpl.new(dir, js_choice: 'importmap', testing_response: 'y')
      Dir.chdir(dir) { GemManager.apply(tpl) }
      gemfile = File.read(File.join(dir, 'Gemfile'))
      expect(gemfile).to include("eval_gemfile 'config/gems/app.rb'")
      expect(gemfile).to include("eval_gemfile 'config/gems/rspec_gemfile.rb'")
      app_rb = File.read(File.join(dir, 'config/gems/app.rb'))
      expect(app_rb).to include('gem "bootstrap"')
      expect(app_rb).to include('gem "dartsass-rails"')
      expect(app_rb).to include('gem "openssl"')
    end
  end

  it 'adds rspec eval for esbuild when selected' do
    prepare_temp_copy do |dir|
      tpl = FakeTpl.new(dir, js_choice: 'esbuild', testing_response: 'y')
      Dir.chdir(dir) { GemManager.apply(tpl) }
      gemfile = File.read(File.join(dir, 'Gemfile'))
      expect(gemfile).to include("eval_gemfile 'config/gems/rspec_gemfile.rb'")
    end
  end

  it 'adds minitest eval for esbuild when selected n' do
    prepare_temp_copy do |dir|
      tpl = FakeTpl.new(dir, js_choice: 'esbuild', testing_response: 'n')
      Dir.chdir(dir) { GemManager.apply(tpl) }
      gemfile = File.read(File.join(dir, 'Gemfile'))
      expect(gemfile).to include("eval_gemfile 'config/gems/minitest_gemfile.rb'")
    end
  end

  it 'does not inject test gemfile when tests skipped' do
    prepare_temp_copy do |dir|
      tpl = FakeTpl.new(dir, js_choice: 'importmap', testing_response: nil)
      Dir.chdir(dir) { GemManager.apply(tpl) }
      gemfile = File.read(File.join(dir, 'Gemfile'))
      expect(gemfile).to include("eval_gemfile 'config/gems/app.rb'")
      expect(gemfile).not_to include("eval_gemfile 'config/gems/minitest_gemfile.rb'")
      expect(gemfile).not_to include("eval_gemfile 'config/gems/rspec_gemfile.rb'")
    end
  end

  it 'is idempotent when applied twice' do
    prepare_temp_copy do |dir|
      tpl = FakeTpl.new(dir, js_choice: 'importmap', testing_response: 'y')
      Dir.chdir(dir) do
        GemManager.apply(tpl)
        GemManager.apply(tpl)
      end
      app_rb = File.read(File.join(dir, 'config/gems/app.rb'))
      # gems should only appear once
      expect(app_rb.scan(/gem\s+\"bootstrap\"/).size).to be <= 1
      expect(app_rb.scan(/gem\s+\"openssl\"/).size).to be <= 1
      gemfile = File.read(File.join(dir, 'Gemfile'))
      expect(gemfile.scan(/eval_gemfile\s+'config\/gems\/rspec_gemfile.rb'/).size).to be <= 1
    end
  end

  it 'inserts after strong_migrations comment when present' do
    prepare_temp_copy do |dir|
      # craft an app.rb with a strong_migrations comment
      app_rb_path = File.join(dir, 'config/gems/app.rb')
      File.write(app_rb_path, <<~RB)
        gem "annotate"
        # gem "strong_migrations" # Uncomment if you want to use strong_migrations
        gem "inline_svg"
      RB

      tpl = FakeTpl.new(dir, js_choice: 'importmap', testing_response: 'y')
      Dir.chdir(dir) { GemManager.apply(tpl) }

      lines = File.read(app_rb_path).lines.map(&:chomp)
      strong_idx = lines.index { |l| l =~ /#\s*gem\s+['\"]strong_migrations['\"]/ }
      bootstrap_idx = lines.index { |l| l.include?('gem "bootstrap"') }
      expect(strong_idx).not_to be_nil
      expect(bootstrap_idx).not_to be_nil
      expect(bootstrap_idx).to be > strong_idx
    end
  end

  it 'uncomments cssbundling-rails for non-importmap flows' do
    prepare_temp_copy do |dir|
      app_rb_path = File.join(dir, 'config/gems/app.rb')
      # ensure a commented cssbundling line exists
      File.write(app_rb_path, <<~RB)
        # gem "cssbundling-rails"
        gem "inline_svg"
      RB

      tpl = FakeTpl.new(dir, js_choice: 'esbuild', testing_response: 'n')
      Dir.chdir(dir) { GemManager.apply(tpl) }

      content = File.read(app_rb_path)
      expect(content).to include('gem "cssbundling-rails"')
      expect(content).not_to include('# gem "cssbundling-rails"')
    end
  end

  it 'removes opposite test eval when switching frameworks' do
    prepare_temp_copy do |dir|
      # seed Gemfile with minitest eval then select rspec
      gemfile_path = File.join(dir, 'Gemfile')
      File.write(gemfile_path, "source 'https://rubygems.org'\n\neval_gemfile 'config/gems/minitest_gemfile.rb'\n")

      tpl = FakeTpl.new(dir, js_choice: 'importmap', testing_response: 'y')
      Dir.chdir(dir) { GemManager.apply(tpl) }

      gemfile = File.read(gemfile_path)
      expect(gemfile).to include("eval_gemfile 'config/gems/rspec_gemfile.rb'")
      expect(gemfile).not_to include("eval_gemfile 'config/gems/minitest_gemfile.rb'")
    end
  end
end
