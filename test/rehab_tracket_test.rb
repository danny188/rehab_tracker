ENV["RACK_ENV"] = "test"

require 'minitest/autorun'
require 'rack/test'

require_relative "../rehab_tracker.rb"

# class AWS_Amazon_Test < Minitest::Test
#   def setup

#   end

#   def test_upload_object_to_bucket
#     Amazon_AWS.upload_obj(key: "test123.txt", body: "Carnivore Diet is interesting.")
#     s3 = Aws::S3::Client.new(region: Amazon_AWS::REGION)
#     resp = s3.list_objects_v2(bucket: Amazon_AWS::BUCKET)
#     assert resp.contents.any? { |obj| obj.key == "test123.txt"}
#   end

#   def teardown

#   end
# end

class Rehab_Tracker_Test < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end


end