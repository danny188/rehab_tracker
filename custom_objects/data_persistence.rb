module DataPersistence
  def upload_file_to_local(source:, dest:)
    # create directory if doesn't exist
    dir_name = File.dirname(dest)

    unless File.directory?(dir_name)
      FileUtils.mkdir_p(dir_name)
    end

    FileUtils.cp(source, dest)
  end

  # upload public files associated with exercise library or patient's exercises
  def upload_supp_file(file_obj:, dest_path:)
    Amazon_AWS.upload_obj(source_obj: file_obj,
      bucket: :images,
      dest_path: dest_path)
  end

  def delete_supp_file(key:)
    Amazon_AWS.delete_obj(key: key, bucket: :images)
  end

  def public_path
    File.expand_path("../public", __FILE__)
  end


  def save_to_local_filesystem()
    store = YAML::Store.new(self.class.path(self.name))
    store.transaction do
      store = self
    end
  end

  def delete_file_from_local_filesystem(path)
    FileUtils.rm(path)
  end

  def save
    # case ENV["RACK_ENV"]
    # # when 'testing_local'
    # #   save_to_local_filesystem
    # # when 'testing_s3', 'production_s3'
    # when 'production', 'development'
    #   Amazon_AWS.upload_obj(source_obj: self.to_yaml,
    #   bucket: :data,
    #   dest_path: "#{file_prefix + self.name}.store")
    # end

    Amazon_AWS.upload_obj(source_obj: self.to_yaml,
    bucket: :data,
    dest_path: "#{file_prefix + self.name}.store")
  end
end
