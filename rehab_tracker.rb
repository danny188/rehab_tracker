require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "sinatra/content_for"
require 'yaml/store'
require 'date'
require 'bcrypt'
require 'fileutils'
require 'pry-byebug'

require_relative 'custom_classes'

ROLES = [:public, :patient, :therapist, :admin]

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
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

  def check_value(test_date, dates_ary)
    "checked" if dates_ary.include?(test_date)
  end
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



get "/users/:username/exercises" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.today

  @dates = past_num_days(from: @end_date)
  @patient = get_user_obj(params[:username])
  erb :tracker
end

# combine this into "/:username/exercises" path by using session[:user]
# signed in user can be different to :username in path if signed-in user is a therapist or admin
get "/users/:username/exercises/therapist_view" do
  @dates = past_num_days(from: Date.today)
  @patient = get_user_obj(params[:username])
  @therapist = get_user_obj('therapist_1')

  erb :tracker
end

post "/users/:username/exercises/add" do
  @patient = get_user_obj(params[:username])
  @patient.add_exercise(params[:new_exercise_name])

  save_user_obj(@patient)

  redirect "/users/#{@patient.username}/exercises"

  rescue Patient::ExerciseNameNotUniqueErr
    "exercise name already exists for patient"
end

get "/users/:username/exercises/:exercise_name/edit" do
  @patient = get_user_obj(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  erb :edit_exercise


end

def delete_file(path)
  FileUtils.rm(path)
end

post "/users/:username/exercises/:exercise_name/upload_file" do
  @patient = get_user_obj(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  params[:images].each do |file_hash|
    dest_path = File.join(public_path + "/images/#{params[:username]}/#{params[:exercise_name]}", file_hash[:filename])
    upload_file(source: file_hash[:tempfile], dest: dest_path)

    image_link = File.join("/images/#{params[:username]}/#{params[:exercise_name]}", file_hash[:filename])

    @exercise.image_links.push(image_link)
    save_user_obj(@patient)
  end

  # todo: limit file sizes and number of files uploaded per exercise
  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
end

# Save exercise details
post "/users/:username/exercises/:exercise_name/update" do
  @patient = get_user_obj(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  @exercise.name = params[:exercise_name]
  @exercise.reps = params[:reps]
  @exercise.sets = params[:sets]
  @exercise.instructions = params[:instructions]
  @exercise.comment_by_patient = params[:patient_comment]
  @exercise.comment_by_therapist = params[:therapist_comment]

  save_user_obj(@patient)

  session[:success] = "Your changes have been saved"
  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
end

# delete exercise for patient
post "/users/:username/exercises/:exercise_name/delete" do
  @patient = get_user_obj(params[:username])

  @patient.delete_exercise(params[:exercise_name])

  save_user_obj(@patient)

  redirect "/users/#{@patient.username}/exercises"
end

# Delete file associated with exercise
post "/users/:username/exercises/:exercise_name/delete_file" do
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

post "/users/:username/update_tracker" do #rename to patient_edit
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

get "/upload" do

  erb :exercise, layout: :layout
end

post "/upload" do
  file_hashes = params['images']
  filenames = params['images'].map { |f| f[:name] }.join(";")

  filenames = filenames.split(";")
  num_files = filenames.length

  file_hashes.each do |file_h|
    file = file_h[:tempfile]
    File.open("./uploaded_#{file_h[:filename]}", "wb") do |f|
      f.write file.read
    end
  end

   # params['images'].inspect
end

post "/save_changes_tracker" do
  "result_of_ajax"
end

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
    unless verify_user_access(required_authorization: :therapist)
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

  if authenticate_user(@user.username, @current_password)

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
      else
        session[:error] = "Please correctly confirm your new password."
        halt erb(:profile)
      end
      session[:warning] = "new pw was '#{@new_password}'"
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

def redirect_to_home_page(user)
  @user = user

  redirect "/login" unless @user

  case @user.role
    when :patient
      redirect "/users/#{@user.username}/exercises"
    when :therapist
      redirect "/patient_list"
    when :admin
      redirect "/users/#{@user.username}/admin_panel"
    end
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

def save_exercises(patient)
  store = YAML::Store.new("./data/patient/#{patient.username}.store")
  store.transaction do
    store[:data][:exercises] = patient.exercises
  end
end

def verify_user_access(required_authorization: :public, required_username: nil)
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


# returns array of all user data objects
def get_all_users
  files = Dir.glob("./data/**/*.store")

  result = []
  files.each do |file_path|
    contents = YAML.load(File.read(file_path))
    user_obj = contents[:data]
    result.push(user_obj)
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
  FileUtils.cp(source, dest)
end

