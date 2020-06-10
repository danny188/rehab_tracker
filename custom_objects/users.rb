
class User
  attr_accessor :username, :pw, :first_name, :last_name, :email,
  :change_pw_next_login, :account_status, :deactivate_time, :last_login_time

  include DataPersistence

  alias :name :username

  INACTIVE_DAYS_THRESHOLD = 20

  SlimUser = Struct.new(:username, :role)

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

  # returns a slimmed down version of User object
  def slim
    SlimUser.new(self.username, self.role)
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
  attr_accessor :exercise_collection, :wellness_ratings, :last_updated,
                :last_review_date, :last_review_by, :last_updated,
                :chat_history
  include GroupOperations

  alias_method :top_collection, :exercise_collection

  MAX_NUM_EXERCISES = 20

  def initialize(username, pw)
    super
    @exercise_collection = ExerciseGroup.new(TOP_GROUP)
    @chat_history = []
  end

  def self.get_all
    super.select { |user| user.role == :patient }
  end

  def self.get_all_patients_locally
    get_all_users_locally.select { |user| user_role(user) == :patient }
  end

  def move_exercise_up(exercise_name, group_name)
    if group_name && !group_name.empty?
      exercise_list = self.exercise_collection.get_subgroup(group_name).items
    else
      exercise_list = self.exercise_collection.items
    end

    exercise_1_index = exercise_list.find_index { |exercise| exercise.name == exercise_name }
    exercise_2_index = exercise_1_index - 1 % exercise_list.size

    swap_element_position(exercise_list, exercise_1_index, exercise_2_index)
  end

  def move_exercise_down(exercise_name, group_name)
    if group_name && !group_name.empty?
      exercise_list = self.exercise_collection.get_subgroup(group_name).items
    else
      exercise_list = self.exercise_collection.items
    end

    exercise_1_index = exercise_list.find_index { |exercise| exercise.name == exercise_name }
    exercise_2_index = (exercise_1_index + 1) % exercise_list.size

    swap_element_position(exercise_list, exercise_1_index, exercise_2_index)
  end

  def move_group_up(group_name)
    grp_1_index = self.exercise_collection.subgroups.find_index { |group| group.name == group_name }
    grp_2_index = (grp_1_index - 1) % self.exercise_collection.subgroups.size

    swap_element_position(self.exercise_collection.subgroups, grp_1_index, grp_2_index)
  end

  def move_group_down(group_name)
    grp_1_index = self.exercise_collection.subgroups.find_index { |group| group.name == group_name }
    grp_2_index = (grp_1_index + 1) % self.exercise_collection.subgroups.size

    swap_element_position(self.exercise_collection.subgroups, grp_1_index, grp_2_index)
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
  def move_exercise_supp_file(exercise_name, new_exercise_name, filename, from_group_hierarchy, to_group_hierarchy)
    source_key = "images/#{self.username}/#{make_group_query_str(from_group_hierarchy)}/#{exercise_name}/#{filename}"
    target_key = "images/#{self.username}/#{make_group_query_str(to_group_hierarchy)}/#{new_exercise_name}/#{filename}"

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

  def swap_element_position(ary, index_1, index_2)
    return if ary.size == 1

    tmp = ary[index_1]
    ary[index_1] = ary[index_2]
    ary[index_2] = tmp
  end

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

