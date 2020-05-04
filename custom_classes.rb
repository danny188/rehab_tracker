require 'aws-sdk-s3'
require 'stringio'
require 'set'

class Exercise
  attr_accessor :name, :instructions, :reps, :sets, :duration,
                :id, :added_date, :record_of_days,
                :comment_by_patient, :comment_by_therapist,
                :pictures, :image_links

  Comment = Struct.new(:author, :text, :last_modified)

  def initialize(name, reps = '30', sets = '3')
    @name = name
    @reps = reps
    @sets = sets
    @record_of_days = Set.new
    @image_links = []
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
end

class User
  attr_accessor :username, :pw, :first_name, :last_name, :email,
                :change_pw_next_login

  def initialize(username, pw)
    @username = username
    @pw = pw
    change_pw_next_login = false
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
end

class Patient < User
  attr_accessor :exercises, :wellness_ratings, :last_updated

  class ExerciseNameNotUniqueErr < StandardError; end

  Wellness = Struct.new(:date, :rating)

  def initialize(username, pw)
    @exercises = []
    super
  end

  def add_exercise(exercise_name)
    raise ExerciseNameNotUniqueErr if exercises.any? { |exercise| exercise.name == exercise_name }

    exercises.push(Exercise.new(exercise_name))
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
end

class Admin < User
end

class Amazon_AWS
  REGION = "ap-southeast-2"
  BUCKET = "rehab.tracker"

  def self.upload_file(local_path:, target_folder:)
    s3 = Aws::S3::Resource.new(region: REGION)

    key = File.basename(local_path).prepend(target_folder)

    obj = s3.bucket(BUCKET).object(key)

    obj.upload_file(local_path)
  end

  def self.upload_obj(key:, body:, target_folder: "")
    s3 = Aws::S3::Client.new(region: REGION)

    s3.put_object(bucket: BUCKET, key: target_folder + key, body: body)
  end

  # saves file to local_path, or returns contents of file as string if local_path not specified
  def self.download(local_path:, key:, from_folder:)
    s3 = Aws::S3::Resource.new(region: REGION)

    obj = s3.bucket(BUCKET).object(from_folder + key)

    if local_path
      obj.get(response_target: local_path)
    else
      obj.get.body.string
    end
  end
end