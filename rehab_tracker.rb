require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "sinatra/content_for"
require 'yaml/store'
require 'date'
require 'bcrypt'
require 'fileutils'
require 'pry-byebug'
require 'chartkick'
require 'net/http'
require 'json'

require_relative 'custom_classes'

ROLES = [:public, :patient, :therapist, :admin]
STAFF_ROLES = [:therapist, :admin]

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def nil_or_empty?(value)
  value.nil? || value.empty?
end

def public_path
  File.expand_path("../public", __FILE__)
end

def create_test_patient_flora
  flora = Patient.new('flora_username', 'secret')
  bridge_for_flora = Exercise.new('bridge', 30, flora)
  bridge_for_flora.record_of_days = [Date.today-1, Date.today - 3]
  plank_for_flora = Exercise.new('plank', 3, flora)
  plank_for_flora.record_of_days = [Date.today, Date.today - 2]
  plank_for_flora.duration = '30 seconds'


  flora.exercises.push(bridge_for_flora)
  flora.exercises.push(plank_for_flora)



  flora
end

# returns array of dates of past 'n' days starting from given date (as Date object)
def past_num_days(num: 7, from:)
  result = []
    (num).times do |n|
      result.unshift(from - n)
    end
  result
end

# Routes -----------------------------------------------------------

configure do
  enable :sessions
  set :session_secret, "secret"
end

helpers do
  def format_date(date)
    date.strftime("%a %d/%m")
  end

  def address_user(user)
    user.first_name || user.username
  end

  def full_name_plus_username(user)
    if nil_or_empty?(user.full_name)
      user.username
    else
      user.full_name + ' (@' + user.username + ')'
    end
  end

  def check_value(test_date, dates_ary)
    "checked" if dates_ary.include?(test_date)
  end

  def reps_and_sets_str(exercise)
    reps_str = "#{exercise.reps} " + (exercise.reps.to_i > 1 ? "reps" : "rep") unless exercise.reps.to_s.empty?
    sets_str = "#{exercise.sets} " + (exercise.sets.to_i > 1 ? "sets" : "set") unless exercise.sets.to_s.empty?
    [reps_str, sets_str].compact.join(", ")
  end

  def active_class(test_path)
    "active" if request.path_info == test_path
  end
end

get "/weather" do
  url = "https://api.openweathermap.org/data/2.5/weather?id=2147714&appid=a987a5af5f795697f65534eeb4c91f39&units=metric"
  uri = URI(url)
  response = Net::HTTP.get(uri)
  @data = JSON.parse(response)
  @weather_icon_url = "http://openweathermap.org/img/wn/#{@data['weather'][0]['icon']}@2x.png"
  @cur_time = Time.now.strftime("%d/%m %a %I:%M %p")

  weather_btn_popover_content = <<-HEREDOC
  <div class="text-center">
  <p>#{@cur_time}</p>
  <img width="120px" height="120px" id="wicon"  src="#{@weather_icon_url}" alt="Weather icon">
  <p>#{ @data['weather'][0]['description'] }</p>
  <hr>
  <p>Current Temp: #{@data['main']['temp']} °C</p>
  <p>Max Temp: #{@data['main']['temp_max']} °C</p>
  <p>Min Temp: #{@data['main']['temp_min']} °C</p>

  </div>
  HEREDOC

end

get "/" do

  # store = YAML::Store.new("./flora.store")
  # store.transaction do
  #   store['patient_info'] = create_test_patient_flora
  # end

  redirect_to_home_page(session[:user])

  # Amazon_AWS.upload("./flora.store")
  # @dates = past_num_days(from: Date.today)
  # @patient = create_test_patient_flora
  # erb :tracker, layout: :layout
end

def user_role(user_obj)
  if user_obj.is_a?(Patient)
    :patient
  elsif user_obj.is_a?(Therapist)
    :therapist
  elsif user_obj.is_a?(Admin)
    :admin
  end
end

not_found do
  erb :custom_404
end

get "/users/:username/exercises" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.today

  @dates = past_num_days(from: @end_date)
  @patient = get_user_obj(params[:username])
  erb :tracker
end

# add exercise for patient from library
get "/users/:username/exercises/add_from_library" do
  @patient = get_user_obj(params[:username])

  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  erb :exercise_library
end

# display page for creating exercise template
get "/exercise_library/add_template" do
  @patient = get_user_obj(params[:pt]) if params[:pt]

  @new_template = true

  erb :new_exercise_template
end

# add exercise template
post "/exercise_library/add_template" do

end

# display exercise template edit page
get "/exercise_library/:template_name/edit" do


  erb :edit_exercise_template
end

# edit exercise template
post "/exercise_library/:template_name/edit" do

end

# delete exercise template
post "/exercise_library/:template_name/delete" do

end


post "/users/:username/exercises/add" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = get_user_obj(params[:username])
  @new_exercise_name = params[:new_exercise_name]

  # validate exercise name
  raise ExerciseTemplate::ExerciseNameNotUniqueErr if @patient.has_exercise(@new_exercise_name)

  @patient.add_exercise(params[:new_exercise_name])

  save_user_obj(@patient)

  redirect "/users/#{@patient.username}/exercises"

  rescue ExerciseTemplate::ExerciseNameNotUniqueErr
    session[:error] = "An exercise called '#{@new_exercise_name}' already exists. Please pick a new name."
    redirect "/users/#{@patient.username}/exercises"
end

get "/users/:username/exercises/:exercise_name/edit" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = get_user_obj(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  erb :edit_exercise
end

def delete_file(path)
  FileUtils.rm(path)
end

# upload image or other files associated with an exercise for a patient
post "/users/:username/exercises/:exercise_name/upload_file" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = get_user_obj(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])

  params[:images].each do |file_hash|
    dest_path = File.join(public_path + "/images/#{params[:username]}/#{params[:exercise_name]}", file_hash[:filename])
    upload_file(source: file_hash[:tempfile], dest: dest_path)

    if @exercise.has_file(file_hash[:filename]) # image with same name already exists
      session[:error] = "This exercise already has an image called '#{file_hash[:filename]}'. Please upload an image with a different name."
      redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
    end

    if @exercise.num_files >= ExerciseTemplate::FILES_LIMIT
      session[:error] = "Each exercise can only contain #{ExerciseTemplate::FILES_LIMIT} files."
      redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
    end

    image_link = File.join("/images/#{params[:username]}/#{params[:exercise_name]}", file_hash[:filename])

    @exercise.image_links.push(image_link)
    save_user_obj(@patient)
  end

  # todo: validate file sizes
  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
end

get "/users/:username/deactivate_account" do
  @deactivate_user = get_user_obj(params[:username])

  if @deactivate_user.username == session[:user].username
    if @deactivate_user.role == :therapist
      @message = "Dear #{address_user(@deactivate_user)}, thank you for looking after your patients. Take care!"
    elsif @deactivate_user.role == :patient
      @message = "Dear #{address_user(@deactivate_user)}, we sincerely hope that Rehab Buddy has helped you along the way. Take care!"
    end
    erb :deactivate_account_own
  else
    erb :deactivate_account_on_behalf
  end
end

post "/users/:username/deactivate_account" do
  @deactivate_user = get_user_obj(params[:username])
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
    unless verify_user_access(required_authorization: :patient, required_username: params[:username])
      redirect "/access_error"
    end

  when :therapist, :admin
    unless verify_user_access(required_authorization: :admin)
      redirect "/access_error"
    end
  end

  # need at least one admin account
  if get_all_admins.size <= 1
    session[:error] = "At least 1 Admin account need to exist."
    redirect "/users/#{session[:user].username}/admin_panel"
  end

  session.delete(:user) if deactivating_own_account

  # delete account from storage
  deactivate_user_obj(@deactivate_user)

  session[:warning] = "Account '#{@deactivate_user.username}' has been deactivated."
  redirect_to_home_page(session[:user])
end

# Save exercise details
post "/users/:username/exercises/:exercise_name/update" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = get_user_obj(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  @exercise.name = params[:new_exercise_name]
  @exercise.reps = params[:reps]
  @exercise.sets = params[:sets]
  @exercise.instructions = params[:instructions]
  @exercise.comment_by_patient = params[:patient_comment]
  @exercise.comment_by_therapist = params[:therapist_comment]

  save_user_obj(@patient)

  session[:success] = "Your changes have been saved"
  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
end

get "/about" do

  erb :about
end

# delete exercise for patient
post "/users/:username/exercises/:exercise_name/delete" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = get_user_obj(params[:username])

  @patient.delete_exercise(params[:exercise_name])

  save_user_obj(@patient)

  redirect "/users/#{@patient.username}/exercises"
end

# Delete file associated with exercise
post "/users/:username/exercises/:exercise_name/delete_file" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = get_user_obj(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  @file_path = params[:file_path]

  if @exercise.image_links.delete(@file_path)
    save_user_obj(@patient)
    filename = File.basename(@file_path)
    delete_file(public_path + "/images/#{params[:username]}/#{params[:exercise_name]}/#{filename}")
    session[:success] = "File succcessfuly removed"
  else
    session[:error] = "File does not exist"
  end


  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
end

post "/users/:username/exercises/mark_all" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = get_user_obj(params[:username])
  @mark_date = params[:date]
  @mark_all_done = params[:select_all_none]

  if @mark_all_done
    @patient.mark_done_all_exercises(@mark_date)
  else
    @patient.mark_undone_all_exercises(@mark_date)
  end

  save_user_obj(@patient)

  redirect "/users/#{@patient.username}/exercises"
end

# update checkbox values for a particular exercise and day for a patient
post "/users/:username/update_tracker" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = get_user_obj(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  @check_date = params[:date]
  @ticked = params[:checkbox_value]

  if @ticked
    @exercise.add_date(@check_date)
  else
    @exercise.delete_date(@check_date)
  end

  save_user_obj(@patient)

  # result = "updating #{@exercise_name} for #{params[:username]}. Date is #{@check_date}. Tick value is #{!!@ticked}"



  # if params[:example1]
  #   "checked, exercise_id=#{params[:exercise_id]}"
  # else
  #   "not checked, exercise_id=#{params[:exercise_id]}"
  # end

  redirect "/users/#{@patient.username}/exercises"
end

# post "/upload" do
#   file_hashes = params['images']
#   filenames = params['images'].map { |f| f[:name] }.join(";")

#   filenames = filenames.split(";")
#   num_files = filenames.length

#   file_hashes.each do |file_h|
#     file = file_h[:tempfile]
#     File.open("./uploaded_#{file_h[:filename]}", "wb") do |f|
#       f.write file.read
#     end
#   end

#    # params['images'].inspect
# end

# post "/save_changes_tracker" do
#   "result_of_ajax"
# end

get "/new_account" do
  erb :new_account
end

post "/new_account" do
  @username = params[:username]
  @email = params[:email]
  @first_name = params[:first_name]
  @last_name = params[:last_name]
  @password = params[:password]
  @role = params[:role]
  @hashed_pw = BCrypt::Password.create(@password)

  if @role == 'patient'
    new_user = Patient.new(@username, @hashed_pw)
  elsif @role == 'therapist'
    unless verify_user_access(required_authorization: :admin)
      redirect "/access_error"
    end

    new_user = Therapist.new(@username, @hashed_pw)
  elsif @role = 'admin'
    unless verify_user_access(required_authorization: :admin)
      redirect "/access_error"
    end

    new_user = Admin.new(@username, @hashed_pw)
  else # no role chosen
    session[:error] = "Please choose a role."
    halt erb(:new_account)
  end

  new_user.email = @email
  new_user.first_name = @first_name
  new_user.last_name = @last_name
  new_user.change_pw_next_login = true if params[:prompt_change_pw]

  if user_exists?(@username)
    session[:error] = "Username already exists. Please pick another."

    halt erb(:new_account)
  end

  save_user_obj(new_user)
  # store = YAML::Store.new("./data/#{@username}.store")
  # store.transaction do
  #   store[:data] = new_user

  #   # if user_records.key?(@username.to_sym)
  #   #   session[:error] = "Username already exists. Please pick another."

  #   #   halt erb(:new_account)
  #   # end

  #   # user_record[:data] = new_user
  #   # store[:users] = user_records
  # end

  session[:success] = "Account #{@username} has been created"
  redirect_to_home_page(session[:user])
end


post "/users/:username/profile/update" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @user = get_user_obj(params[:username])
  @current_password = params[:current_password]

  if authenticate_user(@user.username, @current_password) || session[:user].role == :admin

    @user.first_name = params[:first_name]
    @user.last_name = params[:last_name]
    @user.email = params[:email]

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
        halt erb(:profile)
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
    halt erb(:profile)
  end

  save_user_obj(@user)

  session[:success] = "Changes have been saved."
  redirect "/users/#{@user.username}/profile"
end

get "/login" do
  erb :login, layout: :layout
end


post "/user/logout" do
  session.delete(:user)

  "/login"
end

def home_page_for(user)
  return "/login" unless user

  case user.role
    when :patient
      "/users/#{user.username}/exercises"
    when :therapist
      "/patient_list"
    when :admin
      "/users/#{user.username}/admin_panel"
  end
end

def redirect_to_home_page(user)
  redirect home_page_for(user)
end

post "/login" do
  @username = params[:username]
  @password = params[:password]

  if authenticate_user(@username, @password)
    @user = get_user_obj(@username)

    session[:user] = @user

    if @user.change_pw_next_login
      session[:warning] = "Please change your password"
      redirect "/users/#{@username}/profile"
    end

    redirect_to_home_page(@user)
  else
    session[:error] = "Please check your details and try again."
    halt erb(:login)
  end
end

get "/users/:username/admin_panel" do
  unless verify_user_access(required_authorization: :admin)
    redirect "/access_error"
  end
  @user = get_user_obj(params[:username])
  @all_patients = get_all_patients
  @all_therapists = get_all_therapists
  @all_admins = get_all_admins

  erb :admin_panel
end

def user_exists?(username)
  File.exists?("./data/#{username}.store")
end

# returns true only if username exists and password is valid
def authenticate_user(username, test_pw)
  user = get_user_obj(username) # returns nil if user_exists? == false
  user && BCrypt::Password.new(user.pw) == test_pw
end

def get_user_obj(username)
  return nil unless user_exists?(username)

  user_obj = nil
  store = YAML::Store.new("./data/#{username}.store")
  store.transaction do
    user_obj = store[:data]
  end
  user_obj
end

def save_user_obj(user)
  store = YAML::Store.new("./data/#{user.username}.store")
  store.transaction do
    store[:data] = user
  end
end

def deactivate_user_obj(user)
  user.account_status = :deactivated

  # move user file + image file folder to deactivated folder

  save_user_obj(user)
end

def save_exercises(patient)
  store = YAML::Store.new("./data/patient/#{patient.username}.store")
  store.transaction do
    store[:data][:exercises] = patient.exercises
  end
end

def verify_user_access(required_authorization: :public, required_username: nil)
  return false unless session[:user] || required_authorization == :public

  session_role = session[:user].role if session[:user]
  current_role = session_role || :public

  access_level_diff = ROLES.index(current_role) - ROLES.index(required_authorization)
  role_ok = access_level_diff >= 0
  username_ok = if required_username
                  session[:user].username == required_username ||
                    access_level_diff > 0
                 # if required_username is provided, access is only granted
                 # if username matches, OR logged-in user has higher access level than required
                else
                  true
                end

  role_ok && username_ok
end

get "/access_error" do
  erb :access_error
end

get "/patient_list" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end
  @user = session[:user]
  @all_patients = get_all_patients
  erb :patient_list
end

get "/users/:username/profile" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @user = get_user_obj(params[:username])

  erb :profile
end

get "/users/:username/stats" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end



  @patient = get_user_obj(params[:username])
  erb :stats
  # @patient.exercise_completion_rates_by_day.inspect
  # rate = @patient.num_of_exercises_done_on('20200501') / @patient.num_of_exercises.to_f
  # rate.to_s
end

# returns array of all user data objects
def get_all_users
  files = Dir.glob("./data/**/*.store")

  result = []
  files.each do |file_path|
    contents = YAML.load(File.read(file_path))
    user_obj = contents[:data]
    result.push(user_obj) unless user_obj.account_status == :deactivated
  end
  result
end

def get_all_patients
  get_all_users.select { |user| user_role(user) == :patient }
end

def get_all_therapists
  get_all_users.select { |user| user_role(user) == :therapist }
end

def get_all_admins
  get_all_users.select { |user| user_role(user) == :admin }
end

def upload_file(source:, dest:)
  # create directory if doesn't exist
  dir_name = File.dirname(dest)

  unless File.directory?(dir_name)
    FileUtils.mkdir_p(dir_name)
  end

  FileUtils.cp(source, dest)
end

