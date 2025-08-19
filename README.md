# My Default Rails Template

This is a simple Rails Template to start a new project. It is a template I use to remove those tasks a developer has to perform to set up a new project in Rails:

## Features
- Defaults to Esbuild for JavaScript bundling
- Asks the user for a choice of styling systems. Right now between Bootstrap or none, adding Tailwind soon
- Defaults to `minitest` but if the user uses `-T` with `rails new` it will set up RSpec, or now tests at all
  - Includes preconfigure FactoryBot (RSPEC), Faker, and Webmock
  - Set up Code Coverage with `simplecov`
- Set up Rubocop using `rubocop-rails-omakase`
- Adds code quality and security tools that can be used with `bin/ci`
- Add static controller and home page
- Configure rails generators to not generate helpers or stylesheets
- Create postgresql database and `db:migrate`
- You can enable local development SSL: Defaults to `https://localhost:3001` or without SSL at `http://localhost:3000`

## Start using
Clone or fork and clone this repo:
```shell
git clone git@github.com:eclectic-coding/rails_default_template.git
```
**Create a new application:**

There are a few prerequisites. By defaults `rails new` looks in your root directory for a `.railrc` configuration file. Here you can place these commands, so you do not have to remember them each time. In your root home directory create `.railsrc`, and add the following:
```shell
--skip-spring
-a propshaft
-j esbuild
-m ~/path/to/repo/rails_default_template/template.rb
```
Create new app: `rails new awesome_app -T` if you wish to add rspec

Bypass these settings and this template for a default rails app: `rails new awesome_app --no-rc`
