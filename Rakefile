require 'rake/clean'
require 'dotenv/tasks'
require_relative 'amazon'

task :check_inventory => :dotenv do
  amazon = Amazon.new
  amazon.check_inventory
end