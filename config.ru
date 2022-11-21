# config.ru

require "./rehab_tracker"


run Sinatra::Application

$stdout.sync = true