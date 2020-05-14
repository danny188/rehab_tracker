require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "sinatra/content_for"
require 'date'
require 'bcrypt'
require 'pry-byebug'
require 'chartkick'
require 'net/http'
require 'json'

require_relative 'custom_classes'

ENV['custom_env'] = 'testing_s3'

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
  @patient = User.get(params[:username])
  erb :tracker
end

# add exercise for patient from library
get "/users/:username/exercises/add_from_library" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  exercise_library = ExerciseLibrary.load('main')
  @all_templates = exercise_library.get_all_templates

  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  erb :exercise_library
end

# add selected template as exercise for a patient
post "/users/:username/exercises/add_from_library" do

  patient = User.get(params[:username])
  exercise_library = ExerciseLibrary.load('main')
  template = exercise_library.get_template(params[:template_name])

  exercise = Exercise.new_from_template(template)

  if patient.has_exercise(template.name)
    session[:error] = "#{full_name_plus_username(patient)} already has an exercise called '#{template.name}'. Please change either the name of the template or the patient's exercise."
    redirect "/users/#{patient.username}/exercises/add_from_library"
  end

  patient.add_exercise(exercise)

  patient.save

  # # session[:success] = "Successfully added template #{template.name} for #{full_name_plus_username(patient)}"
  # session[:toast_title] = "Template Added"
  # session[:toast] = "Successfully added template #{template.name} for #{full_name_plus_username(patient)}"
  { toast_title: "Template Added",
    toast_msg: "Successfully added template #{template.name} for #{full_name_plus_username(patient)}" }.to_json
  end

# display page for creating exercise template
get "/exercise_library/add_template" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @patient = User.get(params[:pt]) if params[:pt]

  @new_template = true

  erb :new_exercise_template
end

# add exercise template
post "/exercise_library/add_template" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @new_template_name = params[:new_template_name].to_s.strip

  @template = ExerciseTemplate.new(@new_template_name, params[:reps], params[:sets])
  @template.instructions = params[:instructions]

  exercise_library = ExerciseLibrary.load('main')

  if exercise_library.has_template?(@new_template_name)
    session[:error] = "Exercise Library already has a template named '#{@new_template_name}'. Please choose another name."
    halt erb(:new_exercise_template)
  end

  if @new_template_name.empty?
    session[:error] = "Template name cannot be empty."
    halt erb(:new_exercise_template)
  end

  exercise_library.add_template(@template)
  exercise_library.save

  redirect "/exercise_library/#{@template.name}/edit"
end

# display exercise template edit page
get "/exercise_library/:template_name/edit" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  exercise_library = ExerciseLibrary.load('main')
  @template = exercise_library.get_template(params[:template_name])

  unless @template # requested template not found
    session[:error] = "Exercise template '#{params[:template_name]}' not found."
    if @patient
      redirect "/users/#{@patient.username}/exercises/add_from_library"
    else
      redirect "/exercise_library"
    end
  end

  erb :edit_exercise_template
end

get "/exercise_library" do

  exercise_library = ExerciseLibrary.load('main')
  @all_templates = exercise_library.get_all_templates


  erb :exercise_library

end

# edit exercise template
post "/exercise_library/:template_name/edit" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  exercise_library = ExerciseLibrary.load('main')
  @template = exercise_library.get_template(params[:template_name])
  @new_template_name = params[:new_template_name].strip

  @template.reps = params[:reps]
  @template.sets = params[:sets]
  @template.instructions = params[:instructions]

  # ensuring not changing name to clash with another existing template
  if exercise_library.has_template?(@new_template_name) && @new_template_name != @template.name
    session[:error] = "Exercise Library already has a template named '#{@new_template_name}'. Please choose another name."
    halt erb(:edit_exercise_template)
  end

  @template.name = @new_template_name

  exercise_library.save

  redirect "/exercise_library/#{@template.name}/edit"
end

# delete exercise template
post "/exercise_library/:template_name/delete" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  exercise_library = ExerciseLibrary.load('main')
  @delete_template = exercise_library.get_template(params[:template_name])

  exercise_library.delete_template(@delete_template)

  exercise_library.save

  if params[:pt]
    redirect "/users/#{params[:pt]}/exercises/add_from_library"
  else
    redirect "/exercise_library"
  end
end

def remove_trailing_nils_and_emptys(ary)
  until (!ary[-1].nil? && !ary[-1].empty?) || ary.empty?
    ary.pop
  end
end

def group_hierarchy(*groups)
  remove_trailing_nils_and_emptys(groups)
  groups.unshift(GroupOperations::TOP_GROUP) if groups[0] != GroupOperations::TOP_GROUP
  groups
end

post "/users/:username/exercises/add" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @new_exercise_name = params[:new_exercise_name].strip
  @group_name = params[:group].strip


  # validate exercise name
  raise GroupOperations::ItemNameInGroupNotUniqueErr if @patient.has_exercise(@new_exercise_name, group_hierarchy(@group_name))

  raise GroupOperations::ItemNameEmpty if @new_exercise_name.empty?

  @patient.add_exercise_by_name(params[:new_exercise_name], group_hierarchy(@group_name))

  @patient.save

  redirect "/users/#{@patient.username}/exercises"

rescue GroupOperations::ItemNameInGroupNotUniqueErr
  session[:error] = "An exercise called '#{@new_exercise_name}' already exists. Please pick a new name."
  redirect "/users/#{@patient.username}/exercises"
rescue GroupOperations::ItemNameEmpty
  session[:error] = "Exercise name cannot be blank"
  redirect "/users/#{@patient.username}/exercises"
end

get "/users/:username/exercises/:exercise_name/edit" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  erb :edit_exercise
end

def delete_local_file(path)
  FileUtils.rm(path)
end

# upload image/files for exercise template
post "/exercise_library/:template_name/upload_file" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  exercise_library = ExerciseLibrary.load('main')
  template = exercise_library.get_template(params[:template_name])

  params[:images].each do |file_hash|
    if template.has_file(file_hash[:filename])
      session[:error] = "This template already has an image called '#{file_hash[:filename]}'. Please upload an image with a different name."
      redirect "/exercise_library/#{template.name}/edit"
    end

    if template.num_files >= ExerciseTemplate::FILES_LIMIT
      session[:error] = "Each template can only contain #{ExerciseTemplate::FILES_LIMIT} files."
      redirect "/exercise_library/#{template.name}/edit"
    end

    template.add_file(file: file_hash[:tempfile], filename: file_hash[:filename])
    exercise_library.save
  end

  redirect "/exercise_library/#{template.name}/edit#{'?pt=' + params[:pt] if params[:pt]}"
end

# upload image or other files associated with an exercise for a patient
post "/users/:username/exercises/:exercise_name/upload_file" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])

  params[:images].each do |file_hash|
    # dest_path = File.join(public_path + "/images/#{params[:username]}/#{params[:exercise_name]}", file_hash[:filename])

    if @exercise.has_file(file_hash[:filename]) # image with same name already exists
      session[:error] = "This exercise already has an image called '#{file_hash[:filename]}'. Please upload an image with a different name."
      redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
    end

    if @exercise.num_files >= ExerciseTemplate::FILES_LIMIT
      session[:error] = "Each exercise can only contain #{ExerciseTemplate::FILES_LIMIT} files."
      redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
    end

    # upload_file(source: file_hash[:tempfile], dest: dest_path)
    # image_link = File.join("/images/#{params[:username]}/#{params[:exercise_name]}", file_hash[:filename])

    # @exercise.add_file_link(image_link)
    @exercise.add_file(file: file_hash[:tempfile], filename: file_hash[:filename])
    @patient.save
  end

  # todo: validate file sizes
  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
end

get "/users/:username/deactivate_account" do
  @deactivate_user = User.get(params[:username])

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
    unless verify_user_access(required_authorization: :patient, required_username: params[:username])
      redirect "/access_error"
    end

  when :therapist
    unless verify_user_access(required_authorization: :admin)
      redirect "/access_error"
    end

  when :admin
    unless verify_user_access(required_authorization: :admin)
      redirect "/access_error"
    end

    # need at least one admin account
    if Admin.get_all.size <= 1
      session[:error] = "At least 1 Admin account need to exist. Cannot delete last Admin account."
      redirect "/users/#{session[:user].username}/admin_panel"
    end
  end

  session.delete(:user) if deactivating_own_account

  # delete account from storage
  @deactivate_user.deactivate

  session[:warning] = "Account '#{@deactivate_user.username}' has been deactivated."
  redirect_to_home_page(session[:user])
end

# Save exercise details
post "/users/:username/exercises/:exercise_name/update" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  @exercise.reps = params[:reps]
  @exercise.sets = params[:sets]
  @exercise.instructions = params[:instructions]
  @exercise.comment_by_patient = params[:patient_comment]
  @exercise.comment_by_therapist = params[:therapist_comment]

  # validate exercise name
  exercise_name_not_unique = @patient.has_exercise(params[:new_exercise_name]) && @exercise.name != params[:new_exercise_name]

  raise ExerciseTemplate::ExerciseNameNotUniqueErr if exercise_name_not_unique

  @exercise.name = params[:new_exercise_name]

  @patient.save

  session[:success] = "Your changes have been saved"
  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"

rescue ExerciseTemplate::ExerciseNameNotUniqueErr
  session[:error] = "An exercise called '#{@new_exercise_name}' already exists. Please pick a new name."
  halt erb(:edit_exercise)
end

get "/about" do

  erb :about
end

# delete exercise for patient
post "/users/:username/exercises/:exercise_name/delete" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  @patient.delete_exercise(params[:exercise_name])

  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

# Delete file associated with exercise
post "/users/:username/exercises/:exercise_name/delete_file" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  @file_path = params[:file_path]
  filename = File.basename(@file_path)

  if @exercise.has_file(filename)
    # delete_file(public_path + "/images/#{params[:username]}/#{params[:exercise_name]}/#{filename}")
    @exercise.delete_file(link: @file_path)
    @patient.save
    session[:success] = "File succcessfuly removed"
  else
    session[:error] = "File does not exist"
  end

  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit"
end

# Delete file associated with exercise template
post "/exercise_library/:template_name/delete_file" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  exercise_library = ExerciseLibrary.load('main')
  template = exercise_library.get_template(params[:template_name])
  @file_path = params[:file_path]
  filename = File.basename(@file_path)

  if template.has_file(filename)
    template.delete_file(@file_path)
    exercise_library.save
    session[:success] = "File succcessfuly removed"
  else
    session[:error] = "File does not exist"
  end

  redirect "/exercise_library/#{template.name}/edit#{'?pt=' + params[:pt] if params[:pt]}"
end

post "/users/:username/exercises/mark_all" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @mark_date = params[:date]
  @mark_all_done = params[:select_all_none]

  if @mark_all_done
    @patient.mark_done_all_exercises(@mark_date)
  else
    @patient.mark_undone_all_exercises(@mark_date)
  end

  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

# update checkbox values for a particular exercise and day for a patient
post "/users/:username/update_tracker" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @exercise = @patient.get_exercise(params[:exercise_name])
  @check_date = params[:date]
  @ticked = params[:checkbox_value]

  if @ticked
    @exercise.add_date(@check_date)
  else
    @exercise.delete_date(@check_date)
  end

  @patient.save

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
  elsif @role == 'admin'
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



  if User.exists?(@username)
    session[:error] = "Username already exists. Please pick another."

    halt erb(:new_account)
  end

  new_user.save
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

  @user = User.get(params[:username])
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

  @user.save

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
    @user = User.get(@username)

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
  @user = User.get(params[:username])
  @all_patients = Patient.get_all
  @all_therapists = Therapist.get_all
  @all_admins = Admin.get_all

  erb :admin_panel
end



# returns true only if username exists and password is valid
def authenticate_user(username, test_pw)
  user = User.get(username) # returns nil if user_exists? == false
  user && BCrypt::Password.new(user.pw) == test_pw
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
              @all_patients = Patient.get_all
              erb :patient_list
            end

            get "/users/:username/profile" do
              unless verify_user_access(required_authorization: :patient, required_username: params[:username])
                redirect "/access_error"
              end

              @user = User.get(params[:username])

              erb :profile
            end

            get "/users/:username/stats" do
              unless verify_user_access(required_authorization: :patient, required_username: params[:username])
                redirect "/access_error"
              end



              @patient = User.get(params[:username])
              erb :stats
  # @patient.exercise_completion_rates_by_day.inspect
  # rate = @patient.num_of_exercises_done_on('20200501') / @patient.num_of_exercises.to_f
  # rate.to_s
end

def upload_file(source:, dest:)
  # create directory if doesn't exist
  dir_name = File.dirname(dest)

  unless File.directory?(dir_name)
    FileUtils.mkdir_p(dir_name)
  end

  FileUtils.cp(source, dest)
end

# get "/users/:username/exercises/add_group" do
#   @patient = User.get(params[:username])

#   erb :add_exercise_group
# end

post "/users/:username/exercises/add_group" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  @new_group_name = params[:group].strip

  if @patient.subgroup_exists?(@new_group_name, Patient::TOP_HIERARCHY)
    session[:error] = "A group called #{@new_group_name} already exists."
    erb :tracker
  end

  if @new_group_name.empty?
    session[:error] = "Group name cannot be blank."
    erb :tracker
  end

  @patient.add_subgroup(@new_group_name, Patient::TOP_HIERARCHY)
  @patient.save
  redirect "/users/#{@patient.username}/exercises"
end

post "/users/:username/exercises/group/:delete_group/delete" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  delete_group_name = params[:delete_group]

  @patient.delete_subgroup(delete_group_name, group_hierarchy)

  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

get "/test" do
  # patient = Amazon_AWS.download_obj(key: 'starfish.store', bucket: :data)

  # patient = User.get('starfish')

  # patient.first_name

  # Amazon_AWS.s3_env

  # ary = Amazon_AWS.download_all_objs(bucket: :data, prefix: 'user_')
  # YAML.load(ary[0]).first_name
  # Amazon_AWS.copy_obj(source_bucket: :images, target_bucket: :images,
  #   source_key: "girl.png", target_key: "girl_copied.png")
  @patient = User.get('pineapple')

  @patient.get_groups(['main']).map(&:name).inspect
  # @patient.get_group(['main', 'stretches']).items.inspect
main_grp = @patient.get_group(['main']).name


end