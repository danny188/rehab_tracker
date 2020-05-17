# ENV["RACK_ENV"] = "test"
# ENV['custom_env'] = 'testing_s3'

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


class Group_Class_Test < Minitest::Test
  def test_duplicate_from
    @group_1 = Group.new('group 1')
    @group_1.add_item('item 1')
    @group_1.add_subgroup_by_name('group_1_sub_1')
    @group_1.get_subgroup('group_1_sub_1').add_item('sub 1 item 1')

    @group_2 = Group.deep_copy(@group_1)
    assert_equal @group_1.name, @group_2.name
    assert @group_2.get_subgroup('group_1_sub_1')
    assert_includes(@group_2.get_subgroup('group_1_sub_1').items, 'sub 1 item 1')

    # test modifying original copy doesn't mutate new copy
    @group_1.get_subgroup('group_1_sub_1').items.first.concat('appended')
    assert_includes(@group_2.get_subgroup('group_1_sub_1').items, 'sub 1 item 1')
  end
end

class ExerciseLibrary_Class_Test < Minitest::Test
  def setup
    @lib = ExerciseLibrary.new('main')

  end

  def test_get_top_group
    assert @lib.get_group(create_group_hierarchy)
  end
end



class Patient_Class_Test < Minitest::Test
  def setup
    @pt = Patient.new('patient1', 'secret')
  end

  def teardown

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

  def test_add_group
    @pt.add_group('stretches', create_group_hierarchy)

    assert @pt.get_group(create_group_hierarchy + ['stretches'])
  end

  def test_delete_group
    @pt.add_group('stretches', create_group_hierarchy)
    @pt.delete_group('stretches', create_group_hierarchy)

    refute @pt.get_group(create_group_hierarchy + ['stretches'])
  end

  def test_move_exercise_between_subgroups
    @pt.add_group('stretches', create_group_hierarchy)
    @pt.add_group('strengthening', create_group_hierarchy)

    exercise = Exercise.new('calf stretch')
    from_group_hierarchy = create_group_hierarchy('strengthening')
    to_group_hierarchy = create_group_hierarchy('stretches')

    @pt.add_exercise_by_name(exercise.name, from_group_hierarchy)
    @pt.move_exercise(exercise.name, from_group_hierarchy, to_group_hierarchy )

    assert @pt.get_exercise(exercise.name, to_group_hierarchy)
    refute @pt.get_exercise(exercise.name, from_group_hierarchy)
  end

  def test_move_exercise_between_top_level_and_subgroup
    @pt.add_group('stretches', create_group_hierarchy)

    exercise = Exercise.new('calf stretch')
    from_group_hierarchy = create_group_hierarchy()
    to_group_hierarchy = create_group_hierarchy('stretches')

    @pt.add_exercise_by_name(exercise.name, from_group_hierarchy)
    @pt.move_exercise(exercise.name, from_group_hierarchy, to_group_hierarchy )

    assert @pt.get_exercise(exercise.name, to_group_hierarchy)
    refute @pt.get_exercise(exercise.name, from_group_hierarchy)
  end

  def test_move_exercise_error_exercise_name_not_unique
    @pt.add_group('stretches', create_group_hierarchy)
    exercise = Exercise.new('calf stretch')

    from_group_hierarchy = create_group_hierarchy()
    to_group_hierarchy = create_group_hierarchy('stretches')

    @pt.add_exercise_by_name(exercise.name, from_group_hierarchy)
    @pt.add_exercise_by_name(exercise.name, to_group_hierarchy)

    assert_raises GroupOperations::ItemNameInGroupNotUniqueErr do
      @pt.move_exercise(exercise.name, from_group_hierarchy, to_group_hierarchy )
    end
  end
end

class Rehab_Tracker_Test < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup

  end

  def sign_in(username, password)
    post "/login", {username: username, password: password}
  end

  def sign_out()
    post "/user/logout"
  end

  def teardown
     # Amazon_AWS.delete_all_objs(bucket: :data, prefix: "")
  end

  def create_patient_nina
    @patient_username = "nina"
    @patient_filename = "user_" + @patient_username + ".store"
    File.open("test/" + @patient_filename) do |file|
      Amazon_AWS.upload_obj(source_obj: file,
                            bucket: :data,
                            dest_path: @patient_filename)
    end
  end

  def delete_patient_nina
    Amazon_AWS.delete_obj(bucket: :data, key: @patient_filename)
  end

  def create_admin_admin_1

    File.open("test/" + @admin_filename) do |file|
      Amazon_AWS.upload_obj(source_obj: file,
                            bucket: :data,
                            dest_path: @admin_filename)
    end
  end

  def test_sign_in_as_patient
    create_patient_nina

    post "/login", {username: @patient_username, password: 'secret'}
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status

    assert_includes last_response.body, "Nina's Exercises"

    delete_patient_nina
  end

  def test_sign_in_as_admin
    @admin_filename = "user_admin_1.store"
    create_admin_admin_1

    post "/login", {username: 'admin_1', password: 'secret1'}

    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Here is your admin panel"
  end

  def test_create_exercise_template

  end

end

