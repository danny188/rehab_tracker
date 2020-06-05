require_relative '../helpers'

get "/users/:username/therapist_dashboard" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end
  @user = User.get(params[:username])
  @all_patients = Patient.get_all

  logger.info "#{logged_in_user} displays therapist dashboard"

  sort_by = params[:sort]
  direction = nil_or_empty?(params[:dir]) ? 'desc' : params[:dir]

  sort_criteria = ['first_name', 'last_name', 'last_login_time', 'username']

  if sort_criteria.include?(sort_by)
    @all_patients.sort_by! { |pt| pt.public_send(sort_by).to_s.downcase || Time.new(2000) }
  else
    @all_patients.sort_by! { |pt| pt.last_login_time || Time.new(2000) }
  end

  @all_patients.reverse! if direction == 'desc'

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