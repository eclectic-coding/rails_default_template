# Simulation script for cli_option and cli_flag? helpers
# Usage: ruby scripts/simulate_cli_helpers.rb [scenario_name]
# The script reads the helper method definitions from template.rb, evals them
# in this process and runs multiple ARGV scenarios to show parsing behavior.

TEMPLATE = File.read(File.expand_path("../template.rb", __dir__))

helpers = []
# extract def cli_option ... end (robust multiline capture)
if (m = TEMPLATE.match(/(def\s+cli_option[\s\S]*?^end\s*)/m))
  helpers << m[1]
else
  abort "Could not find cli_option method in template.rb"
end

# extract def cli_flag? ... end (robust multiline capture)
if (m = TEMPLATE.match(/(def\s+cli_flag\?[\s\S]*?^end\s*)/m))
  helpers << m[1]
else
  abort "Could not find cli_flag? method in template.rb"
end

# Eval the helper methods in this context
helpers.each { |code| eval(code) }

scenarios = {
  'no args' => [],
  '--javascript=esbuild' => ['--javascript=esbuild'],
  '--javascript esbuild' => ['--javascript', 'esbuild'],
  '--javascript=importmap' => ['--javascript=importmap'],
  '--skip-test flag' => ['--skip-test'],
  '--javascript empty value' => ['--javascript='],
  '--both flags' => ['--javascript=esbuild', '--skip-test'],
  '--flags reversed' => ['--skip-test', '--javascript=esbuild'],
  '--quoted value' => ['--javascript="esbuild"'],
  '--other option' => ['--other', 'value'],
  '--unknown format' => ['--weird=--value'],
}

# allow running a single scenario by name
selected = ARGV.shift

run_list = if selected && scenarios.key?(selected)
  { selected => scenarios[selected] }
else
  scenarios
end

puts "Simulating cli_option and cli_flag? helper behavior:\n"

run_list.each do |name, args|
  # set ARGV for this scenario
  ARGV.replace(args.dup)

  js = cli_option(:javascript, 'importmap')
  skip_test_flag = cli_flag?('skip-test')

  puts "Scenario: #{name}\n  ARGV: #{ARGV.inspect}\n  cli_option(:javascript) => #{js.inspect}\n  cli_flag?(\"skip-test\") => #{skip_test_flag.inspect}\n\n"
end

# Demonstrate how callers can use the value
puts "Example decision: uncomment cssbundling-rails?"
ARGV.replace(['--javascript=esbuild'])
if cli_option(:javascript, 'importmap').to_s != 'importmap'
  puts "  Yes - would uncomment cssbundling-rails"
else
  puts "  No - leave cssbundling-rails commented"
end

