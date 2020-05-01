require 'aws-sdk-s3'
require 'stringio'
require 'set'

class Exercise
  attr_accessor :name, :instructions, :reps, :sets, :duration,
                :id, :added_date, :record_of_days,
                :comment_by_patient, :comment_by_therapist,
                :pictures, :image_links

  Comment = Struct.new(:author, :text, :last_modified)

  def initialize(name, reps = 30, sets = 3)
    @name = name
    @reps = reps
    @sets = sets
    @record_of_days = Set.new
    @image_links = []
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
end

class User
  attr_accessor :username, :pw, :first_name, :last_name, :email

  def initialize(username, pw)
    @username = username
    @pw = pw
  end

  def to_s
    first_name
  end

  def role
    self.class.to_s.downcase.to_sym
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