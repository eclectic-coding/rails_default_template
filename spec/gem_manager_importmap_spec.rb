require 'fileutils'
require 'tmpdir'
require_relative '../scripts/gem_manager_importmap'

RSpec.describe GemManagerImportmap do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  it 'inserts gems after strong_migrations comment' do
    FileUtils.mkdir_p('config/gems')
    File.write('config/gems/app.rb', "# gem 'strong_migrations'\nsource 'https://rubygems.org'\n")

    GemManagerImportmap.apply(nil)

    content = File.read('config/gems/app.rb')
    expect(content).to include('gem "bootstrap"')
    expect(content).to include('gem "dartsass-rails"')
    expect(content).to include('gem "openssl"')

    lines = content.lines
    idx = lines.index { |l| l =~ /#\s*gem\s+['\"]strong_migrations/ }
    expect(lines[idx + 1]).to match(/gem\s+"bootstrap"/)
  end

  it 'is idempotent' do
    FileUtils.mkdir_p('config/gems')
    File.write('config/gems/app.rb', "# gem 'strong_migrations'\n")

    GemManagerImportmap.apply(nil)
    first = File.read('config/gems/app.rb')
    GemManagerImportmap.apply(nil)
    second = File.read('config/gems/app.rb')

    expect(second).to eq(first)
  end
end

