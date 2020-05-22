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

require_relative 'custom_classes'
include GroupOperations

# ENV['custom_env'] = 'production_s3'

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

def invalid_name(name)
  name =~ /[^a-z0-9\s]/i
end

def invalid_username(name)
  name =~ /[^-_a-z0-9\s]/i
end

# returns array of dates of past 'n' days starting from given date (as Date object)
def past_num_days(num: 7, from:)
  result = []
  (num).times do |n|
    result.unshift(from - n)
  end
  result
end

def log_date_if_therapist_doing_edit(patient)
  # record review date by therapist whenever updating patient
  if session[:user].role == :therapist
    patient.last_review_date = Date.today
    patient.last_review_by = session[:user].username
  end
end

# Routes -----------------------------------------------------------

configure do
  enable :sessions
  # set :session_secret, ENV.fetch('SINATRA_SESSION_KEY') { SecureRandom.hex(64) }
  set :session_secret, 'secret'
  set :markdown, :layout_engine => :erb
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



  def checkbox_display_class(day_idx)
    case day_idx
    when 0..1
      "d-none d-lg-block d-print-none"
    when 2..3
      "d-none d-lg-block d-print-block"
    when 4..5
      "d-none d-md-block d-print-block"
    when 6
      'd-print-block'
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

  # takes a hash query str parameter name/value pairs, returns a query str
  def create_full_query_str(param_hash)
    ary_of_query_strings = param_hash.map { |key, value| (key.to_s + '=' + value) unless value.to_s.empty? }
    '?' + ary_of_query_strings.compact.join('&')
  end

end

get "/weather" do
  url = "https://api.openweathermap.org/data/2.5/weather?id=2147714&appid=#{ENV['OPEN_WEATHER_MAP_API_KEY']}&units=metric"
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

def valid_date_str(date_str)
  date_str =~ /^(19|20)\d\d(0[1-9]|1[012])(0[1-9]|[12][0-9]|3[01])$/
end

not_found do
  erb :custom_404
end

get "/users/:username/exercises" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end
  @end_date_str = params[:end_date].strip if params[:end_date]
  @nav = params[:nav]
  @day_step = params[:day_step].to_s.to_i

  @day_step *= -1 if @nav == 'back'



  @end_date = if nil_or_empty?(@end_date_str) || !valid_date_str(@end_date_str)
                Date.today
              else
                Date.parse(@end_date_str) + @day_step
              end

  @dates = past_num_days(from: @end_date)
  @patient = User.get(params[:username])
  erb :tracker
end



get "/users/:username/exercises/print_view" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end
  @end_date_str = params[:end_date].strip if params[:end_date]

  @end_date = if nil_or_empty?(@end_date_str) || !valid_date_str(@end_date_str)
                Date.today
              else
                Date.parse(@end_date_str)
              end

  @dates = past_num_days(from: @end_date)
  @patient = User.get(params[:username])
  erb :print_view
end

def exercise_library_title(group_hierarchy)
  case group_hierarchy.size
  when 1
    "Exercise Library"
  when 2
    "Exercise Library #{'(Group: ' + group_hierarchy[1] + ')'}"
  when 3
    "Exercise Library #{'(Group: ' + group_hierarchy[1] + '/' + group_hierarchy[2] +')'}"
  end
end

# add exercise for patient from library
get "/users/:username/exercises/add_from_library" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @patient = User.get(params[:username])
  @exercise_library = ExerciseLibrary.load('main')
  @group = @exercise_library.get_group(@group_hierarchy)

  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  erb :exercise_library
end

# add selected template as exercise for a patient
post "/users/:username/exercises/add_from_library" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  @exercise_library = ExerciseLibrary.load('main')

  # group hierarchy from which we're pulling exercise template
  @group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group_hierarchy_str]))
  @exercise_template = @exercise_library.get_exercise(params[:exercise_name], @group_hierarchy)


  @exercise = Exercise.new_from_template(@exercise_template)
  @exercise.patient_username = @patient.username

  # apply exercise template to top group level of patient

  if @patient.has_exercise(@exercise_template.name, create_group_hierarchy)
    session[:error] = "#{full_name_plus_username(@patient)} already has an exercise called '#{@exercise_template.name}'. Please change either the name of the template or the patient's exercise."
    redirect "/users/#{@patient.username}/exercises/add_from_library#{create_full_query_str({group: params[:group], pt: params[:pt] })}"
  end

  # copy image files from template
  GroupOperations.replace_all_supp_files(@exercise_library, @exercise_template, @exercise)

  # session[:debug] = @exercise.image_links.inspect
  # redirect "/test"

  # exercise will be added to top group of patient's exercises
  @patient.add_exercise(@exercise, create_group_hierarchy)

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  # # session[:success] = "Successfully added template #{template.name} for #{full_name_plus_username(patient)}"
  # session[:toast_title] = "Template Added"
  # session[:toast] = "Successfully added template #{template.name} for #{full_name_plus_username(patient)}"
  { toast_title: "Template Added",
    toast_msg: "Successfully added template #{@exercise_template.name} for #{full_name_plus_username(@patient)}" }.to_json
end

# display page for creating exercise template
get "/exercise_library/add_exercise" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  @exercise_library = ExerciseLibrary.load('main')
  @patient = User.get(params[:pt]) if params[:pt]
  # the group level user is browsing exercise library at

  # testing
  # @exercise_library.add_group('A', create_group_hierarchy)
  # @exercise_library.add_group('B', create_group_hierarchy)

  # @exercise_library.add_group('A1', create_group_hierarchy('A'))
  # @exercise_library.add_group('A2', create_group_hierarchy('A'))
  # @exercise_library.add_group('B1', create_group_hierarchy('B'))

  @title = "Create Exercise Template"

  erb :exercise_template_base_info_edit
end

# add exercise template
post "/exercise_library/add_exercise" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @new_exercise_name = params[:new_exercise_name].to_s.strip
  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @dest_group_hierarchy = create_group_hierarchy(params[:group_lvl_1], params[:group_lvl_2])

  @exercise = ExerciseTemplate.new(@new_exercise_name, params[:reps], params[:sets])
  @exercise.instructions = params[:instructions]

  @exercise_library = ExerciseLibrary.load('main')

  @title = "Create Exercise Template"

  # validate exercise name
  if invalid_name(@new_exercise_name)
    session[:error] = "Exercise names can only contain letters and/or numbers."
    halt erb(:exercise_template_base_info_edit)
  end

  # validate group names
  if (!params[:group_lvl_1].empty? && invalid_name(params[:group_lvl_1])) ||
    (!params[:group_lvl_2].empty? && invalid_name(params[:group_lvl_2]))
    session[:error] = "Group names can only contain letters and/or numbers."
    halt erb(:exercise_template_base_info_edit)
  end

  if nil_or_empty?(params[:group_lvl_1]) && !nil_or_empty?(params[:group_lvl_2])
    session[:error] = "Group name cannot be empty if a subgroup is specified."
    halt erb(:exercise_template_base_info_edit)
  end

  if @exercise_library.has_exercise(@new_exercise_name, @dest_group_hierarchy)
    session[:error] = "Exercise Library already has a template named '#{@new_exercise_name} in group #{[params[:group_lvl_1], params[:group_lvl_1]].join('/')}'. Please choose another name."
    halt erb(:exercise_template_base_info_edit)
  end

  if @new_exercise_name.empty?
    session[:error] = "Template name cannot be empty."
    halt erb(:exercise_template_base_info_edit)
  end

  @exercise_library.add_exercise(@exercise, @dest_group_hierarchy)
  @exercise_library.save

  redirect "/exercise_library/#{@exercise.name}/edit?group=#{params[:group]}"
end

# display exercise template edit page
get "/exercise_library/:exercise_name/edit" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @exercise_library = ExerciseLibrary.load('main')
  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @patient = User.get(params[:pt])

  # session[:debug] = params[:group]
  # redirect "/test"
  @exercise = @exercise_library.get_exercise(params[:exercise_name], @browse_group_hierarchy)

  unless @exercise # requested exercise not found
    session[:error] = "Exercise template '#{params[:exercise_name]}' not found."
    if @patient
      redirect "/users/#{@patient.username}/exercises/add_from_library#{'?pt=' + @patient.username if @patient}"
    else
      redirect "/exercise_library"
    end
  end

  @title = "Edit Exercise Template"
  @editing_exercise_template = true

  erb :exercise_template_base_info_edit, :layout => :layout do
    erb :template_images_edit
  end
end

# display templates and/or groups
get "/exercise_library" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @exercise_library = ExerciseLibrary.load('main')

  @group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  # @group contains subgroups + template items
  @group = @exercise_library.get_group(@group_hierarchy)

  @patient = User.get(params[:pt])
  # debug
  # @exercise_library.add_subgroup('group 1', create_group_hierarchy)
  # @exercise_library.add_subgroup('group 2', create_group_hierarchy)
  # @exercise_library.add_subgroup('group 3', create_group_hierarchy)

  # @exercise_library.add_exercise_by_name('squat')
  # @exercise_library.add_exercise_by_name('jump')


  erb :exercise_library
end

# edit exercise template
post "/exercise_library/:exercise_name/edit" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  @dest_group_hierarchy = create_group_hierarchy(params[:group_lvl_1], params[:group_lvl_2])

  @patient = params[:pt]

  @exercise_library = ExerciseLibrary.load('main')
  # session[:debug] = @exercise_library.get_exercise('jumping ropes',@browse_group_hierarchy).name
  # redirect "/test"
  @exercise = @exercise_library.get_exercise(params[:exercise_name], @browse_group_hierarchy)
  @new_exercise_name = params[:new_exercise_name].strip

  @exercise.reps = params[:reps]
  @exercise.sets = params[:sets]
  @exercise.instructions = params[:instructions]

  # check for empty group names
  if nil_or_empty?(params[:group_lvl_1]) && !nil_or_empty?(params[:group_lvl_2])
    session[:error] = "Group name cannot be empty if a subgroup is specified."
    erb :exercise_template_base_info_edit, :layout => :layout do
      erb :template_images_edit
    end
    halt
  end

  # validate group names
  if (!params[:group_lvl_1].empty? && invalid_name(params[:group_lvl_1])) ||
    (!params[:group_lvl_2].empty? && invalid_name(params[:group_lvl_2]))
    session[:error] = "Group names can only contain letters and/or numbers."

    erb :exercise_template_base_info_edit, :layout => :layout do
      erb :template_images_edit
    end
    halt
  end

  # ensuring not changing exercise name to clash with another existing exercise
  if @exercise_library.has_exercise(@new_exercise_name, @dest_group_hierarchy) && @new_exercise_name != @exercise.name
    session[:error] = "Exercise Library already has a exercise template named '#{@new_exercise_name}'. Please choose another name."
    erb :exercise_template_base_info_edit, :layout => :layout do
      erb :template_images_edit
    end
    halt
  end

  # update exercise name
  @exercise.name = @new_exercise_name

  # change residing group if needed
  if @browse_group_hierarchy != @dest_group_hierarchy
    @exercise_library.move_exercise(@exercise.name, @browse_group_hierarchy, @dest_group_hierarchy)
  end

  @exercise_library.save

  redirect "/exercise_library/#{@exercise.name}/edit#{create_full_query_str({group: make_group_query_str(@dest_group_hierarchy), pt: params[:pt]})}"
end

# delete exercise template
post "/exercise_library/:exercise_name/delete" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  @exercise_library = ExerciseLibrary.load('main')
  @delete_exercise = @exercise_library.get_exercise(params[:exercise_name], @browse_group_hierarchy)

  @exercise_library.delete_exercise(@delete_exercise.name, @browse_group_hierarchy, true)

  @exercise_library.save

  if params[:pt]
    redirect "/users/#{params[:pt]}/exercises/add_from_library?group=#{params[:group]}"
  else
    redirect "/exercise_library?group=#{params[:group]}"
  end
end

def remove_trailing_nils_and_emptys(ary)
  until (!ary[-1].nil? && !ary[-1].empty?) || ary.empty?
    ary.pop
  end
end

def create_group_hierarchy(*groups)
  remove_trailing_nils_and_emptys(groups)
  groups.unshift(GroupOperations::TOP_GROUP) if groups[0] != GroupOperations::TOP_GROUP
  groups
end

# adds a new exercise by name to patient's exercise list
post "/users/:username/exercises/add" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @new_exercise_name = params[:new_exercise_name].strip
  @group_name = params[:group].strip

  if invalid_name(@new_exercise_name)
    session[:error] = "Exercise names can only contain letters and/or numbers."
    redirect "/users/#{@patient.username}/exercises"
  end

  if @patient.num_of_exercises >= Patient::MAX_NUM_EXERCISES
    session[:error] = "You've reached the limit of having #{Patient::MAX_NUM_EXERCISES} exercises."
    redirect "/users/#{@patient.username}/exercises"
  end

  if !@group_name.empty? && invalid_name(@group_name)
    session[:error] = "Group name can only contain letters and/or numbers."
    redirect "/users/#{@patient.username}/exercises"
  end

  # validate exercise name
  raise GroupOperations::ItemNameInGroupNotUniqueErr if @patient.has_exercise(@new_exercise_name, create_group_hierarchy(@group_name))

  raise GroupOperations::ItemNameEmptyErr if @new_exercise_name.empty?

  @patient.add_exercise_by_name(params[:new_exercise_name], create_group_hierarchy(@group_name))

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  redirect "/users/#{@patient.username}/exercises"

rescue GroupOperations::ItemNameInGroupNotUniqueErr
  session[:error] = "An exercise called '#{@new_exercise_name}' already exists. Please pick a new name."
  redirect "/users/#{@patient.username}/exercises"
rescue GroupOperations::ItemNameEmptyErr
  session[:error] = "Exercise name cannot be blank"
  redirect "/users/#{@patient.username}/exercises"
end

get "/users/:username/exercises/:exercise_name/edit" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @current_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @exercise = @patient.get_exercise(params[:exercise_name], @current_group_hierarchy)
  erb :edit_exercise
end

def delete_local_file(path)
  FileUtils.rm(path)
end

# upload image/files for exercise template
post "/exercise_library/:exercise_name/upload_file" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @exercise_library = ExerciseLibrary.load('main')
  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @exercise = @exercise_library.get_exercise(params[:exercise_name], @browse_group_hierarchy)

  params[:images].each do |file_hash|
    if @exercise.has_file(file_hash[:filename])
      session[:error] = "This exercise template already has an image called '#{file_hash[:filename]}'. Please upload an image with a different name."
      redirect "/exercise_library/#{@exercise.name}/edit"
    end

    if @exercise.num_files >= ExerciseTemplate::FILES_LIMIT
      session[:error] = "Each template can only contain #{ExerciseTemplate::FILES_LIMIT} files."
      redirect "/exercise_library/#{@exercise.name}/edit"
    end

        # validate file size
    if File.size(file_hash[:tempfile]) / (1024 * 1024 * 1.0) > ExerciseTemplate::FILE_UPLOAD_SIZE_LIMIT_MB
      session[:error] = "Please ensure each image has a file size of under #{ExerciseTemplate::FILE_UPLOAD_SIZE_LIMIT_MB} megabytes."
      redirect "/exercise_library/#{@exercise.name}/edit"
    end

    @exercise.add_file(file: file_hash[:tempfile], filename: file_hash[:filename])
    @exercise_library.save
  end

  redirect "/exercise_library/#{@exercise.name}/edit#{create_full_query_str({group: params[:group], pt: params[:pt]})}"
end

# upload image or other files associated with an exercise for a patient
post "/users/:username/exercises/:exercise_name/upload_file" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @current_group_hierarchy = parse_group_query_str(params[:group])
  @exercise = @patient.get_exercise(params[:exercise_name], create_group_hierarchy(*@current_group_hierarchy))


  params[:images].each do |file_hash|
    # dest_path = File.join(public_path + "/images/#{params[:username]}/#{params[:exercise_name]}", file_hash[:filename])

    if @exercise.has_file(file_hash[:filename]) # image with same name already exists
      session[:error] = "This exercise already has an image called '#{file_hash[:filename]}'. Please upload an image with a different name."
      redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit?group=#{params[:group]}"
    end

    if @exercise.num_files >= ExerciseTemplate::FILES_LIMIT
      session[:error] = "Each exercise can only contain #{ExerciseTemplate::FILES_LIMIT} files."
      redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit?group=#{params[:group]}"
    end

    # validate file size
    if File.size(file_hash[:tempfile]) / (1024 * 1024 * 1.0) > ExerciseTemplate::FILE_UPLOAD_SIZE_LIMIT_MB
      session[:error] = "Please ensure each image has a file size of under #{ExerciseTemplate::FILE_UPLOAD_SIZE_LIMIT_MB} megabytes."
      redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit?group=#{params[:group]}"
    end

    # upload_file(source: file_hash[:tempfile], dest: dest_path)
    # image_link = File.join("/images/#{params[:username]}/#{params[:exercise_name]}", file_hash[:filename])

    # @exercise.add_file_link(image_link)
    @exercise.add_file(file: file_hash[:tempfile], filename: file_hash[:filename])
    log_date_if_therapist_doing_edit(@patient)
    @patient.save
  end



  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit?group=#{params[:group]}"
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

  @current_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))



  @dest_group_name = params[:dest_group].strip
  @dest_group_hierarchy = create_group_hierarchy(@dest_group_name)

  @exercise = @patient.get_exercise(params[:exercise_name], create_group_hierarchy(*@current_group_hierarchy))

  # session[:debug] = @current_group_hierarchy.inspect
  # redirect "/test"

  if @current_group_hierarchy != @dest_group_hierarchy
    @patient.move_exercise(params[:exercise_name], @current_group_hierarchy, @dest_group_hierarchy)
  end

  @exercise = @patient.get_exercise(params[:exercise_name], create_group_hierarchy(*@dest_group_hierarchy))

  @exercise.reps = params[:reps]
  @exercise.sets = params[:sets]
  @exercise.instructions = params[:instructions]
  @exercise.comment_by_patient = params[:patient_comment]
  @exercise.comment_by_therapist = params[:therapist_comment]

  # validate exercise name
  exercise_name_not_unique = @patient.has_exercise(params[:new_exercise_name], @dest_group_hierarchy) && @exercise.name != params[:new_exercise_name]

  raise GroupOperations::ItemNameInGroupNotUniqueErr if exercise_name_not_unique

  if invalid_name(params[:new_exercise_name])
    session[:error] = "Exercise name can only contain letters and/or numbers."
    halt erb(:edit_exercise)
  end

  @exercise.name = params[:new_exercise_name]

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  session[:success] = "Your changes have been saved"
  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit?group=#{@dest_group_name}"

rescue GroupOperations::ItemNameInGroupNotUniqueErr
  session[:error] = "An exercise called '#{@exercise.name}' already exists in group #{display_current_group(@dest_group_hierarchy)}."
  halt erb(:edit_exercise)
# rescue ExerciseTemplate::ExerciseNameNotUniqueErr
#   session[:error] = "An exercise called '#{@new_exercise_name}' already exists. Please pick a new name."
#   halt erb(:edit_exercise)
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
  @current_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  @patient.delete_exercise(params[:exercise_name], @current_group_hierarchy, true)

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

# Delete file associated with exercise
post "/users/:username/exercises/:exercise_name/delete_file" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @current_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @exercise = @patient.get_exercise(params[:exercise_name], @current_group_hierarchy)

  @file_path = params[:file_path]
  filename = File.basename(@file_path)


  if @exercise.has_file(filename)
    # delete_file(public_path + "/images/#{params[:username]}/#{params[:exercise_name]}/#{filename}")
    @exercise.delete_file(@file_path)

    log_date_if_therapist_doing_edit(@patient)
    @patient.save
    session[:success] = "File succcessfuly removed"
  else
    session[:error] = "File does not exist"
  end

  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit?group=#{params[:group]}"
end

# Delete file associated with exercise template
post "/exercise_library/:exercise_name/delete_file" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @exercise_library = ExerciseLibrary.load('main')
  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @exercise = @exercise_library.get_exercise(params[:exercise_name], @browse_group_hierarchy)

  @file_path = params[:file_path]
  filename = File.basename(@file_path)

  if @exercise.has_file(filename)
    @exercise.delete_file(@file_path)
    @exercise_library.save
    session[:success] = "File succcessfuly removed"
  else
    session[:error] = "File does not exist"
  end

  redirect "/exercise_library/#{@exercise.name}/edit#{create_full_query_str({group: make_group_query_str(@dest_group_hierarchy), pt: params[:pt]})}"
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
  @check_date = params[:date]
  @ticked = params[:checkbox_value]
  @group_name = params[:group]
  @current_group_hierarchy = create_group_hierarchy(@group_name)
  @end_date = params[:end_date].strip

  # session[:debug] = @current_group_hierarchy.inspect
  # redirect "/test"

  @exercise = @patient.get_exercise(params[:exercise_name], @current_group_hierarchy)

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

  redirect "/users/#{@patient.username}/exercises?end_date=#{@end_date}"
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
  @username = params[:username].strip
  @email = params[:email].strip
  @first_name = params[:first_name].strip
  @last_name = params[:last_name].strip
  @password = params[:password]
  @confirm_password = params[:confirm_password]
  @role = params[:role].strip
  @hashed_pw = BCrypt::Password.create(@password)

  if invalid_username(@username)
    session[:error] = "Username can only contain letters, numbers and/or '_' (underscore) and '-' (hyphen) characters."
    halt erb(:new_account)
  end

  if @password != @confirm_password
    session[:error] = "Please correctly confirm your password."
    halt erb(:new_account)
  end

  if @role == 'patient'
    @new_user = Patient.new(@username, @hashed_pw)
  elsif @role == 'therapist'
    unless verify_user_access(required_authorization: :admin)
      redirect "/access_error"
    end

    @new_user = Therapist.new(@username, @hashed_pw)
  elsif @role == 'admin'
    unless verify_user_access(required_authorization: :admin)
      redirect "/access_error"
    end

    @new_user = Admin.new(@username, @hashed_pw)
  else # no role chosen
    session[:error] = "Please choose a role."
    halt erb(:new_account)
  end

  @new_user.email = @email
  @new_user.first_name = @first_name
  @new_user.last_name = @last_name
  @new_user.change_pw_next_login = true if params[:prompt_change_pw]

  if User.exists?(@username)
    session[:error] = "Username already exists. Please pick another."

    halt erb(:new_account)
  end

  @new_user.save

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
  # session.delete(:user)
  session.clear

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
                  (session[:user].username == required_username) || access_level_diff > 0
                 # if required_username is provided, access is only granted
                 #    if username matches, OR logged-in user has higher access level than required
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

post "/users/:username/exercises/add_exercise_group_from_library" do
=begin
if source group is level 1 group, the contents of the group will
be applied to top level group of patient.

if source group is level 2 group (i.e. subgroup), the whole source group
will be applied as a subgroup for the patient.
=end
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @exercise_library = ExerciseLibrary.load('main')

  @source_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group_hierarchy_str]))
  @source_group = @exercise_library.get_group(@source_group_hierarchy)
  @source_level = @source_group_hierarchy.size - 1

  @source_group_copy = Group.deep_copy(@source_group)

  if @source_level == 1 # apply source group contents to patient's main group
    # copy templates to patient's top level group
    @source_group_copy.items.each do |template|
      template.group_hierarchy = create_group_hierarchy()

      dest_exercise = Exercise.new_from_template(template)
      dest_exercise.patient_username = @patient.username

      # copy image files from template
      GroupOperations.replace_all_supp_files(@exercise_library, template, dest_exercise)

      @patient.add_exercise(dest_exercise, create_group_hierarchy)
    end

    # copy subgroup templates into subgroups under patient's exercises
    @source_group_copy.subgroups.each do |subgroup|
      subgroup.items.each do |template|
        dest_exercise = Exercise.new_from_template(template)
        dest_exercise.patient_username = @patient.username
        dest_exercise.group_hierarchy = create_group_hierarchy(subgroup.name)
        GroupOperations.replace_all_supp_files(@exercise_library, template, dest_exercise)
        @patient.add_exercise(dest_exercise, dest_exercise.group_hierarchy)
      end
    end
  elsif @source_level == 2 # apply source group as a subgroup under patient's main group
    @source_group_copy.items.each do |template|
      dest_exercise = Exercise.new_from_template(template)
      dest_exercise.patient_username = @patient.username
      dest_exercise.group_hierarchy = create_group_hierarchy(@source_group_copy.name)
      GroupOperations.replace_all_supp_files(@exercise_library, template, dest_exercise)
      @patient.add_exercise(dest_exercise, dest_exercise.group_hierarchy)
    end
    # @patient.exercise_collection.add_subgroup(@source_group_copy)
  end

  # session[:debug] = @patient.exercise_collection.items[0].name
  # redirect "/test"

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  { toast_title: "Template Added",
    toast_msg: "Successfully added template group #{@source_group.name} for #{full_name_plus_username(@patient)}" }.to_json
end

post "/users/:username/exercises/add_group" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  @new_group_name = params[:group].strip

  if @patient.subgroup_exists?(@new_group_name, Patient::TOP_HIERARCHY)
    session[:error] = "A group called #{@new_group_name} already exists."
    redirect "/users/#{@patient.username}/exercises"
  end

  if @new_group_name.empty?
    session[:error] = "Group name cannot be blank."
    redirect "/users/#{@patient.username}/exercises"
  end

  if invalid_name(@new_group_name)
    session[:error] = "Group name can only contain letters, numbers or space characters."
    redirect "/users/#{@patient.username}/exercises"
  end

  @patient.add_group(@new_group_name, Patient::TOP_HIERARCHY)

  log_date_if_therapist_doing_edit(@patient)
  @patient.save
  redirect "/users/#{@patient.username}/exercises"
end

post "/users/:username/exercises/group/:delete_group/delete" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  delete_group_name = params[:delete_group]

  @patient.delete_group(delete_group_name, create_group_hierarchy)

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

get "/exercise_library/rename_group" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @cur_group_name = @group_hierarchy.last

  erb :rename_template_group
end

post "/exercise_library/rename_group" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @exercise_library = ExerciseLibrary.load('main')

  @cur_group_name = params[:cur_group_name].strip
  @new_group_name = params[:new_group_name].strip
  @current_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @parent_hierarchy = @current_group_hierarchy[0..-2]

  @new_group_hierarchy = @parent_hierarchy + [@new_group_name]


  @group = @exercise_library.get_group(@current_group_hierarchy)

  if @exercise_library.subgroup_exists?(@new_group_name, @parent_hierarchy)
    session[:error] = "A group called #{@new_group_name} already exists."
    redirect "/exercise_library#{create_full_query_str({group: params[:group], pt: params[:pt] })}"
  end

  if @new_group_name.empty?
    session[:error] = "Group name cannot be blank."
    redirect "/exercise_library#{create_full_query_str({group: params[:group], pt: params[:pt] })}"
  end

  if invalid_name(@new_group_name)
    session[:error] = "Group name can only contain letters and/or numbers."
    redirect "/exercise_library#{create_full_query_str({group: params[:group], pt: params[:pt] })}"
  end

  @exercise_library.rename_group(@group.name, @parent_hierarchy, @new_group_name)

  @exercise_library.save

  redirect "/exercise_library#{create_full_query_str({group: make_group_query_str(@parent_hierarchy), pt: params[:pt] })}"
end

post "/users/:username/exercises/group/:group_name/rename" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @group = @patient.get_group(create_group_hierarchy(params[:group_name]))
  @new_group_name = params[:new_group_name].strip

  if invalid_name(@new_group_name)
    session[:error] = "Group name can only contain letters and/or numbers."
    redirect "/users/#{@patient.username}/exercises"
  end

  if @patient.subgroup_exists?(@new_group_name, Patient::TOP_HIERARCHY)
    session[:error] = "A group called #{@new_group_name} already exists."
    redirect "/users/#{@patient.username}/exercises"
  end

  if @new_group_name.empty?
    session[:error] = "Group name cannot be blank."
    redirect "/users/#{@patient.username}/exercises"
  end

  # update group hierarchy names of exercises in this group
  # new_group_hierarchy = create_group_hierarchy(@new_group_name)
  # @group.items.each { |exercise| exercise.group_hierarchy = new_group_hierarchy}

  # @group.name = @new_group_name

  @parent_hierarchy = create_group_hierarchy
  @patient.rename_group(@group.name, @parent_hierarchy, @new_group_name)

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

post "/users/:username/exercises/:exercise_name/move" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  from_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  dest_group_name = params[:dest_group].strip
  dest_group_hierarchy = create_group_hierarchy(dest_group_name)
  # dest_group = @patient.get_group(dest_group_hierarchy)

  # @exercise = @patient.get_exercise(params[:exercise_name], from_group_hierarchy)

  # # validate exercise name
  # raise GroupOperations::ItemNameInGroupNotUniqueErr if @patient.has_exercise(@exercise.name, dest_group_hierarchy)

  # @patient.add_exercise(@exercise, dest_group_hierarchy)
  # @patient.delete_exercise(@exercise.name, from_group_hierarchy)
  @patient.move_exercise(params[:exercise_name], from_group_hierarchy, dest_group_hierarchy)

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  redirect "/users/#{@patient.username}/exercises"

rescue GroupOperations::ItemNameInGroupNotUniqueErr
  session[:error] = "An exercise called '#{@new_exercise_name}' already exists in group #{dest_group.name}."
  redirect "/users/#{@patient.username}/exercises"
end

post "/exercise_library/delete_group" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @delete_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:delete_group_query_str]))

  @exercise_library = ExerciseLibrary.load('main')
  @delete_group_name = @delete_group_hierarchy.last
  @delete_group_parent_hierarchy = @delete_group_hierarchy[0..-2]

  @exercise_library.delete_group(@delete_group_name, @delete_group_parent_hierarchy)

  @exercise_library.save

  redirect "/exercise_library#{create_full_query_str({group: params[:group], pt: params[:pt] })}"
end

post "/exercise_library/create_group" do
  unless verify_user_access(required_authorization: :therapist)
    redirect "/access_error"
  end

  @exercise_library = ExerciseLibrary.load('main')

  @group_lvl_1 = params[:group_lvl_1].strip
  @group_lvl_2 = params[:group_lvl_2].strip

  create_lvl_1_group = nil_or_empty?(@group_lvl_2) && !nil_or_empty?(@group_lvl_1)
  create_lvl_2_group = !nil_or_empty?(@group_lvl_2) && !nil_or_empty?(@group_lvl_1)
  lvl_1_group_exists = @exercise_library.subgroup_exists?(@group_lvl_1, create_group_hierarchy)
  lvl_2_group_exists = @exercise_library.subgroup_exists?(@group_lvl_2, create_group_hierarchy(@group_lvl_1))
  lvl_1_group_name_empty = nil_or_empty?(@group_lvl_1)
  lvl_2_group_name_empty = nil_or_empty?(@group_lvl_2)

  if !lvl_1_group_name_empty && invalid_name(@group_lvl_1) ||
     !lvl_2_group_name_empty && invalid_name(@group_lvl_2)
    session[:error] = "Group name can only contain letters, numbers or space characters."
    redirect "/exercise_library?group=#{params[:group]}"
  end

  # check group exists when creating level 1 group
  if create_lvl_1_group && lvl_1_group_exists
    session[:error] = "Group called '#{@group_lvl_1}' already exists."
    redirect "/exercise_library?group=#{params[:group]}"
  end

  # check group exists when creating level 2 group
  if create_lvl_2_group && lvl_2_group_exists
    session[:error] = "Group called '#{@group_lvl_2}' already exists."
    redirect "/exercise_library?group=#{params[:group]}"
  end

  if create_lvl_1_group
    @exercise_library.add_group(@group_lvl_1, create_group_hierarchy)
  end

  if create_lvl_2_group
    @exercise_library.add_group(@group_lvl_2, create_group_hierarchy(@group_lvl_1))
  end

  # display error for blank group names
  if lvl_1_group_name_empty && lvl_2_group_name_empty ||
     lvl_1_group_name_empty && !lvl_2_group_name_empty
    raise GroupOperations::GroupNameEmptyErr
  end

  @exercise_library.save

  redirect "/exercise_library#{create_full_query_str({group: params[:group], pt: params[:pt] })}"

  rescue GroupOperations::GroupNameEmptyErr
    session[:error] = "Group name cannot be blank."
    redirect "/exercise_library?group=#{params[:group]}"
end

post "/users/:username/exercises/:exercise_name/move_up" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  unless @patient.get_exercise(params[:exercise_name], create_group_hierarchy(params[:group]))
    session[:error] = "Exercise doesn't exist"
    redirect "/users/#{@patient.username}/exercises"
  end

  @patient.move_exercise_up(params[:exercise_name], params[:group])
  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

post "/users/:username/exercises/groups/:group_name/move_all_exercises_out" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @from_group_hierarchy = create_group_hierarchy(params[:group_name])
  @group = @patient.get_group(@from_group_hierarchy)

  unless @group
    session[:error] = "Group doesn't exist"
    redirect "/users/#{@patient.username}/exercises"
  end



  exercise_names = @group.items.map { |exercise| exercise.name.dup }
  exercise_names.each do |exercise_name|
    @patient.move_exercise(exercise_name, @from_group_hierarchy, create_group_hierarchy)
  end

  @patient.save

  session[:success] = "Move all exercises out of group '#{@group.name}'"

  redirect "/users/#{@patient.username}/exercises"
end

post "/users/:username/exercises/:exercise_name/move_down" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  unless @patient.get_exercise(params[:exercise_name], create_group_hierarchy(params[:group]))
    session[:error] = "Exercise doesn't exist"
    redirect "/users/#{@patient.username}/exercises"
  end

  @patient.move_exercise_down(params[:exercise_name], params[:group])
  @patient.save

  redirect "/users/#{@patient.username}/exercises"

end

post "/users/:username/exercises/groups/:group_name/move_up" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  unless @patient.get_group(create_group_hierarchy(params[:group_name]))
    session[:error] = "Group doesn't exist"
    redirect "/users/#{@patient.username}/exercises"
  end

  @patient.move_group_up(params[:group_name])
  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

post "/users/:username/exercises/groups/:group_name/move_down" do
  unless verify_user_access(required_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  unless @patient.get_group(create_group_hierarchy(params[:group_name]))
    session[:error] = "Group doesn't exist"
    redirect "/users/#{@patient.username}/exercises"
  end

  @patient.move_group_down(params[:group_name])
  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

get "/privacy_policy" do
  erb :privacy_policy
end

get "/terms" do

  markdown :terms, layout: :layout
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
  # @patient = User.get('pineapple')

  # @patient.get_groups(['main']).map(&:name).inspect
  # # @patient.get_group(['main', 'stretches']).items.inspect
  # main_grp = @patient.get_group(['main']).name

   session[:debug]

  # Amazon_AWS.delete_all_objs(bucket: :images, prefix: 'coffee')
end