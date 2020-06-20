require_relative '../helpers'

# display templates and/or groups
get "/exercise_library" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @exercise_library = ExerciseLibrary.load('main')

  @group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  # @group contains subgroups + template items
  @group = @exercise_library.get_group(@group_hierarchy)

  @patient = User.get(params[:pt])

  logger.info "#{logged_in_user} views exercise library"

  erb :'exercise_library/exercise_library'
end

# edit exercise template
post "/exercise_library/:exercise_name/edit" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @title = "Edit Exercise Template"

  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  @dest_group_hierarchy = create_group_hierarchy(params[:group_lvl_1], params[:group_lvl_2])

  @patient = User.get(params[:pt])

  @exercise_library = ExerciseLibrary.load('main')
  # session[:debug] = @exercise_library.get_exercise('jumping ropes',@browse_group_hierarchy).name
  # redirect "/test"
  @exercise = @exercise_library.get_exercise(params[:exercise_name], @browse_group_hierarchy)
  @new_exercise_name = params[:new_exercise_name].strip

  # validate new exercise name
  if invalid_name(@new_exercise_name)
    session[:error] = "Exercise name can only contain letters and/or numbers."
    halt erb :'exercise_library/exercise_template_base_info_edit', :layout => :layout do
      erb :'exercise_library/template_images_edit'
    end
  end

  # ensuring not changing exercise name to clash with another existing exercise
  if @exercise_library.has_exercise(@new_exercise_name, @dest_group_hierarchy) && @new_exercise_name != @exercise.name
    session[:error] = "Exercise Library already has a exercise template named '#{@new_exercise_name}' in group #{@dest_group_hierarchy}. Please choose another name."

    halt erb :'exercise_library/exercise_template_base_info_edit', :layout => :layout do
      erb :'exercise_library/template_images_edit'
    end
  end

  # rename exercise or change residing group
  if (@browse_group_hierarchy != @dest_group_hierarchy) || (@exercise.name != @new_exercise_name)
    @exercise_library.move_exercise(@exercise.name, @new_exercise_name, @browse_group_hierarchy, @dest_group_hierarchy)
    @exercise = @exercise_library.get_exercise(params[:new_exercise_name], @dest_group_hierarchy)
  end

  @exercise.reps = params[:reps]
  @exercise.sets = params[:sets]
  @exercise.instructions = params[:instructions]

  # check for empty group names
  if nil_or_empty?(params[:group_lvl_1]) && !nil_or_empty?(params[:group_lvl_2])
    session[:error] = "Group name cannot be empty if a subgroup is specified."
    raise GroupOperations::GroupNameEmptyErr
  end

  # validate group names
  if (!params[:group_lvl_1].empty? && invalid_name(params[:group_lvl_1])) ||
    (!params[:group_lvl_2].empty? && invalid_name(params[:group_lvl_2]))

    session[:error] = "Group names can only contain letters and/or numbers."
    raise GroupOperations::GroupNameEmptyErr
  end

  @exercise_library.save

  logger.info "#{logged_in_user} updated exercise template '#{@exercise.name}', dest group #{@dest_group_hierarchy}"

  redirect "/exercise_library/#{@exercise.name}/edit#{create_full_query_str({group: make_group_query_str(@dest_group_hierarchy), pt: params[:pt]})}"

rescue GroupOperations::GroupNameEmptyErr

  erb :'exercise_library/exercise_template_base_info_edit', :layout => :layout do
      erb :'exercises_library/template_images_edit'
  end
end

# delete exercise template
post "/exercise_library/:exercise_name/delete" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  @exercise_library = ExerciseLibrary.load('main')
  @delete_exercise = @exercise_library.get_exercise(params[:exercise_name], @browse_group_hierarchy)

  logger.info "#{logged_in_user} deletes exercise template '#{@delete_exercise.name}' from group #{@browse_group_hierarchy}"

  @exercise_library.delete_exercise(@delete_exercise.name, @browse_group_hierarchy, true)

  @exercise_library.save

  if params[:pt]
    redirect "/users/#{params[:pt]}/exercises/add_from_library?group=#{params[:group]}"
  else
    redirect "/exercise_library?group=#{params[:group]}"
  end
end



# add exercise for patient from library
get "/users/:username/exercises/add_from_library" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @patient = User.get(params[:username])
  @exercise_library = ExerciseLibrary.load('main')
  @group = @exercise_library.get_group(@group_hierarchy)

  logger.info "#{logged_in_user} views exercise library for #{full_name_plus_username(@patient)}"

  erb :'exercise_library/exercise_library'
end

# add selected template as exercise for a patient
post "/users/:username/exercises/add_from_library" do
  unless verify_user_access(min_authorization: :therapist)
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

    # session[:error] = "#{full_name_plus_username(@patient)} already has an exercise called '#{@exercise_template.name}'. Please change either the name of the template or the patient's exercise."

    logger.info "#{logged_in_user} unsuccessfully attempted to add template '#{@exercise_template.name}' for #{full_name_plus_username(@patient)}"

    { toast_title: "Unable to add template",
    type: 'error',
    toast_msg: "#{full_name_plus_username(@patient)} already has an exercise called '#{@exercise_template.name}'" }.to_json
    # redirect "/users/#{@patient.username}/exercises/add_from_library#{create_full_query_str({group: params[:group], pt: params[:pt] })}"

  else

    # copy image files from template
    GroupOperations.replace_all_supp_files(@exercise_library, @exercise_template, @exercise)

    # exercise will be added to top group of patient's exercises
    @patient.add_exercise(@exercise, create_group_hierarchy)

    log_date_if_therapist_doing_edit(@patient)
    @patient.save

    logger.info "#{logged_in_user} successfully added exercise template '#{@exercise_template.name}' for #{full_name_plus_username(@patient)}"

    { toast_title: "Template Added",
      type: 'success',
      toast_msg: "Successfully added template #{@exercise_template.name} for #{full_name_plus_username(@patient)}" }.to_json
  end
end

# display page for creating exercise template
get "/exercise_library/add_exercise" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  # the group level user is browsing exercise library at
  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))

  @exercise_library = ExerciseLibrary.load('main')
  @patient = User.get(params[:pt]) if params[:pt]


  @title = "Create Exercise Template"

  logger.info "#{logged_in_user} displays page for creating exercise template"

  erb :'exercise_library/exercise_template_base_info_edit'
end

# add exercise template
post "/exercise_library/add_exercise" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @new_exercise_name = params[:new_exercise_name].to_s.strip
  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @dest_group_hierarchy = create_group_hierarchy(params[:group_lvl_1], params[:group_lvl_2])

  @exercise = ExerciseTemplate.new(@new_exercise_name, @dest_group_hierarchy, params[:reps], params[:sets])
  @exercise.instructions = params[:instructions]

  @exercise_library = ExerciseLibrary.load('main')

  @title = "Create Exercise Template"

  # validate exercise name
  if invalid_name(@new_exercise_name)
    session[:error] = "Exercise names can only contain letters and/or numbers."
    halt erb(:'exercise_library/exercise_template_base_info_edit')
  end

  # validate group names
  if (!params[:group_lvl_1].empty? && invalid_name(params[:group_lvl_1])) ||
    (!params[:group_lvl_2].empty? && invalid_name(params[:group_lvl_2]))
    session[:error] = "Group names can only contain letters and/or numbers."
    halt erb(:'exercise_library/exercise_template_base_info_edit')
  end

  if nil_or_empty?(params[:group_lvl_1]) && !nil_or_empty?(params[:group_lvl_2])
    session[:error] = "Group name cannot be empty if a subgroup is specified."
    halt erb(:'exercise_library/exercise_template_base_info_edit')
  end

  if @exercise_library.has_exercise(@new_exercise_name, @dest_group_hierarchy)
    session[:error] = "Exercise Library already has a template named '#{@new_exercise_name}' in group '#{[params[:group_lvl_1], params[:group_lvl_2]].reject(&:empty?).join('/')}'. Please choose another name."
    halt erb(:'exercise_library/exercise_template_base_info_edit')
  end

  if @new_exercise_name.empty?
    session[:error] = "Template name cannot be empty."
    halt erb(:'exercise_library/exercise_template_base_info_edit')
  end

  @exercise_library.add_exercise(@exercise, @dest_group_hierarchy)
  @exercise_library.save

  logger.info "#{logged_in_user} adds template '#{@new_exercise_name}' to exercise library, dest_group_hierarchy=#{@dest_group_hierarchy}"

  redirect "/exercise_library/#{@exercise.name}/edit#{create_full_query_str(group: params[:group], pt: params[:pt])}"
end

# display exercise template edit page
get "/exercise_library/:exercise_name/edit" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @exercise_library = ExerciseLibrary.load('main')
  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @patient = User.get(params[:pt])

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

  logger.info "#{logged_in_user} displays exercise template edit page for '#{@exercise.name}', group:#{@browse_group_hierarchy}, attached pt is #{full_name_plus_username(@patient)}"

  erb :'exercise_library/exercise_template_base_info_edit', :layout => :layout do
    erb :'exercise_library/template_images_edit'
  end
end

# Delete file associated with exercise template
post "/exercise_library/:exercise_name/delete_file" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @exercise_library = ExerciseLibrary.load('main')
  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @exercise = @exercise_library.get_exercise(params[:exercise_name], @browse_group_hierarchy)

  @file_path = params[:file_path]
  filename = File.basename(@file_path)

  if @exercise.has_file(filename)

    logger.info "#{logged_in_user} deletes supplementary file #{filename} for ex template #{@exercise.name} in group #{@browse_group_hierarchy} in exercise library."

    @exercise.delete_file(@file_path)
    @exercise_library.save
    session[:success] = "File succcessfuly removed"
  else
    session[:error] = "File does not exist"
  end

  redirect "/exercise_library/#{@exercise.name}/edit#{create_full_query_str({group: make_group_query_str(@dest_group_hierarchy), pt: params[:pt]})}"
end

post "/users/:username/exercises/add_exercise_group_from_library" do
=begin
if source group is level 1 group, the contents of the group will
be applied to top level group of patient.

if source group is level 2 group (i.e. subgroup), the whole source group
will be applied as a subgroup for the patient.
=end
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @exercise_library = ExerciseLibrary.load('main')

  @source_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group_hierarchy_str]))
  @source_group = @exercise_library.get_group(@source_group_hierarchy)
  @source_level = @source_group_hierarchy.size - 1

  @source_group_copy = Group.deep_copy(@source_group)

  # ensure no exercise name clashes
  @patient_existing_exercises = @patient.get_all_exercises
  @source_group_copy.get_all_items_recursive.each do |template|
    @name_clash = true if @patient_existing_exercises.any? { |pt_ex| pt_ex.name == template.name }
  end

  if @name_clash
    { toast_title: "Template Group Not Added",
    type: 'error',
    toast_msg: "Failed to add template group #{@source_group.name} for #{full_name_plus_username(@patient)}. One or more exercises in template group already exists in patient's exercise list." }.to_json

  else
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

    logger.info "#{logged_in_user} applys template group #{@source_group_hierarchy} for pt #{params[:username]}"

    log_date_if_therapist_doing_edit(@patient)
    @patient.save

    { toast_title: "Template Group Added",
      type: 'success',
      toast_msg: "Successfully added template group #{@source_group.name} for #{full_name_plus_username(@patient)}" }.to_json
  end
end

get "/exercise_library/rename_group" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @cur_group_name = @group_hierarchy.last

  erb :'exercise_library/rename_template_group'
end

post "/exercise_library/rename_group" do
  unless verify_user_access(min_authorization: :therapist)
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

  logger.info "#{logged_in_user} renames template group from #{@current_group_hierarchy} to #{@new_group_hierarchy}"

  @exercise_library.rename_group(@group.name, @parent_hierarchy, @new_group_name)

  @exercise_library.save

  redirect "/exercise_library#{create_full_query_str({group: make_group_query_str(@parent_hierarchy), pt: params[:pt] })}"
end

post "/exercise_library/delete_group" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @browse_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:group]))
  @delete_group_hierarchy = create_group_hierarchy(*parse_group_query_str(params[:delete_group_query_str]))

  @exercise_library = ExerciseLibrary.load('main')
  @delete_group_name = @delete_group_hierarchy.last
  @delete_group_parent_hierarchy = @delete_group_hierarchy[0..-2]

  logger.info "#{logged_in_user} deletes template group #{@delete_group_hierarchy}"

  @exercise_library.delete_group(@delete_group_name, @delete_group_parent_hierarchy)

  @exercise_library.save

  redirect "/exercise_library#{create_full_query_str({group: params[:group], pt: params[:pt] })}"
end

post "/exercise_library/create_group" do
  unless verify_user_access(min_authorization: :therapist)
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

  logger.info "#{logged_in_user} adds template group #{@group_lvl_1} - #{@group_lvl_2}"

  @exercise_library.save

  redirect "/exercise_library#{create_full_query_str({group: params[:group], pt: params[:pt] })}"

  rescue GroupOperations::GroupNameEmptyErr
    session[:error] = "Group name cannot be blank."
    redirect "/exercise_library?group=#{params[:group]}"
end

# upload image/files for exercise template
post "/exercise_library/:exercise_name/upload_file" do
  unless verify_user_access(min_authorization: :therapist)
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
    @file_size = File.size(file_hash[:tempfile]) / (1024 * 1024 * 1.0)

    if @file_size > ExerciseTemplate::FILE_UPLOAD_SIZE_LIMIT_MB
      session[:error] = "Please ensure each image has a file size of under #{ExerciseTemplate::FILE_UPLOAD_SIZE_LIMIT_MB} megabytes."
      redirect "/exercise_library/#{@exercise.name}/edit"
    end

    logger.info "#{logged_in_user} uploads file #{file_hash[:filename]} (size #{@file_size}) for template #{@exercise.name}, group #{@browse_group_hierarchy}"

    @exercise.add_file(file: file_hash[:tempfile], filename: file_hash[:filename])
    @exercise_library.save
  end

  redirect "/exercise_library/#{@exercise.name}/edit#{create_full_query_str({group: params[:group], pt: params[:pt]})}"
end