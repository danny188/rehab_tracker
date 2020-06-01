require_relative '../helpers'

# displays exercise tracker
get "/users/:username/exercises" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @end_date_str = params[:end_date].strip if params[:end_date]
  @nav = params[:nav]
  @day_step = params[:day_step].to_s.to_i

  @day_step *= -1 if @nav == 'back'

  @end_date = get_end_date(@end_date_str, @day_step)

  @dates = past_num_days(from: @end_date)
  @patient = User.get(params[:username])

  @group_names_list = @patient.get_groups(GroupOperations::TOP_HIERARCHY).map { |group| group.name }

  logger.info "#{logged_in_user} display exercises (tracker view) for #{full_name_plus_username(@patient)}"

  erb :'exercise_tracker/tracker'
end

# display patient exercises in a list
get "/users/:username/exercises/list_view" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
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

  logger.info "#{logged_in_user} display exercises (list view) for #{full_name_plus_username(@patient)}"

  erb :'exercise_tracker/exercise_list_view'
end

# adds one or more exercises by name to patient's exercise list
post "/users/:username/exercises/add" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @end_date_str = params[:end_date].strip if params[:end_date]
  @nav = params[:nav]
  @day_step = params[:day_step].to_s.to_i

  @day_step *= -1 if @nav == 'back'

  @end_date = get_end_date(@end_date_str, @day_step)

  @dates = past_num_days(from: @end_date)
  @patient = User.get(params[:username])

  @group_names_list = @patient.get_groups(GroupOperations::TOP_HIERARCHY).map { |group| group.name }


  # up to here
  # session[:debug] = params[:group].inspect
  # redirect "/test"


  @new_exercise_names = params[:new_exercise_name].map(&:strip)
  @groups = params[:group].map(&:strip)

  # if @new_exercise_names.any? {invalid_name(@new_exercise_name)
  #   session[:error] = "Exercise names can only contain letters and/or numbers."
  #   redirect "/users/#{@patient.username}/exercises"
  # end


  until @new_exercise_names.size <= 0 do
    cur_ex = @new_exercise_names[0]
    cur_group = @groups[0]

    # validations

    if invalid_name(cur_ex)
      session[:error] = "Invalid exercise name '#{cur_ex}'. Exercise names can only contain letters and/or numbers."
      # redirect "/users/#{@patient.username if @patient}/exercises#{create_full_query_str({end_date: params[:end_date], day_step: params[:day_step], nav: params[:nav]})}"
      halt erb(:'exercise_tracker/tracker')
    end

    if @patient.num_of_exercises >= Patient::MAX_NUM_EXERCISES
      session[:error] = "You've reached the limit of having #{Patient::MAX_NUM_EXERCISES} exercises."
      # redirect "/users/#{@patient.username if @patient}/exercises#{create_full_query_str({end_date: params[:end_date], day_step: params[:day_step], nav: params[:nav]})}"
      halt erb(:'exercise_tracker/tracker')
    end

    if !cur_group.empty? && invalid_name(cur_group)
      session[:error] = "Invalid group name '#{cur_group}'. Group name can only contain letters and/or numbers."
      # redirect "/users/#{@patient.username if @patient}/exercises#{create_full_query_str({end_date: params[:end_date], day_step: params[:day_step], nav: params[:nav]})}"
      halt erb(:'exercise_tracker/tracker')
    end

    if @patient.has_exercise(cur_ex, create_group_hierarchy(cur_group))
      session[:error] = "An exercise called '#{cur_ex}' already exists. Please pick a new name."
      # redirect "/users/#{@patient.username if @patient}/exercises#{create_full_query_str({end_date: params[:end_date], day_step: params[:day_step], nav: params[:nav]})}"
      halt erb(:'exercise_tracker/tracker')
    end

    # skip row if current new exercise name blank
    if !nil_or_empty?(cur_ex)
      @patient.add_exercise_by_name(cur_ex, create_group_hierarchy(cur_group))

      logger.info "#{logged_in_user} adds exercise '#{cur_ex}', under group '#{cur_group}' for patient #{full_name_plus_username(@patient)}"

      log_date_if_therapist_doing_edit(@patient)
      @patient.save
    end

    @new_exercise_names.shift
    @groups.shift
  end

  redirect "/users/#{@patient.username if @patient}/exercises#{create_full_query_str({end_date: params[:end_date], day_step: params[:day_step], nav: params[:nav]})}"
end

# displays edit page of exercise
get "/users/:username/exercises/:exercise_name/edit" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @current_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @exercise = @patient.get_exercise(params[:exercise_name], @current_group_hierarchy)

  logger.info "#{logged_in_user} displays exercise edit page of '#{@exercise.name}' for patient #{full_name_plus_username(@patient)}"

  erb :'exercise_tracker/edit_exercise'
end

# upload image or other files associated with an exercise for a patient
post "/users/:username/exercises/:exercise_name/upload_file" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
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
    @file_size = File.size(file_hash[:tempfile]) / (1024 * 1024 * 1.0)

    if @file_size  > ExerciseTemplate::FILE_UPLOAD_SIZE_LIMIT_MB
      session[:error] = "Please ensure each image has a file size of under #{ExerciseTemplate::FILE_UPLOAD_SIZE_LIMIT_MB} megabytes."
      redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit?group=#{params[:group]}"
    end

    logger.info "#{logged_in_user} uploads file #{file_hash[:filename]} (size #{@file_size}) for exercise #{@exercise.name}, group #{@current_group_hierarchy}, for pt #{full_name_plus_username(@patient)}"

    @exercise.add_file(file: file_hash[:tempfile], filename: file_hash[:filename])
    log_date_if_therapist_doing_edit(@patient)
    @patient.save
  end


  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit?group=#{params[:group]}"
end

# Save exercise details
post "/users/:username/exercises/:exercise_name/update" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end
  @patient = User.get(params[:username])

  @current_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))



  @dest_group_name = params[:dest_group].strip

  @exercise = @patient.get_exercise(params[:exercise_name], create_group_hierarchy(*@current_group_hierarchy))


  if invalid_name(@dest_group_name)
    session[:error] = "Group names can only contain letters and/or numbers."
    halt erb(:'exercise_tracker/edit_exercise')
  end

  @dest_group_hierarchy = create_group_hierarchy(@dest_group_name)


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
    halt erb(:'exercise_tracker/edit_exercise')
  end

  @exercise.name = params[:new_exercise_name]

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  logger.info "#{logged_in_user} updates exercise '#{@exercise.name}', group #{@current_group_hierarchy} for pt #{full_name_plus_username(@patient)}"

  session[:success] = "Your changes have been saved"
  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit?group=#{@dest_group_name}"

rescue GroupOperations::ItemNameInGroupNotUniqueErr
  session[:error] = "An exercise called '#{@exercise.name}' already exists in group #{display_current_group(@dest_group_hierarchy)}."
  halt erb(:'exercise_tracker/edit_exercise')
# rescue ExerciseTemplate::ExerciseNameNotUniqueErr
#   session[:error] = "An exercise called '#{@new_exercise_name}' already exists. Please pick a new name."
#   halt erb(:'exercise_tracker/edit_exercise')
end

# delete exercise for patient
post "/users/:username/exercises/:exercise_name/delete" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @current_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  logger.info "#{logged_in_user} deletes exercise '#{params[:exercise_name]}', in group #{@current_group_hierarchy} for pt #{full_name_plus_username(@patient)}"

  @patient.delete_exercise(params[:exercise_name], @current_group_hierarchy, true)

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

# Delete file associated with exercise
post "/users/:username/exercises/:exercise_name/delete_file" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @current_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @exercise = @patient.get_exercise(params[:exercise_name], @current_group_hierarchy)

  @file_path = params[:file_path]
  filename = File.basename(@file_path)


  if @exercise.has_file(filename)
    # delete_file(public_path + "/images/#{params[:username]}/#{params[:exercise_name]}/#{filename}")

    logger.info "#{logged_in_user} deletes supplementary file #{filename} for exercise '#{params[:exercise_name]}', in group #{@current_group_hierarchy}, for pt #{full_name_plus_username(@patient)}"

    @exercise.delete_file(@file_path)

    log_date_if_therapist_doing_edit(@patient)
    @patient.save
    session[:success] = "File succcessfuly removed"
  else
    session[:error] = "File does not exist"
  end

  redirect "/users/#{@patient.username}/exercises/#{@exercise.name}/edit?group=#{params[:group]}"
end



post "/users/:username/exercises/mark_all" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
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

  logger.info "#{logged_in_user} marks all exercises done for day #{@mark_date} for pt #{params[:username]}"

  # @patient.save
  session[:patient] = @patient

  # redirect "/users/#{@patient.username}/exercises#{create_full_query_str({end_date: params[:end_date], day_step: params[:day_step], nav: params[:nav]})}"
end

# saves states of all displayed checkboxes in tracker
post "/users/:username/exercises/save_all_checkboxes" do

  checkbox_data_objs = JSON.parse(request.body.read)

  @patient = User.get(params[:username])

  exercise_list = checkbox_data_objs.map { |obj| [obj['exercise_name'], obj['group']] }.uniq
  # exercise_list = exercise_names.zip(groups).uniq
  exercises = exercise_list.map { |ex_name, group| @patient.get_exercise(ex_name, create_group_hierarchy(group))}

  checkbox_data_objs.each do |obj|
    cur_exercise = exercises.find { |exercise|
        exercise.name == obj['exercise_name'] && exercise.group_hierarchy[1].to_s == obj['group']
      }

    if obj['checked']
      cur_exercise.add_date(obj['date'])
    else
      cur_exercise.delete_date(obj['date'])
    end
  end

  logger.info "#{logged_in_user} saves all checkbox changes for patient #{params[:username]}"

  @patient.save
  "saved"
end

# adds exercise group
# ***currently not in use as users not give the option to add group without exercise
post "/users/:username/exercises/add_group" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
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

  logger.info "#{logged_in_user} adds exercise group '#{@new_group_name}' for pt #{full_name_plus_username(@patient)}"

  log_date_if_therapist_doing_edit(@patient)
  @patient.save
  redirect "/users/#{@patient.username}/exercises"
end

# deletes group and associated exercises
post "/users/:username/exercises/group/:delete_group/delete" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  delete_group_name = params[:delete_group]

  logger.info "#{logged_in_user} deletes exercise group '#{delete_group_name}' for pt #{full_name_plus_username(@patient)}"

  @patient.delete_group(delete_group_name, create_group_hierarchy)

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

# renames an exercise group
post "/users/:username/exercises/group/:group_name/rename" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
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

  logger.info "#{logged_in_user} renames group from #{params[:group_name]} to #{@new_group_name} for pt #{full_name_plus_username(@patient)}"

  @parent_hierarchy = create_group_hierarchy
  @patient.rename_group(@group.name, @parent_hierarchy, @new_group_name)

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  redirect "/users/#{@patient.username}/exercises"
end

# moves an exercise to another group
post "/users/:username/exercises/:exercise_name/move" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  from_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  dest_group_name = params[:dest_group].strip
  dest_group_hierarchy = create_group_hierarchy(dest_group_name)

  logger.info "#{logged_in_user} moves exercise #{params[:exercise_name]} from #{from_group_hierarchy} to #{dest_group_hierarchy} for pt #{full_name_plus_username(@patient)}"

  @patient.move_exercise(params[:exercise_name], from_group_hierarchy, dest_group_hierarchy)

  log_date_if_therapist_doing_edit(@patient)
  @patient.save

  redirect "/users/#{@patient.username if @patient}/exercises#{create_full_query_str({end_date: params[:end_date], day_step: params[:day_step], nav: params[:nav]})}"

rescue GroupOperations::ItemNameInGroupNotUniqueErr
  session[:error] = "An exercise called '#{params[:exercise_name]}' already exists in group #{dest_group_name}."
  redirect "/users/#{@patient.username if @patient}/exercises#{create_full_query_str({end_date: params[:end_date], day_step: params[:day_step], nav: params[:nav]})}"
end

# move exercise 1 position up list
post "/users/:username/exercises/:exercise_name/move_up" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
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

# moves all exercise from group to top level group
post "/users/:username/exercises/groups/:group_name/move_all_exercises_out" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
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

# repositions exercise down list
post "/users/:username/exercises/:exercise_name/move_down" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
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


# repositions group up group list
post "/users/:username/exercises/groups/:group_name/move_up" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
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

# repositions group down group list
post "/users/:username/exercises/groups/:group_name/move_down" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
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

# display exercise stats
get "/users/:username/stats" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])

  logger.info "#{logged_in_user} displays stats for #{full_name_plus_username(@patient)}"

  erb :'exercise_tracker/stats'
end