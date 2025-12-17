# Importmap-specific gem management for the template generator.
# Keep importmap logic isolated so `GemManager` stays small and easier to test.
module GemManagerImportmap
  module_function

  def apply(_tpl)
    path = "config/gems/app.rb"

    # Ensure file exists before proceeding
    return unless File.exist?(path)

    content = File.read(path)

    # Only add the gem lines that are missing (idempotent)
    gems_to_add = []
    gems_to_add << 'gem "bootstrap", "~> 5.3.3"' unless content.match?(/gem\s+['"]bootstrap['"]/)
    gems_to_add << 'gem "dartsass-rails"' unless content.match?(/gem\s+['"]dartsass-rails['"]/)
    gems_to_add << 'gem "openssl", "~> 3.3", ">= 3.3.2"' unless content.match?(/gem\s+['"]openssl['"]/)

    return unless gems_to_add.any?

    lines = content.lines

    # find index of the commented strong_migrations line
    idx = lines.index { |l| l =~ /#\s*gem\s+['"]strong_migrations['"]/ }

    # Prepare insertion block (each gem on its own line)
    insert_block = gems_to_add.map { |g| g + "\n" }.join

    if idx
      # Insert after the strong_migrations comment
      lines.insert(idx + 1, insert_block)
    else
      # Append at end
      lines << "\n" unless lines.last&.end_with?("\n")
      lines << insert_block
    end

    # Write back the file in one go
    File.write(path, lines.join)
  end
end

