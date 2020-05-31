
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
  def get_group(hierarchy = TOP_HIERARCHY)Array
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
  def get_exercise(exercise_name, group_hierarchy = TOP_HIERARCHYCHY)
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
