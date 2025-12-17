# Helper module to manage gemfile insertion/cleanup for the template.
# This module is designed to be called from the template with the template
# context instance passed in (so it can call `run`, `copy_file`, `gsub_file`, etc.).
module GemManager
  module_function

  def apply(tpl)
    # tpl is the template instance (self from template.rb)
    tpl.run "mkdir config/gems"

    tpl.copy_file "config/gems/app.rb", "config/gems/app.rb", force: true

    # Delegate importmap-specific gem insertions to GemManagerImportmap when requested
    if tpl.js_choice == "importmap"
      require_relative "gem_manager_importmap"
      GemManagerImportmap.apply(tpl)
    else
      if File.exist?("config/gems/app.rb")
        tpl.gsub_file "config/gems/app.rb", /#\s*gem\s+['"]cssbundling-rails['"]/, 'gem "cssbundling-rails"'
      end
    end

    # Insert eval_gemfile 'config/gems/app.rb' into the Gemfile.
    gemfile_path = "Gemfile"
    if File.exist?(gemfile_path)
      gemfile_content = File.read(gemfile_path)
      strong_line = gemfile_content.lines.find { |l| l =~ /#\s*gem\s+['"]strong_migrations['"]/ }

      if strong_line
        tpl.inject_into_file gemfile_path, after: strong_line do
          "\n\neval_gemfile 'config/gems/app.rb'\n"
        end
      else
        tpl.inject_into_file gemfile_path, after: "source \"https://rubygems.org\"" do
          "\n\neval_gemfile 'config/gems/app.rb'\n"
        end
      end
    else
      # Fallback to originally inject when Gemfile is missing for some reason
      tpl.inject_into_file "Gemfile", after: "source \"https://rubygems.org\"" do
        "\n\neval_gemfile 'config/gems/app.rb'\n"
      end
    end

    # Remove any existing test eval_gemfile lines so we can insert exactly one, idempotently
    if File.exist?("Gemfile")
      tpl.gsub_file "Gemfile", /\n*eval_gemfile\s+'config\/gems\/rspec_gemfile.rb'\s*\n*/m, ''
      tpl.gsub_file "Gemfile", /\n*eval_gemfile\s+'config\/gems\/minitest_gemfile.rb'\s*\n*/m, ''
    end

    testing_response = tpl.instance_variable_get(:@testing_response)

    if testing_response == "y"
      # Remove any gems listed in the minitest gemfile from the Gemfile
      if File.exist?("config/gems/minitest_gemfile.rb")
        minitest_gems = File.read("config/gems/minitest_gemfile.rb").scan(/gem\s+['"]([^'"]+)['"]/).flatten
        minitest_gems.each do |g_name|
          tpl.gsub_file "Gemfile", /^\s*gem\s+['"]#{Regexp.escape(g_name)}['\"].*\n/, ''
        end
      end

      # Remove test/ directory if present (cleanup prior runs)
      tpl.run "rm -rf test" if Dir.exist?("test")

      tpl.copy_file "config/gems/rspec_gemfile.rb", "config/gems/rspec_gemfile.rb", force: true
      # inject only if not already present
      gemfile_txt = File.read('Gemfile') if File.exist?('Gemfile')
      unless gemfile_txt && gemfile_txt.include?("eval_gemfile 'config/gems/rspec_gemfile.rb'")
        tpl.inject_into_file "Gemfile", after: "eval_gemfile 'config/gems/app.rb'" do
          "\neval_gemfile 'config/gems/rspec_gemfile.rb'"
        end
      end
    elsif testing_response == "n"
      # Remove any gems listed in the rspec gemfile from the Gemfile
      if File.exist?("config/gems/rspec_gemfile.rb")
        rspec_gems = File.read("config/gems/rspec_gemfile.rb").scan(/gem\s+['"]([^'"]+)['"]/).flatten
        rspec_gems.each do |g_name|
          tpl.gsub_file "Gemfile", /^\s*gem\s+['"]#{Regexp.escape(g_name)}['\"].*\n/, ''
        end
      end

      # Remove spec/ and .rspec if present (cleanup prior runs)
      tpl.run "rm -rf spec" if Dir.exist?("spec")
      tpl.run "rm -f .rspec" if File.exist?('.rspec')

      tpl.copy_file "config/gems/minitest_gemfile.rb", "config/gems/minitest_gemfile.rb", force: true
      gemfile_txt = File.read('Gemfile') if File.exist?('Gemfile')
      unless gemfile_txt && gemfile_txt.include?("eval_gemfile 'config/gems/minitest_gemfile.rb'")
        tpl.inject_into_file "Gemfile", after: "eval_gemfile 'config/gems/app.rb'" do
          "\neval_gemfile 'config/gems/minitest_gemfile.rb'"
        end
      end
    else
      # tests skipped by options; do not inject any test gemfiles
    end

    tpl.run("ruby -v | awk '{print $2}' > .ruby-version")
  end
end

