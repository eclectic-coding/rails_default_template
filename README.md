# My Default Rails Template

This is a simple Rails Template to start a new project. It is a template I use to remove those tasks a developer has to perform to set up a new project in Rails:

- Set up RSpec
- Set up Code Coverage
- Set up Guard, and Guard live-reloading
- Set up Rubocop
- Add static controller and home page
- Configure rails generators to not generate helpers or stylesheets
- Create postgresql database and `db:migrate`

## Start using
Clone or fork and clone this repo: 
```shell
git clone git@github.com:eclectic-coding/rails_default_template.git
```
**Create a new application:**
There are a few prerequisites:
- Template is setup to use Postgresql
- Since it uses RSpec, you need to use the `-T` to not install testing
- To use the template you need to use the `-m` switch followed by the path to the `template.rb`

By defaults `rails new` looks in your root directory for a `.railrc` configuration file. Here you can place these commands, so you do not have to remember them each time. In your root home directory create `.railsrc`, and add the following:
```shell
--database=postgresql -T -m ~/path/to/repo/rails_default_template/template.rb
```
Create new app: `rails new awesome_app`

Bypass these settings for a default rails app: `rails new awesome_app --no-rc`