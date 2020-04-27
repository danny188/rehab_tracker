require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "sinatra/content_for"
require 'yaml/store'
require 'date'
require 'bcrypt'

require_relative 'custom_classes'

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

  store = YAML::Store.new("./flora.store")
  store.transaction do
    store['patient_info'] = create_test_patient_flora
  end



  # Amazon_AWS.upload("./flora.store")
  @dates = past_num_days(from: Date.today)
  @patient = create_test_patient_flora
  erb :tracker, layout: :layout
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

post "/users/:username/update_tracker" do #rename to patient_edit

  exercise_name = params[:exercise_name]
  check_date = params[:date]
  ticked = params[exercise_name.to_sym]

  result = "updating #{exercise_name} for #{params[:username]}. Date is #{check_date}. Tick value is #{!!ticked}"

  # if params[:example1]
  #   "checked, exercise_id=#{params[:exercise_id]}"
  # else
  #   "not checked, exercise_id=#{params[:exercise_id]}"
  # end

  # redirect "/"
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
    new_user = Therapist.new(@username, @hashed_pw)
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


  store = YAML::Store.new("./data/#{@username}.store")
  store.transaction do
    store[:data] = new_user

    # if user_records.key?(@username.to_sym)
    #   session[:error] = "Username already exists. Please pick another."

    #   halt erb(:new_account)
    # end

    # user_record[:data] = new_user
    # store[:users] = user_records
  end
end

get "/login" do
  erb :login
end

post "/login" do
  @username = params[:username]
  @password = params[:password]

  if authenticate_user(@username, @password)
    user = get_user_obj(@username)
    "Welcome, #{user.first_name}."
  else
    "Please check your details and try again."
  end
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
  store = YAML::Store.new("./data/#{patient.username}.store")
  store.transaction do
    store[:data][:exercises] = patient.exercises
  end
end

get "/patient_list" do
  # verify user access rights
  @user = get_user_obj('admin_1')

  @all_patients = get_all_patients
  erb :patient_list
end

# returns array of all user data objects
def get_all_users
  files = Dir.glob("./data/*.store")
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

