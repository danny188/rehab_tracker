
class ExerciseTemplate
  include DataPersistence
  include GroupOperations

  attr_accessor :name, :instructions, :reps, :sets,
                :duration, :image_links, :exercise_library_name,
                :group_hierarchy

  FILES_LIMIT = 4
  FILE_UPLOAD_SIZE_LIMIT_MB = 3.0
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

class TemplateGroup < Group
  # alias_method :add_template, :add_item
  # alias_method :get_template, :get_item
  # alias_method :delete_template, :delete_item
  # alias_method :each_template, :each_item
end

class ExerciseLibrary
  include DataPersistence
  include GroupOperations

  attr_accessor :name, :templates, :template_collection, :last_updated

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