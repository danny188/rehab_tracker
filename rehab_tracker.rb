require "sinatra"
require "sinatra/reloader" if development?
require "tilt"
require "erubis"
require "sinatra/content_for"
require 'date'
require 'bcrypt'
require 'pry-byebug'
require 'chartkick'
require 'net/http'
require 'json'
require 'securerandom'
require 'logger'
require 'redcarpet'
require 'rack-ssl-enforcer'
# require 'mail'
require 'sendgrid-ruby'
include SendGrid
require 'envyable'

require_relative 'custom_objects/init'
include GroupOperations

require_relative 'routes/exercise_library'
require_relative 'routes/accounts'
require_relative 'routes/exercise_tracker'
require_relative 'routes/dashboards'
require_relative 'routes/weather'
require_relative 'routes/misc'
require_relative 'routes/chat'
require_relative 'routes/notifications'

require_relative 'helpers'

Envyable.load('./config/env.yml', 'development')

set :logger, Logger.new($stdout)

ROLES = [:public, :patient, :therapist, :admin]
STAFF_ROLES = [:therapist, :admin]

configure do
  enable :sessions

  if ENV['RACK_ENV'] == 'production'
    set :session_secret, ENV.fetch('SINATRA_SESSION_KEY') { SecureRandom.hex(64) }
    use Rack::SslEnforcer
  else
    set :session_secret, 'secret'
  end

  set :markdown, :layout_engine => :erb
end

get "/debug" do
  session[:debug]
end