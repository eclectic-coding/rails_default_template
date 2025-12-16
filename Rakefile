# Minimal Rakefile to load tasks under lib/tasks
require 'bundler/setup'
require 'rake'

# Load all rake files in lib/tasks
Dir.glob(File.join(__dir__, 'lib', 'tasks', '**', '*.rake')).sort.each { |f| load f }

# If no default task is defined by tasks, define a noop
if Rake.application.top_level_tasks.empty?
  task :default do
    puts "No default Rake task defined. Run `bundle exec rake -T` to see available tasks."
  end
end

