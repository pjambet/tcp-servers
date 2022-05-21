require "rake/testtask"
require "minitest/reporters"

# Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(:color => true)]
Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new()]

task default: "test"

Rake::TestTask.new do |t|
  t.pattern = "test/*test.rb"
end
