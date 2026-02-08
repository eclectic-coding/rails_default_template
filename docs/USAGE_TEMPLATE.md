# Using the rails_default_template

This template customizes Rails app generation and offers interactive choices for JavaScript bundling and styling.

Recommended invocation (prevents Rails from running JS installers early):

```bash
# preferred: template controls JS tooling
./scripts/new_with_template.sh myapp
```

If you want Rails itself to set up the JS bundler (and avoid template prompts), pass the desired option to `rails new`:

```bash
rails new myapp --javascript=esbuild -m /path/to/template.rb
```

Environment variables:

- `RAILS_TEMPLATE_NO_SKIP_JS=1` — when using `scripts/new_with_template.sh`, set this to avoid automatically adding `--skip-javascript`.

Troubleshooting:

- If you see errors about `importmap:install` or `javascript:install:esbuild` during `rails new`, use the helper script above or pass `--skip-javascript` to prevent Rails from running its own installers before the template runs.
- If esbuild builds fail, ensure `node` and `yarn`/`npm` are installed and run `yarn add esbuild -D` or `npm install esbuild --save-dev` inside the new app.


