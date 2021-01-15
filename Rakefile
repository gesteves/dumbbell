require 'rake/clean'
require 'dotenv/tasks'
require_relative 'amazon'
require_relative 'web'

task :check_inventory => :dotenv do
  amazon = Amazon.new
  amazon.check_inventory
  web = Web.new
  web.check_inventory
end
