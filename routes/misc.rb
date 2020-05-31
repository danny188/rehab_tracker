require_relative '../helpers'

get "/" do
  redirect_to_home_page(session[:user])
end

not_found do
  erb :custom_404
end

get "/about" do
  logger.info "#{logged_in_user} visits about page"
  erb :about
end

get "/access_error" do
  erb :access_error
end

get "/privacy_policy" do
  logger.info "#{logged_in_user} views privacy policy"
  erb :privacy_policy
end

get "/terms" do
  logger.info "#{logged_in_user} views terms of service"
  markdown :terms, layout: :layout
end
