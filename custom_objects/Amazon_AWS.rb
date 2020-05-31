class Amazon_AWS
  REGION = "ap-southeast-2"

  # BUCKETS = { data: 'rehab-buddy-data', images: 'rehab-buddy-images'}
  BUCKETS = { data: ENV['S3_DATA_BUCKET'], images: ENV['S3_IMAGES_BUCKET'] }
  TEST_BUCKETS = { data: 'auto-test-rehab-buddy-data', images: 'auto-test-rehab-buddy-images'}

  def self.bucket_name(bucket)
    ENV['RACK_ENV'] == 'production' ? BUCKETS[bucket] : TEST_BUCKETS[bucket]
  end

  # returns an array of objects downloaded
  def self.download_all_objs(bucket:, prefix: "")

    s3 = Aws::S3::Resource.new(region: REGION)

    result = []
    s3.bucket(bucket_name(bucket)).objects(prefix: prefix).each do |obj|

      result.push(obj.get.body.string)
    end
    result
  end

  def self.delete_all_objs(bucket:, prefix:)
    s3 = Aws::S3::Resource.new(region: REGION)

    s3.bucket(bucket_name(bucket)).objects(prefix: prefix).each do |obj|
      obj.delete
    end
  end

  def self.upload_obj(source_obj:, bucket:, dest_path:)

    s3 = Aws::S3::Resource.new(region: REGION)

    key = dest_path
    obj = s3.bucket(bucket_name(bucket)).object(key)

    # upload file
    # key = File.basename(local_path).prepend(target_folder)
    # obj.upload_supp_file(local_path)

    obj.put(body: source_obj)
  end

  # def self.upload_obj(key:, body:, target_folder: "")
  #   s3 = Aws::S3::Client.new(region: REGION)

  #   s3.put_object(bucket: BUCKET, key: target_folder + key, body: body)
  # end

  # saves file to local_path, or returns contents of file as string if local_path not specified

  def self.obj_exists?(key:, bucket:)
    s3 = Aws::S3::Resource.new(region: REGION)

    s3.bucket(bucket_name(bucket)).object(key).exists?
  end

  def self.download_obj(local_path: nil, key:, bucket:)
    return nil unless obj_exists?(key: key, bucket: bucket)

    s3 = Aws::S3::Resource.new(region: REGION)

    obj = s3.bucket(bucket_name(bucket)).object(key)

    if local_path
      obj.get(response_target: local_path)
    else
      obj.get.body.string
    end
  end

  def self.delete_obj(bucket:, key:)
    s3 = Aws::S3::Resource.new(region: REGION)

    s3.bucket(bucket_name(bucket)).object(key).delete
  end

  def self.copy_obj(source_bucket:, source_key:, target_bucket:, target_key:)
    s3 = Aws::S3::Client.new(region: REGION)
    s3.copy_object(bucket: bucket_name(target_bucket), copy_source: bucket_name(source_bucket) + '/' + source_key, key: target_key)
  end

  def self.move_obj(source_bucket:, source_key:, target_bucket:, target_key:)
    copy_obj(source_bucket: source_bucket,
             source_key: source_key,
             target_bucket: target_bucket,
             target_key: target_key)
    delete_obj(bucket: source_bucket, key: source_key)
  end
end