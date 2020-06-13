require_relative '../helpers'

get "/users/:username/deactivate_account" do
  @deactivate_user = User.get(params[:username])

  logger.info "#{logged_in_user} displays deactivate account page for user #{params[:username]}"

  unless @deactivate_user
    halt erb(:custom_404)
  end

  if @deactivate_user.username == session[:user].username
    if @deactivate_user.role == :therapist
      @message = "Dear #{address_user(@deactivate_user)}, thank you for looking after your patients. Take care!"
    elsif @deactivate_user.role == :patient
      @message = "Dear #{address_user(@deactivate_user)}, we sincerely hope that Rehab Buddy has helped you along the way. Take care!"
    end
    erb :'accounts/deactivate_account_own'
  else
    erb :'accounts/deactivate_account_on_behalf'
  end
end

post "/users/:username/deactivate_account" do
  @deactivate_user = User.get(params[:username])
  @confirm_username = params[:confirm_username]
  @confirm_password = params[:confirm_password]
  @understand_check = params[:understand_check]

  deactivating_own_account = params[:username] == session[:user].username
  deactivating_on_behalf = !deactivating_own_account

  if !authenticate_user(@confirm_username, @confirm_password) && deactivating_own_account
    session[:error] = "Please check your credentials and try again."
  end

  if @confirm_username != @deactivate_user.username && deactivating_on_behalf
    session[:error] = "Please ensure you enter the correct username."
  end

  unless @understand_check
    session[:error] = "Please verify that you understand deactivated accounts are not recoverable."
  end

  redirect "/users/#{@deactivate_user.username}/deactivate_account" if session[:error]

  case @deactivate_user.role
  when :patient
    unless verify_user_access(min_authorization: :patient, required_username: params[:username])
      redirect "/access_error"
    end

  when :therapist
    unless verify_user_access(min_authorization: :admin)
      redirect "/access_error"
    end

  when :admin
    unless verify_user_access(min_authorization: :admin)
      redirect "/access_error"
    end

    # need at least one admin account
    if Admin.get_all.size <= 1
      session[:error] = "At least 1 Admin account need to exist. Cannot delete final Admin account."
      redirect "/users/#{session[:user].username}/admin_dashboard"
    end
  end

  session.delete(:user) if deactivating_own_account

  logger.info "#{logged_in_user} deactivates #{@deactivate_user.role.to_s} account #{full_name_plus_username(@deactivate_user)}"

  # mark account deactivated from storage
  @deactivate_user.deactivate

  session[:warning] = "Account '#{@deactivate_user.username}' has been deactivated."
  redirect_to_home_page(session[:user])
end

# email account verification for new accounts
get "/users/:username/activate" do
  @token = params[:token]

  @user = User.get(params[:username])

  redirect_to_home_page(@user) if @user.account_activated

  if @user.activation_token_expiry <= Time.now || @user.activation_token.nil?
    session[:error] = "The activation link has expired. Please request a new one on your Profile page."
    @user.activation_token = nil
    halt erb(:'accounts/activate_account')
  end

  if @user.activation_token == @token
    @user.account_activated = true
    @user.activation_token = nil
    @user.activation_token_expiry = nil

    session[:success] = "Account successfully verified."
    @user.save

    if session[:user] && session[:user].username == params[:username] # already logged in
      redirect_to_home_page(@user)
    else
      redirect "/login"
    end
  else
    session[:error] = "The activation link is not valid. You may request a new link on your <a href='/users/#{params[:username]}/profile'>Profile</a> page."
    halt erb(:'accounts/activate_account')
  end
end

get "/new_account" do

  logger.info "#{logged_in_user} displays new account creation page"
  erb :'accounts/new_account'
end

post "/new_account" do
  @username = params[:username].strip.downcase if params[:username]
  @email = params[:email].strip
  @first_name = params[:first_name].strip
  @last_name = params[:last_name].strip
  @password = params[:password]
  @confirm_password = params[:confirm_password]
  @role = params[:role].strip
  @hashed_pw = BCrypt::Password.create(@password)

  unless params[:chkbox_agree_terms]
    session[:error] = "Please read and agree to <a href='/terms'>Terms of Service</a> and <a href='/privacy_policy'>Privacy Policy</a> to create an account."
    halt erb(:'accounts/new_account')
  end

  if invalid_username(@username)
    session[:error] = "Username can only contain letters, numbers and/or '_' (underscore) and '-' (hyphen) characters."
    halt erb(:'accounts/new_account')
  end

  if invalid_name(@first_name) || invalid_name(@last_name)
    session[:error] = "Names can only contain letters and/or numbers."
    halt erb(:'accounts/new_account')
  end

  if @password != @confirm_password
    session[:error] = "Please correctly confirm your password."
    halt erb(:'accounts/new_account')
  end

  if @role == 'patient'
    @new_user = Patient.new(@username, @hashed_pw)
  elsif @role == 'therapist'
    unless verify_user_access(min_authorization: :admin)
      redirect "/access_error"
    end

    @new_user = Therapist.new(@username, @hashed_pw)
  elsif @role == 'admin'
    unless verify_user_access(min_authorization: :admin)
      redirect "/access_error"
    end

    @new_user = Admin.new(@username, @hashed_pw)
  else # no role chosen
    session[:error] = "Please choose a role."
    halt erb(:'accounts/new_account')
  end

  @new_user.email = @email
  @new_user.first_name = @first_name
  @new_user.last_name = @last_name
  @new_user.change_pw_next_login = true if params[:prompt_change_pw]

  if User.exists?(@username)
    session[:error] = "Username already exists. Please pick another."

    halt erb(:'accounts/new_account')
  end

  logger.info "#{logged_in_user} creates #{@new_user.role.to_s} account for #{full_name_plus_username(@new_user)}"

  # verify patient accounts
  if @role = 'patient'
    response = @new_user.send_account_verification_email
    logger.info "email api response: #{response.status_code}\n body: #{response.body}\n headers: #{response.headers}"
  end

  @new_user.save

  # session[:success] = "Account #{@username} has been created."

  if session[:user]
    redirect_to_home_page(session[:user])
  else
    # redirect "/login"
    erb :'accounts/await_verification'
  end
end

post "/users/:username/profile/update" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @user = User.get(params[:username])
  @current_password = params[:current_password]

  @first_name = params[:first_name]
  @last_name = params[:last_name]

  if invalid_name(@first_name) || invalid_name(@last_name)
    session[:error] = "Names can only contain letters and/or numbers."
    halt erb(:'accounts/profile')
  end

  if authenticate_user(@user.username, @current_password) || session[:user].role == :admin

    # disallow edit of admin's personal details by another admin
    if (session[:user].role != :admin) || (session[:user].role == :admin && session[:user].username == @user.username)
      @user.first_name = @first_name
      @user.last_name = @last_name
      @user.email = params[:email]
    else
      session[:error] = "Editing of another admin's personal details is disallowed."
      halt erb(:'accounts/profile')
    end

    @new_role = params[:role].to_sym
    @new_password = params[:new_password]
    @confirm_new_password = params[:confirm_new_password]

    # change pw
    unless @new_password == ""
      if @new_password == @confirm_new_password
        @hashed_new_pw = BCrypt::Password.create(@new_password)
        @user.pw = @hashed_new_pw
        @user.change_pw_next_login = false
      else
        session[:error] = "Please correctly confirm your new password."
        halt erb(:'accounts/profile')
      end
    end

    # change role enabled only for admins
    if @user.role != @new_role && session[:user].role == :admin
      case @new_role
      when :patient
        user_with_new_role = Patient.new(@user.username, @user.pw)
      when :therapist
        user_with_new_role = Therapist.new(@user.username, @user.pw)
      when :admin
        user_with_new_role = Admin.new(@user.username, @user.pw)
      else
        user_with_new_role = @user
      end
      user_with_new_role.copy_from(@user)
      @user = user_with_new_role
    end
  else
    session[:error] = "Current password was incorrect. Please try again."
    halt erb(:'accounts/profile')
  end

  logger.info "#{logged_in_user} updates profile"

  @user.save

  session[:success] = "Changes have been saved."
  redirect "/users/#{@user.username}/profile"
end

get "/login" do
  redirect_to_home_page(session[:user]) if session[:user]

  erb :'accounts/login', layout: :layout
end


post "/user/logout" do

  logger.info "#{logged_in_user} logs out"

  # session.delete(:user)
  session.clear

  "/login"
end

post "/login" do
  @username = params[:username].strip.downcase if params[:username]
  @password = params[:password]

  if authenticate_user(@username, @password)
    @user = User.get(@username)

    session[:user] = @user.slim

    if @user.change_pw_next_login
      session[:warning] = "Please change your password"
      redirect "/users/#{@username}/profile"
    end

    if params[:keep_signed_in]
      session.options.delete(:expire_after)
    else
      session.options[:expire_after] = 14400 # 4 hrs
    end

    @user.last_login_time = Time.now
    @user.save

    redirect_to_home_page(@user)
  else
    session[:error] = "Please check your details and try again."
    halt erb(:'accounts/login')
  end
end


get "/users/:username/profile" do
  @user = User.get(params[:username])

  # disallow a therapist to view profile of other therapists or admins, but allow admins to view profile of other admins
  unless verify_user_access(min_authorization: @user.role, required_username: params[:username])
    redirect "/access_error"
  end

  erb :'accounts/profile'
end

# re-send account email verification link
post "/users/:username/resend-activation" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @user = User.get(params[:username])
  @user.create_activation_token
  response = @user.send_account_verification_email

  logger.info "#{logged_in_user} re-requests activation link for #{params[:username]}"
  logger.info "email api response: #{response.status_code}\n body: #{response.body}\n headers: #{response.headers}"
  @user.save

  session[:success] = "Account verification link has been sent. Please activate within 24 hours to complete registration."
  redirect "/users/#{params[:username]}/profile"
end