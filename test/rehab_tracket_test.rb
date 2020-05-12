ENV["RACK_ENV"] = "test"

require 'minitest/autorun'
require 'rack/test'

require_relative "../rehab_tracker.rb"
require_relative "../custom_classes.rb"

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

class Patient_Class_Test < Minitest::Test
  def setup
    @pt = Patient.new('patient1', 'secret')
  end

  def test_can_add_exercise
    squat = Exercise.new('squat')
    @pt.add_exercise(squat)
    exercise = @pt.get_exercise(squat.name)

    assert_equal squat.name, exercise.name
  end

  def test_can_delete_exercise
    squat = Exercise.new('squat')
    @pt.add_exercise(squat)

    @pt.delete_exercise(squat.name)

    refute @pt.has_exercise(squat.name)
    assert_nil @pt.get_exercise(squat.name)
  end

  def test_can_add_exercise_to_subgroup
    hierarchy = ['main', 'leg strength']
    squat = Exercise.new('squat')
    @pt.add_exercise(squat, hierarchy)
    exercise = @pt.get_exercise(squat.name, hierarchy)

    assert_equal squat.name, exercise.name
  end

  def test_can_delete_exercise_from_subgroup
    hierarchy = ['main', 'leg strength']
    squat = Exercise.new('squat')
    @pt.add_exercise(squat, hierarchy)
    @pt.delete_exercise(squat.name, hierarchy)

    refute @pt.has_exercise(squat.name, hierarchy)
    assert_nil @pt.get_exercise(squat.name, hierarchy)
  end

  def test_can_get_all_exercises
    hierarchy1 = ['main', 'leg strength']
    hierarchy2 = ['main', 'stretches']

    squat = Exercise.new('squat')
    hs_stretch = Exercise.new('HS Stretch')

    @pt.add_exercise(squat, hierarchy1)
    @pt.add_exercise(hs_stretch, hierarchy2)

    all_exercises = @pt.get_all_exercises

    assert_includes(all_exercises.map(&:name), squat.name)
    assert_includes(all_exercises.map(&:name), hs_stretch.name)
  end

  def test_mark_done_all_exercises()
    done_date = '20200105'

    hierarchy1 = ['main', 'leg strength']
    hierarchy2 = ['main', 'stretches']

    squat = Exercise.new('squat')
    hs_stretch = Exercise.new('HS Stretch')

    @pt.add_exercise(squat, hierarchy1)
    @pt.add_exercise(hs_stretch, hierarchy2)

    @pt.mark_done_all_exercises(done_date)

    @pt.get_all_exercises.all? { |exercise| assert exercise.done_on?(done_date)}
  end

end

class Rehab_Tracker_Test < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end


end

