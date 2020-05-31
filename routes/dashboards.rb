require_relative '../helpers'

get "/therapist_dashboard" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end
  @user = session[:user]
  @all_patients = Patient.get_all

  logger.info "#{logged_in_user} displays therapist dashboard"

  erb :'dashboards/dashboard_base'
end

get "/users/:username/admin_dashboard" do
  unless verify_user_access(min_authorization: :admin)
    redirect "/access_error"
  end
  @user = User.get(params[:username])
  @all_patients = Patient.get_all
  @all_therapists = Therapist.get_all
  @all_admins = Admin.get_all

  logger.info "#{logged_in_user} displays admin dashboard"

  erb :'dashboards/dashboard_base', :layout => :layout do
    erb :'dashboards/admin_dashboard_section'
  end
end