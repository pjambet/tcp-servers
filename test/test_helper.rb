# frozen_string_literal: true

require "minitest/autorun"
require "minitest/focus"
require "logger"

# require "debug"

LOG = Logger.new(STDOUT)

LOG.level = if ENV["LOG_LEVEL"]
              Logger.const_get(ENV["LOG_LEVEL"].upcase)
            else
              Logger::WARN
            end

SERVER_CONFIG = nil

PORT = "3000"

SERVER_CONFIGS = {
  "c" => {
    "build" => "(cd c && make clean && make)",
    "start" => ["./c/server"],
  },
  "ruby" => {
    "build" => nil,
    "start" => ["ruby", "ruby/server.rb"],
  },
  "python" => {
    "build" => nil,
    "start" => ["python3", "python/server.py"],
  },
  "go" => {
    "build" => "go build -o ./go/server go/server.go",
    "start" => ["./go/server"],
  },
  "node" => {
    "build" => nil,
    "start" => ["node", "node/server.js"],
  },
  "rust" => {
    "build" => "(cd rust && cargo build)",
    "start" => ["./rust/target/debug/tcp"],
  },
  "kotlin" => {
    "build" => "(cd kotlin && gradle clean && gradle fatJar)",
    "start" => ["java", "-jar", "kotlin/build/libs/kotlin-1.0-SNAPSHOT-standalone.jar"],
  },
  "java" => {
    "build" => "(cd java && javac -d . tcp-server/src/main/java/main/Main.java && jar cfe Main.jar main.Main main/Main.class)",
    "start" => %w[java -jar java/Main.jar],
  },
  "clojure" => {
    "build" => "(cd clojure && lein uberjar)",
    "start" => ["java", "-jar", "clojure/target/uberjar/tcp-server-0.1.0-SNAPSHOT-standalone.jar"],
  },
  "zig" => {
    "build" => "(cd zig && zig build-exe src/main.zig)",
    "start" => ["./zig/main"],
  },
}

SERVER_CONFIG = SERVER_CONFIGS[ENV["SERVER"]&.downcase]

if SERVER_CONFIG.nil?
  raise "Need to pass a valid SERVER env variable to run, e.g SERVER=ruby rake, valid options: #{ SERVER_CONFIGS.keys.join(', ') }"
end

if SERVER_CONFIG["build"]
  LOG.debug "building with #{ SERVER_CONFIG['build'] }"
  system(SERVER_CONFIG["build"])
end
