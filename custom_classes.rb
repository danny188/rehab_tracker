require 'aws-sdk-s3'
require 'stringio'
require 'set'
require 'yaml/store'
require 'fileutils'

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
  def upload_file(file_obj:, dest_path:)
    Amazon_AWS.upload_obj(source_obj: file_obj,
      bucket: :images,
      dest_path: dest_path)
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

  def save
    # save_to_local_filesystem

    Amazon_AWS.upload_obj(source_obj: self.to_yaml,
      bucket: :data,
      dest_path: "#{file_prefix + self.name}.store")

  end
end

class ExerciseTemplate
  include DataPersistence

  attr_accessor :name, :instructions, :reps, :sets, :duration, :image_links, :exercise_library

  FILES_LIMIT = 4
  DEFAULT_REPS = '30'
  DEFAULT_SETS = '3'
  DEFAULT_EXERCISE_LIBRARY = 'main'

  class ExerciseNameNotUniqueErr < StandardError; end
  class ExerciseNameEmpty < StandardError; end

  def initialize(name, reps = DEFAULT_REPS, sets = DEFAULT_SETS)
    @name = name
    @reps = reps
    @sets = sets
    @image_links = []
    @instructions = ''
  end

  def files_path_local(filename)
    File.join(public_path + "/images/exercise_library/#{self.name}", filename)
  end

  def image_link_path(filename)
    case ENV["custom_env"]
    when 'testing_local'
      File.join("/images/exercise_library/#{self.name}", filename)
    when 'testing_s3'
      "https://test-rehab-buddy-images.s3-ap-southeast-2.amazonaws.com/#{filename}"
    when 'production_s3'
      "https://rehab-buddy-images.s3-ap-southeast-2.amazonaws.com/#{filename}"
    end
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

  def get_image_link(idx)
    image_links[idx]
  end

  def delete_image_link(link)
    image_links.delete(link)
  end

  def add_file(file:, filename:)
    case ENV['custom_env']
    when 'testing_local'
      upload_file_to_local(source: file, dest: files_path_local(filename))
      dest_path = filename
    else
      dest_path = "images/exercise_library_#{exercise_library}/#{self.name}/#{filename}"
      upload_file(file_obj: file, dest_path: dest_path)
    end

    self.add_image_link(image_link_path(dest_path))
  end

  def delete_file(link)
    filename = File.basename(link)

    self.delete_image_link(link)
    FileUtils.rm(files_path_local(filename))
  end
end

class ExerciseLibrary
  include DataPersistence

  attr_accessor :name, :templates

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
    @templates = []
  end

  def file_prefix
    "exercise_library_"
  end

  def add_template(template)
    template.exercise_library = self.name
    templates.push(template)
  end

  def get_template(name)
    templates.find { |template| template.name == name }
  end

  def get_all_templates()
    templates
  end

  def delete_template(template_to_delete)
    templates.delete_if { |template| template.name == template_to_delete.name }
  end

  def has_template?(test_template_name)
    templates.any? { |template| template.name == test_template_name }
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

  def initialize(name, reps = DEFAULT_REPS, sets = DEFAULT_REPS)
    super
    @record_of_days = Set.new
    @comment_by_therapist = ""
    @comment_by_patient = ""
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

  def files_path_local(filename:, exercise_name:)
    File.join(public_path + "/images/#{patient_username}/#{exercise_name}", filename)
  end

  def image_link_path(filename)
    case ENV["custom_env"]
    when 'testing_local'
      File.join("/images/#{patient_username}/#{self.name}", filename)
    when 'testing_s3'
      "https://test-rehab-buddy-images.s3-ap-southeast-2.amazonaws.com/#{filename}"
    when 'production_s3'
      "https://rehab-buddy-images.s3-ap-southeast-2.amazonaws.com/#{filename}"
    end
  end

  def add_file(file:, filename:)
    case ENV['custom_env']
    when 'testing_local'
      upload_file_to_local(source: file, dest: files_path_local(filename))
      dest_path = filename
    else
      dest_path = "images/#{patient_username}/#{self.name}/#{filename}"
      upload_file(file_obj: file, dest_path: dest_path)
    end

    self.add_image_link(image_link_path(dest_path))
  end

  def delete_file(link:, username:, exercise_name:)
    filename = File.basename(link)

    self.delete_image_link(link)
    FileUtils.rm(files_path(filename: filename, username: username, exercise_name: exercise_name))
  end
end

class User
  attr_accessor :username, :pw, :first_name, :last_name, :email,
  :change_pw_next_login, :account_status

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
  end

  def activate
    self.account_status = :active
  end
end

class Patient < User
  attr_accessor :exercises, :wellness_ratings, :last_updated

  Wellness = Struct.new(:date, :rating)

  def initialize(username, pw)
    super
    @exercises = []
  end

  def self.get_all
    super.select { |user| user.role == :patient }
  end

  def self.get_all_patients_locally
    get_all_users_locally.select { |user| user_role(user) == :patient }
  end

  def add_exercise_by_name(exercise_name)
    raise ExerciseNameNotUniqueErr if exercises.any? { |exercise| exercise.name == exercise_name }

    exercises.push(Exercise.new(exercise_name))
  end

  def add_exercise(exercise)
    exercise.patient_username = self.username
    exercises.push(exercise)
  end

  def get_exercise(exercise_name)
    exercises.find { |exercise| exercise.name == exercise_name }
  end

  def delete_exercise(exercise_name)
    exercises.delete_if { |exercise| exercise.name == exercise_name }
  end

  def has_exercise(exercise_name)
    exercises.any? { |exercise| exercise.name == exercise_name }
  end

  def mark_done_all_exercises(date)
    exercises.each do |exercise|
      exercise.add_date(date)
    end
  end

  def mark_undone_all_exercises(date)
    exercises.each do |exercise|
      exercise.delete_date(date)
    end
  end

  def done_all_exercises?(date)
    exercises.all? { |exercise| exercise.done_on?(date) }
  end

  # todo: change this to be day specific. num of exercises according to how many
  # active exercises there are on a day, discount
  def num_of_exercises
    exercises.size
  end

  def has_not_started_exercising
    exercises.all? { |exercise| exercise.has_not_been_started? }
  end

  def first_exercise_day
    return nil if has_not_started_exercising
    exercises.map { |exercise| exercise.first_day }.select { |first_day| first_day }.min
  end

  def last_exercise_day
    return nil if has_not_started_exercising
    exercises.map { |exercise| exercise.last_day }.select { |last_day| last_day }.max
  end

  def num_of_exercises_done_on(date)
    return 0 if has_not_started_exercising
    exercises.select { |exercise| exercise.done_on?(date) }.count
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
    exercises.each do |exercise|
      result.push([exercise.name, exercise.days_done])
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

  def num_of_exercises
    exercises.size
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

  def self.get_all_therapists_locally
    get_all_users_locally.select { |user| user.role == :therapist }
  end
end

class Amazon_AWS
  REGION = "ap-southeast-2"

  BUCKETS = { data: 'rehab-buddy-data', images: 'rehab-buddy-images'}
  TEST_BUCKETS = { data: 'test-rehab-buddy-data', images: 'test-rehab-buddy-images'}

  def self.bucket_name(bucket)
    ENV['custom_env'] == 'testing_s3' ? TEST_BUCKETS[bucket] : BUCKETS[bucket]
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

  def self.upload_obj(source_obj:, bucket:, dest_path:)

    s3 = Aws::S3::Resource.new(region: REGION)

    key = dest_path
    obj = s3.bucket(bucket_name(bucket)).object(key)

    # upload file
    # key = File.basename(local_path).prepend(target_folder)
    # obj.upload_file(local_path)

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
end