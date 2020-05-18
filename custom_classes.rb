require 'aws-sdk-s3'
require 'stringio'
require 'set'
require 'yaml/store'
require 'fileutils'

module GroupOperations
  TOP_GROUP = 'main'
  TOP_HIERARCHY = [TOP_GROUP]

  class ItemNameInGroupNotUniqueErr < StandardError; end
  class ItemNameEmptyErr < StandardError; end
  class GroupNameEmptyErr < StandardError; end

  # replaces exercise's supplementary files with those of template's
  # used when creating new exercise for patient from existing template
  def self.replace_all_supp_files(exercise_library, template, exercise)
    exercise.clear_image_links

    # delete existing supp files of exercise? There shouldn't be any for this use case
    # of applying template's supplementary files to a brand new exercise obj

    filenames = template.image_links.map { |link| File.basename(link) }

    filenames.each do |filename|
      # add modified link to exercise
        dest_path = "images/#{exercise.patient_username}/#{make_group_query_str(exercise.group_hierarchy)}/#{exercise.name}/#{filename}"
        image_url = exercise.image_link_path(dest_path)
        exercise.add_image_link(image_url)

      #copy s3 file to patient's exercise group hierarchy
      source_path = "images/exercise_library_#{exercise_library.name}/#{make_group_query_str(template.group_hierarchy)}/#{template.name}/#{filename}"

      Amazon_AWS.copy_obj(source_bucket: :images,
                          source_key: source_path,
                          target_bucket: :images,
                          target_key: dest_path)
    end
  end

  def make_group_query_str(group_hierarchy)
    if group_hierarchy
      group_hierarchy.join("_")
    else
      ""
    end
  end

  def display_current_group(current_group_hierarchy)
    current_group_hierarchy.last
  end

  def parse_group_query_str(str)
    str.split("_") if str
  end

  # Used by ExerciseLibrary and Patient
  def add_group(new_group_name, parent_hierarchy)
    parent_group = get_group(parent_hierarchy)

    raise GroupNameEmptyErr if new_group_name.empty?

    # create parent group if not yet exist
    unless parent_group
      add_group(parent_hierarchy.last, parent_hierarchy[0..-2])
      parent_group = get_group(parent_hierarchy)
    end

    # create subgroup if not yet exist
    unless subgroup_exists?(new_group_name, parent_hierarchy)
      parent_group.add_subgroup(Group.new(new_group_name))
    end
  end

  # basically creates a new group.
  # Used by ExerciseLibrary and Patient
  def rename_group(current_name, parent_hierarchy, new_name)
    current_group_hierarchy = parent_hierarchy + [current_name]
    new_group_hierarchy = parent_hierarchy + [new_name]

    add_group(new_name, parent_hierarchy)

    cur_group = get_group(current_group_hierarchy)
    new_group = get_group(new_group_hierarchy)

    cur_group.items.each do |exercise|
      move_exercise(exercise.name, current_group_hierarchy, new_group_hierarchy)
    end

    cur_group.subgroups.each do |subgroup|
      add_group(subgroup.name, new_group_hierarchy)

      subgroup.items.each do |exercise|
        move_exercise(exercise.name,
                      current_group_hierarchy + [subgroup.name],
                      new_group_hierarchy + [subgroup.name])
      end
    end

    delete_group(current_name, parent_hierarchy)
  end

  # Used by ExerciseLibrary and Patient
  def delete_group(delete_group_name, parent_hierarchy)
    parent_group = get_group(parent_hierarchy)

    if subgroup_exists?(delete_group_name, parent_hierarchy)
      # delete elements within group
      group_to_delete = get_group(parent_hierarchy + [delete_group_name])
      temp_group_hierarchy = [parent_hierarchy] + [delete_group_name]
      # delete s3 sup files of group recursively

      Amazon_AWS.delete_all_objs(bucket: :images, prefix: image_link_prefix + "/" + make_group_query_str(temp_group_hierarchy))

      parent_group.delete_subgroup_by_name(delete_group_name)
    end
  end


  def get_groups(parent_hierarchy)
    parent_group = get_group(parent_hierarchy)
    parent_group.subgroups
  end

  # Used by ExerciseLibrary and Patient
  def subgroup_exists?(test_group_name, parent_hierarchy)
    parent_group = get_group(parent_hierarchy)
    return false unless parent_group
    parent_group.get_subgroup(test_group_name)
  end

  # Used by ExerciseLibrary and Patient
  def get_group(hierarchy = TOP_HIERARCHY)
    hierarchy_copy = hierarchy.dup

    hierarchy_copy.shift
    result_group = top_collection

    until hierarchy_copy.empty?
      result_group = result_group.get_subgroup(hierarchy_copy[0])
      return nil unless result_group
      hierarchy_copy.shift
    end

    result_group
  end

  # Used by ExerciseLibrary and Patient
  def add_exercise(exercise, group_hierarchy = TOP_HIERARCHY)
    group = get_group(group_hierarchy)

    if group
      raise ItemNameInGroupNotUniqueErr if group.has_item?(exercise.name)
    else # create subgroup if not yet exists
      target_group_name = group_hierarchy.last
      parent_hierarchy = group_hierarchy.slice(0..-2)
      add_group(target_group_name, parent_hierarchy)
      group = get_group(group_hierarchy)
    end
    exercise.group_hierarchy = group_hierarchy
    group.add_item(exercise)
  end

  # Used by ExerciseLibrary and Patient
  def get_exercise(exercise_name, group_hierarchy = TOP_HIERARCHY)
    group = get_group(group_hierarchy)
    group.get_item(exercise_name)
  end

  # Used by ExerciseLibrary and Patient
  def delete_exercise(exercise_name, group_hierarchy = TOP_HIERARCHY, delete_supp_files = false)
    group = get_group(group_hierarchy)
    exercise = get_exercise(exercise_name, group_hierarchy)

    if delete_supp_files
      # delete supplementary (image) files from s3
      exercise.image_links.each do |link|
        exercise.delete_file(link)
      end
    end

    # delete exercise object
    group.delete_item_by_name(exercise_name)
  end

  # Used by ExerciseLibrary and Patient
  def has_exercise(exercise_name, group_hierarchy = TOP_HIERARCHY)
    group = get_group(group_hierarchy)

    return false unless group

    group.has_item?(exercise_name)
  end

  # Used by ExerciseLibrary and Patient
  def move_exercise(exercise_name, from_group_hierarchy, to_group_hierarchy)
    from_group = get_group(from_group_hierarchy)
    to_group = get_group(to_group_hierarchy)

    exercise = get_exercise(exercise_name, from_group_hierarchy)

    raise GroupOperations::ItemNameInGroupNotUniqueErr if has_exercise(exercise.name, to_group_hierarchy)

    exercise.group_hierarchy = to_group_hierarchy

    # move related images/files on cloud
    move_all_exercise_supp_files(exercise_name, from_group_hierarchy, to_group_hierarchy)

    exercise_copy = exercise.deep_copy
    exercise_copy.group_hierarchy = to_group_hierarchy

    add_exercise(exercise_copy, to_group_hierarchy)

    delete_exercise(exercise.name, from_group_hierarchy)
  end

  # Used by GroupOperations::move_exercise
  def move_all_exercise_supp_files(exercise_name, from_group_hierarchy, to_group_hierarchy)
    exercise = get_exercise(exercise_name, from_group_hierarchy)
    filenames = exercise.image_links.map { |link| File.basename(link) }

    filenames.each do |filename|
      move_exercise_supp_file(exercise_name, filename, from_group_hierarchy, to_group_hierarchy)
    end

    # self.save
    # the cloud files will already have been moved even if self.save is not run
  end
end

module DataPersistence
  def upload_file_to_local(source:, dest:)
    # create directory if doesn't exist
    dir_name = File.dirname(dest)

    unless File.directory?(dir_name)
      FileUtils.mkdir_p(dir_name)
    end

    FileUtils.cp(source, dest)
  end

  # upload public files associated with exercise library or patient's exercises
  def upload_supp_file(file_obj:, dest_path:)
    Amazon_AWS.upload_obj(source_obj: file_obj,
      bucket: :images,
      dest_path: dest_path)
  end

  def delete_supp_file(key:)
    Amazon_AWS.delete_obj(key: key, bucket: :images)
  end

  def public_path
    File.expand_path("../public", __FILE__)
  end


  def save_to_local_filesystem()
    store = YAML::Store.new(self.class.path(self.name))
    store.transaction do
      store = self
    end
  end

  def delete_file_from_local_filesystem(path)
    FileUtils.rm(path)
  end

  def save
    # case ENV["RACK_ENV"]
    # # when 'testing_local'
    # #   save_to_local_filesystem
    # # when 'testing_s3', 'production_s3'
    # when 'production', 'development'
    #   Amazon_AWS.upload_obj(source_obj: self.to_yaml,
    #   bucket: :data,
    #   dest_path: "#{file_prefix + self.name}.store")
    # end
    Amazon_AWS.upload_obj(source_obj: self.to_yaml,
    bucket: :data,
    dest_path: "#{file_prefix + self.name}.store")
  end
end

class ExerciseTemplate
  include DataPersistence
  include GroupOperations

  attr_accessor :name, :instructions, :reps, :sets,
                :duration, :image_links, :exercise_library_name,
                :group_hierarchy

  FILES_LIMIT = 4
  DEFAULT_REPS = '30'
  DEFAULT_SETS = '3'
  DEFAULT_EXERCISE_LIBRARY_NAME = 'main'

  def deep_copy
    Marshal.load(Marshal.dump(self))
  end

  def initialize(name, group_hierarchy = GroupOperations::TOP_HIERARCHY, reps = DEFAULT_REPS, sets = DEFAULT_SETS)
    @name = name
    @reps = reps
    @sets = sets
    @image_links = []
    @instructions = ''
    @group_hierarchy = group_hierarchy
    @exercise_library_name = DEFAULT_EXERCISE_LIBRARY_NAME
  end

  def name_with_group
    if self.group_hierarchy.size <= 1
      self.name
    else
      "(#{display_current_group(group_hierarchy)}) #{self.name}"
    end
  end

  def files_path_local(filename)
    File.join(public_path + "/images/exercise_library/#{self.name}", filename)
  end

  def image_link_path(filename)
    # case ENV["RACK_ENV"]
    # when 'testing_local'
    #   File.join("/images/exercise_library/#{self.name}", filename)
    # when 'testing_s3'
    #   "https://#{Amazon_AWS.bucket_name(:images)}.s3-ap-southeast-2.amazonaws.com/#{filename}"
    # when 'production_s3'
    #   "https://#{Amazon_AWS.bucket_name(:images)}.s3-ap-southeast-2.amazonaws.com/#{filename}"
    # end

      "https://#{Amazon_AWS.bucket_name(:images)}.s3-ap-southeast-2.amazonaws.com/#{filename}"

  end

  def has_file(filename)
    image_links.any? { |image_link| File.basename(image_link) == filename }
  end

  def num_files
    image_links.size
  end

  def add_image_link(link)
    image_links.push(link)
  end

  def clear_image_links
    self.image_links = []
  end

  def get_image_link(idx)
    image_links[idx]
  end

  def delete_image_link(link)
    image_links.delete(link)
  end

  def add_file(file:, filename:)
    # case ENV["RACK_ENV"]
    # when 'testing_local'
    #   upload_file_to_local(source: file, dest: files_path_local(filename))
    #   dest_path = filename
    # when 'production'
    #   dest_path = "images/exercise_library_#{exercise_library_name}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    #   upload_supp_file(file_obj: file, dest_path: dest_path)
    # end

    dest_path = "images/exercise_library_#{exercise_library_name}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    upload_supp_file(file_obj: file, dest_path: dest_path)

    self.add_image_link(image_link_path(dest_path))
  end

  def delete_file(link)
    filename = File.basename(link)

    # case ENV['custom_env']
    # when 'testing_local'
    #   FileUtils.rm(files_path_local(filename))
    # when 'testing_s3', 'production_s3'
    #   key = "images/exercise_library_#{exercise_library_name}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    #   delete_supp_file(key: key)
    # end

    key = "images/exercise_library_#{exercise_library_name}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    delete_supp_file(key: key)

    self.delete_image_link(link)
  end
end

# group items can be Exercise or ExerciseTemplates objects
class Group
  attr_accessor :name, :items, :subgroups

  def initialize(name)
    @name = name
    @items = []
    @subgroups = []
  end

  def self.deep_copy(other_group)
    Marshal.load(Marshal.dump(other_group))
  end

  def add_item(new_item)
    items.push(new_item)
  end

  def get_item(item_name)
    items.find { |item| item.name == item_name }
  end

  def has_item?(item_name)
    items.any? { |item| item.name == item_name }
  end

  def add_items(new_items)
    items.push(*new_items)
  end

  def delete_item_by_name(item_name)
    items.delete_if { |item| item.name == item_name }
  end

  def add_subgroup(new_subgroup)
    subgroups.push(new_subgroup)
  end

  def add_subgroup_by_name(new_subgroup_name)
    new_subgroup = Group.new(new_subgroup_name)
    add_subgroup(new_subgroup)
  end

  def get_subgroup(subgroup_name)
    subgroups.find { |subgroup| subgroup.name == subgroup_name }
  end

  def delete_subgroup_by_name(subgroup_name)
    subgroups.delete_if { |subgroup| subgroup.name == subgroup_name}
  end

  def each_item
    items.each do |item|
      yield(item) if block_given?
    end
  end

  def each_subgroup
    subgroups.each do |subgroup|
      yield(subgroup) if block_given?
    end
  end

  def get_all_items_recursive()
    return @items if @subgroups.empty?

    result = []

    subgroups.each do |subgroup|
      result = result + subgroup.get_all_items_recursive
    end

    return result + @items
  end

end

class ExerciseGroup < Group
  # alias_method :add_exercise, :add_item
  # alias_method :get_exercise, :get_item
  # alias_method :delete_exercise, :delete_item
  # alias_method :each_exercise, :each_item
end

class TemplateGroup < Group
  # alias_method :add_template, :add_item
  # alias_method :get_template, :get_item
  # alias_method :delete_template, :delete_item
  # alias_method :each_template, :each_item
end

class ExerciseLibrary
  include DataPersistence
  include GroupOperations

  attr_accessor :name, :templates, :template_collection

  alias_method :top_collection, :template_collection

  def self.path(name)
    "./data/exercise_library_#{name}.store"
  end

  def self.create_locally(name)

    # do not overwrite
    return nil if File.exists?(path(name))

    store = YAML::Store.new(path(name))
    store.transaction do
      store = ExerciseLibrary.new(name)
    end
  end

  def self.create(name)
    new_exercise_library = ExerciseLibrary.new(name)

    Amazon_AWS.upload_obj(source_obj: new_exercise_library.to_yaml,
      bucket: :data,
      dest_path: "exercise_library_#{name}.store")

    new_exercise_library
  end

  def self.load_locally(name)
    return nil unless File.exists?(path(name))

    exercise_lib_obj = nil

    store = YAML::Store.new(path(name))
    store.transaction do
      exercise_lib_obj = store
    end

    exercise_lib_obj
  end

  def self.load(name)
    obj = Amazon_AWS.download_obj(key: "exercise_library_#{name}.store",
      bucket: :data)

    exercise_library = YAML.load(obj.to_s)

    exercise_library || create(name)
  end


  def initialize(name)
    self.name = name
    @template_collection = TemplateGroup.new(TOP_GROUP)
  end

  def image_link_prefix()
    "images/exercise_library_#{self.name}"
  end

  def file_prefix
    "exercise_library_"
  end

  def get_all_templates()
    @template_collection.get_all_items_recursive
  end

  def add_exercise_by_name(exercise_name, group_hierarchy = TOP_HIERARCHY)
    new_exercise = ExerciseTemplate.new(exercise_name, group_hierarchy)

    add_exercise(new_exercise, group_hierarchy)
  end

  # this is called by move_all_exercise_supp_files method included from GroupOperations
  def move_exercise_supp_file(exercise_name, filename, from_group_hierarchy, to_group_hierarchy)
    source_key = "images/exercise_library_#{self.name}/#{make_group_query_str(from_group_hierarchy)}/#{exercise_name}/#{filename}"
    target_key = "images/exercise_library_#{self.name}/#{make_group_query_str(to_group_hierarchy)}/#{exercise_name}/#{filename}"

    exercise = get_exercise(exercise_name, from_group_hierarchy)
    image_index = exercise.image_links.index{ |link| File.basename(link) == filename }

    Amazon_AWS.move_obj(source_bucket: :images,
                        source_key: source_key,
                        target_bucket: :images,
                        target_key: target_key)

    exercise.image_links[image_index] = exercise.image_link_path(target_key)

    # self.save
  end
end

class Exercise < ExerciseTemplate
  attr_accessor :added_date, :record_of_days, :comment_by_patient, :comment_by_therapist, :patient_username

  Comment = Struct.new(:author, :text, :last_modified)

  def self.new_from_template(template)
    new_ex = Exercise.new(template.name, template.reps, template.sets)
    new_ex.image_links = template.image_links
    new_ex.instructions = template.instructions

    new_ex
  end

  def initialize(name, group_hierarchy = GroupOperations::TOP_HIERARCHY, reps = DEFAULT_REPS, sets = DEFAULT_SETS)
    super
    @record_of_days = Set.new
    @comment_by_therapist = ""
    @comment_by_patient = ""
    @group_hierarchy = TOP_HIERARCHY
  end

  def add_date(date)
    record_of_days << date
  end

  def delete_date(date)
    record_of_days.delete(date)
  end

  def done_on?(date)
    record_of_days.include?(date)
  end

  def first_day
    return nil if record_of_days.empty?
    record_of_days.select { |day| day }.min
  end

  def last_day
    return nil if record_of_days.empty?
    record_of_days.select { |day| day }.max
  end

  def days_done
    record_of_days.select { |day| day }.count
  end

  def has_not_been_started?
    first_day == nil && last_day == nil
  end

  def files_path_local(filename:)
    File.join(public_path + "/images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}", filename)
  end

  def image_link_path(filename)
    # case ENV["custom_env"]
    # when 'testing_local'
    #   File.join("/images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}", filename)
    # when 'testing_s3'
    #   "https://#{Amazon_AWS.bucket_name(:images)}.s3-ap-southeast-2.amazonaws.com/#{filename}"
    # when 'production_s3'
    #   "https://#{Amazon_AWS.bucket_name(:images)}.s3-ap-southeast-2.amazonaws.com/#{filename}"
    # end

    "https://#{Amazon_AWS.bucket_name(:images)}.s3-ap-southeast-2.amazonaws.com/#{filename}"
  end

  def add_file(file:, filename:)
    # case ENV['custom_env']
    # when 'testing_local'
    #   upload_file_to_local(source: file, dest: files_path_local(filename))
    #   dest_path = filename
    # else
    #   dest_path = "images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    #   upload_supp_file(file_obj: file, dest_path: dest_path)
    # end

    dest_path = "images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    upload_supp_file(file_obj: file, dest_path: dest_path)

    self.add_image_link(image_link_path(dest_path))
  end

  def delete_file(link)
    filename = File.basename(link)

    # case ENV['custom_env']
    # when 'testing_local'
    #   FileUtils.rm(files_path_local(filename: filename))
    # when 'testing_s3', 'production_s3'
    #   key = "images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    #   delete_supp_file(key: key)
    # end

    key = "images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    delete_supp_file(key: key)

    self.delete_image_link(link)
  end
end

class User
  attr_accessor :username, :pw, :first_name, :last_name, :email,
  :change_pw_next_login, :account_status, :deactivate_time

  include DataPersistence

  alias :name :username

  def initialize(username, pw)
    @username = username
    @pw = pw
    @change_pw_next_login = false
    @account_status = :active
  end

  def self.get(username)
    # get_user_obj_locally(username) # uncomment this to get from local filesystem

    return nil unless exists?(username)

    obj = Amazon_AWS.download_obj(key: "user_#{username}.store",
      bucket: :data)

    YAML.load(obj)
  end

  def self.get_all()
    result = Amazon_AWS.download_all_objs(bucket: :data, prefix: 'user_')

    result.map! { |obj| YAML.load(obj) }
    result.select { |user| user.account_status == :active }
  end

  def self.exists?(username)
    Amazon_AWS.obj_exists?(key: "user_#{username}.store", bucket: :data)
  end

  def self.path(username)
    "./data/user_#{username}.store"
  end

  def self.user_exists_locally?(username)
    File.exists?("./data/user_#{username}.store")
  end

  def self.get_user_obj_locally(username)
    return nil unless user_exists_locally?(username)

    user_obj = nil
    store = YAML::Store.new("./data/user_#{username}.store")
    store.transaction do
      user_obj = store
    end
    user_obj
  end

  def self.get_all_users_locally
    files = Dir.glob("./data/**/*.store")

    result = []
    files.each do |file_path|
      contents = YAML.load(File.read(file_path))
      if contents.is_a?(User)
        user_obj = contents
        result.push(user_obj) unless user_obj.account_status == :deactivated
      end
    end
    result
  end

  def full_name
    [first_name, last_name].join(' ')
  end

  def to_s
    first_name
  end

  def role
    self.class.to_s.downcase.to_sym
  end

  def copy_from(another_user)
    self.username = another_user.username
    self.pw = another_user.pw
    self.first_name = another_user.first_name
    self.last_name = another_user.last_name
    self.email = another_user.email
    self.change_pw_next_login = another_user.change_pw_next_login
  end

  def save_to_local_filesystem
    store = YAML::Store.new(self.class.path(self.username))
    store.transaction do
      store = self
    end
  end

  def file_prefix
    "user_"
  end

  def deactivate
    self.account_status = :deactivated
    self.deactivate_time = Time.now
    self.save

    # rename user file on s3 data bucket
    source_key = "#{file_prefix + self.name}.store"
    Amazon_AWS.copy_obj(source_bucket: :data,
                        target_bucket: :data,
                        source_key: source_key,
                        target_key: "deactivated_#{file_prefix + self.name}.store")
    Amazon_AWS.delete_obj(bucket: :data, key: source_key)

    # delete all supplementary/image files of exercises of patient
    Amazon_AWS.delete_all_objs(bucket: :images, prefix: 'images/' + self.name)
  end

  def activate
    self.account_status = :active
  end
end

class Patient < User
  attr_accessor :exercise_collection, :wellness_ratings, :last_updated
  include GroupOperations

  alias_method :top_collection, :exercise_collection

  def initialize(username, pw)
    super
    @exercise_collection = ExerciseGroup.new(TOP_GROUP)
  end

  def self.get_all
    super.select { |user| user.role == :patient }
  end

  def self.get_all_patients_locally
    get_all_users_locally.select { |user| user_role(user) == :patient }
  end


  def image_link_prefix()
    "images/#{self.username}"
  end

  def add_exercise_by_name(exercise_name, group_hierarchy = TOP_HIERARCHY)
    new_exercise = Exercise.new(exercise_name, group_hierarchy)

    add_exercise(new_exercise, group_hierarchy)
  end

  def add_exercise(exercise, group_hierarchy = TOP_HIERARCHY)
    super
    exercise.patient_username = self.username
  end

  def get_all_exercises()
    @exercise_collection.get_all_items_recursive
  end

  # this is called by move_all_exercise_supp_files method included from GroupOperations
  def move_exercise_supp_file(exercise_name, filename, from_group_hierarchy, to_group_hierarchy)
    source_key = "images/#{self.username}/#{make_group_query_str(from_group_hierarchy)}/#{exercise_name}/#{filename}"
    target_key = "images/#{self.username}/#{make_group_query_str(to_group_hierarchy)}/#{exercise_name}/#{filename}"

    exercise = get_exercise(exercise_name, from_group_hierarchy)
    image_index = exercise.image_links.index{ |link| File.basename(link) == filename }

    Amazon_AWS.move_obj(source_bucket: :images,
                        source_key: source_key,
                        target_bucket: :images,
                        target_key: target_key)

    exercise.image_links[image_index] = exercise.image_link_path(target_key)

    # self.save
  end

  def mark_done_all_exercises(date)
    all_exercises = get_all_exercises
    all_exercises.each do |exercise|
      exercise.add_date(date)
    end
  end

  def mark_undone_all_exercises(date)
    all_exercises = get_all_exercises
    all_exercises.each do |exercise|
      exercise.delete_date(date)
    end
  end

  def done_all_exercises?(date)
    all_exercises = get_all_exercises
    all_exercises.all? { |exercise| exercise.done_on?(date) }
  end

  # todo: change this to be day specific. num of exercises according to how many
  # active exercises there are on a day, discount
  def num_of_exercises
    get_all_exercises.size
  end

  def has_not_started_exercising
    get_all_exercises.all? { |exercise| exercise.has_not_been_started? }
  end

  def first_exercise_day
    return nil if has_not_started_exercising
    get_all_exercises.map { |exercise| exercise.first_day }.select { |first_day| first_day }.min
  end

  def last_exercise_day
    return nil if has_not_started_exercising
    get_all_exercises.map { |exercise| exercise.last_day }.select { |last_day| last_day }.max
  end

  def num_of_exercises_done_on(date)
    return 0 if has_not_started_exercising
    get_all_exercises.select { |exercise| exercise.done_on?(date) }.count
  end

  # returns 2d array of [day, completion rate]
  def exercise_completion_rates_by_day
    return nil if num_of_exercises <= 0 || has_not_started_exercising

    result = []
    date_strings(first_exercise_day, last_exercise_day).each do |day|
      rate = num_of_exercises_done_on(day) / num_of_exercises.to_f * 100
      result.push([day, rate.round])
    end

    result
  end

  def exercise_completion_rates_by_exercise
    return nil if num_of_exercises <= 0 || has_not_started_exercising

    result = []
    get_all_exercises.each do |exercise|
      result.push([exercise.name_with_group, exercise.days_done])
    end
    result
  end

  def exercise_completion_rates_by_weekday
    return nil if num_of_exercises <= 0 || has_not_started_exercising

    result = Date::ABBR_DAYNAMES.map { |day_name| [day_name, 0] }.to_h

    date_strings(first_exercise_day, last_exercise_day).each do |day|
      weekday = Date.parse(day).strftime("%a")
      result[weekday] += num_of_exercises_done_on(day)
    end

    result
  end

  private

  def date_strings(from, to)
    (Date.parse(from)..Date.parse(to)).map { |date| date.strftime("%Y%m%d") }
  end

end

class Therapist < User
  def self.get_all
    super.select { |user| user.role == :therapist }
  end

  def self.get_all_therapists_locally
    get_all_users_locally.select { |user| user.role == :therapist }
  end
end

class Admin < User
  def self.get_all
    super.select { |user| user.role == :admin }
  end

  def self.get_all_admins_locally
    get_all_users_locally.select { |user| user.role == :admin }
  end
end

class Amazon_AWS
  REGION = "ap-southeast-2"

  BUCKETS = { data: 'rehab-buddy-data', images: 'rehab-buddy-images'}
  TEST_BUCKETS = { data: 'auto-test-rehab-buddy-data', images: 'auto-test-rehab-buddy-images'}

  def self.bucket_name(bucket)
    ENV['RACK_ENV'] == 'production' ? BUCKETS[bucket] : TEST_BUCKETS[bucket]
  end

  # returns an array of objects downloaded
  def self.download_all_objs(bucket:, prefix: "")

    s3 = Aws::S3::Resource.new(region: REGION)

    result = []
    s3.bucket(bucket_name(bucket)).objects(prefix: prefix).each do |obj|

      result.push(obj.get.body.string)
    end
    result
  end

  def self.delete_all_objs(bucket:, prefix:)
    s3 = Aws::S3::Resource.new(region: REGION)

    s3.bucket(bucket_name(bucket)).objects(prefix: prefix).each do |obj|
      obj.delete
    end
  end

  def self.upload_obj(source_obj:, bucket:, dest_path:)

    s3 = Aws::S3::Resource.new(region: REGION)

    key = dest_path
    obj = s3.bucket(bucket_name(bucket)).object(key)

    # upload file
    # key = File.basename(local_path).prepend(target_folder)
    # obj.upload_supp_file(local_path)

    obj.put(body: source_obj)
  end

  # def self.upload_obj(key:, body:, target_folder: "")
  #   s3 = Aws::S3::Client.new(region: REGION)

  #   s3.put_object(bucket: BUCKET, key: target_folder + key, body: body)
  # end

  # saves file to local_path, or returns contents of file as string if local_path not specified

  def self.obj_exists?(key:, bucket:)
    s3 = Aws::S3::Resource.new(region: REGION)

    s3.bucket(bucket_name(bucket)).object(key).exists?
  end

  def self.download_obj(local_path: nil, key:, bucket:)
    return nil unless obj_exists?(key: key, bucket: bucket)

    s3 = Aws::S3::Resource.new(region: REGION)

    obj = s3.bucket(bucket_name(bucket)).object(key)

    if local_path
      obj.get(response_target: local_path)
    else
      obj.get.body.string
    end
  end

  def self.delete_obj(bucket:, key:)
    s3 = Aws::S3::Resource.new(region: REGION)

    s3.bucket(bucket_name(bucket)).object(key).delete
  end

  def self.copy_obj(source_bucket:, source_key:, target_bucket:, target_key:)
    s3 = Aws::S3::Client.new(region: REGION)
    s3.copy_object(bucket: bucket_name(target_bucket), copy_source: bucket_name(source_bucket) + '/' + source_key, key: target_key)
  end

  def self.move_obj(source_bucket:, source_key:, target_bucket:, target_key:)
    copy_obj(source_bucket: source_bucket,
             source_key: source_key,
             target_bucket: target_bucket,
             target_key: target_key)
    delete_obj(bucket: source_bucket, key: source_key)
  end
end