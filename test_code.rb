require 'aws-sdk-s3'
require 'stringio'
require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "sinatra/content_for"

region = "ap-southeast-2"
bucket = "rehab.tracker"

s3_client = Aws::S3::Client.new(region: region)

s3 = Aws::S3::Resource.new(region: region)

#s3.put_object(bucket: "rehab.tracker", key: "file1", body: "My first s3 object")

# obj = s3.bucket('rehab.tracker').object('THREADS')

# #resp = s3.get_object(bucket: bucket, key: 'THREADS')

# strio = StringIO.new

# puts obj.get.body.string

resp = s3_client.get_object(bucket: bucket, key: 'file1', response_target: "./result.txt")
# puts resp.body.string


# yaml store

get "/" do
  # erb :layout
  # ex = Exercise.new("bridge", 30)
  # ex2 = Exercise.new("hip abd", 20)
  # store = YAML::Store.new "test.store"

  # store.transaction do
  #   store["exercise"] = [ex, ex2]
  # end

  store = YAML::Store.new("test.store")
  exercises = nil
  store.transaction do
    exercises = store['exercise']

  end

  result = ""
  result2 = nil
  exercises.each do |ex|
    result += ex.name + " " + ex.reps.to_s + " "
  end

  result
end
