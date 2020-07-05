class ExerciseGroup < Group
  # alias_method :add_exercise, :add_item
  # alias_method :get_exercise, :get_item
  # alias_method :delete_exercise, :delete_item
  # alias_method :each_exercise, :each_item
end

class Exercise < ExerciseTemplate
  attr_accessor :added_date, :record_of_days, :comment_by_patient, :comment_by_therapist, :patient_username

  Comment = Struct.new(:author, :text, :last_modified)

  def self.new_from_template(template)
    new_ex = Exercise.new(template.name, nil, template.reps, template.sets)
    new_ex.image_links = template.image_links
    new_ex.instructions = template.instructions

    new_ex
  end

  def initialize(name, group_hierarchy = GroupOperations::TOP_HIERARCHY, reps = DEFAULT_REPS, sets = DEFAULT_SETS)
    super
    @record_of_days = Set.new
    @comment_by_therapist = ""
    @comment_by_patient = ""
    @group_hierarchy = TOP_HIERARCHY
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

  def files_path_local(filename:)
    File.join(public_path + "/images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}", filename)
  end

  def image_link_path(filename)
    # case ENV["custom_env"]
    # when 'testing_local'
    #   File.join("/images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}", filename)
    # when 'testing_s3'
    #   "https://#{Amazon_AWS.bucket_name(:images)}.s3-ap-southeast-2.amazonaws.com/#{filename}"
    # when 'production_s3'
    #   "https://#{Amazon_AWS.bucket_name(:images)}.s3-ap-southeast-2.amazonaws.com/#{filename}"
    # end

    "https://#{Amazon_AWS.bucket_name(:images)}.s3-ap-southeast-2.amazonaws.com/#{filename}"
  end

  def add_file(file:, filename:)
    # case ENV['custom_env']
    # when 'testing_local'
    #   upload_file_to_local(source: file, dest: files_path_local(filename))
    #   dest_path = filename
    # else
    #   dest_path = "images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    #   upload_supp_file(file_obj: file, dest_path: dest_path)
    # end

    dest_path = "images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    upload_supp_file(file_obj: file, dest_path: dest_path)

    self.add_image_link(image_link_path(dest_path))
  end

  def delete_file(link)
    filename = File.basename(link)

    # case ENV['custom_env']
    # when 'testing_local'
    #   FileUtils.rm(files_path_local(filename: filename))
    # when 'testing_s3', 'production_s3'
    #   key = "images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    #   delete_supp_file(key: key)
    # end

    key = "images/#{patient_username}/#{make_group_query_str(self.group_hierarchy)}/#{self.name}/#{filename}"
    delete_supp_file(key: key)

    self.delete_image_link(link)
  end
end
