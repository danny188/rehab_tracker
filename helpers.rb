helpers do
  def format_date(date)
    date.strftime("%a %d/%m")
  end

  def address_user(user)
    user.first_name || user.username
  end

  def full_name_plus_username(user)
    return '' unless user

    if nil_or_empty?(user.full_name)
      user.username
    else
      user.full_name + ' (@' + user.username + ')'
    end
  end

  # toggles sort direction
  def sort_direction(dir)
    if nil_or_empty?(dir) || dir.downcase == 'desc'
      'asc'
    else
      'desc'
    end
  end

  # emails rehab buddy admin of events (e.g. account creations, pw resets, etc..)
  # returns SendGrid Response object
  def email_rb_admin(subject, text)
    from = SendGrid::Email.new(email: ENV['REHAB_BUDDY_EMAIL'])
    to = SendGrid::Email.new(email: ENV['REHAB_BUDDY_EMAIL'])
    content = SendGrid::Content.new(type: 'text/plain', value: text)
    mail = SendGrid::Mail.new(from, subject, to, content)

    sg = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY'])
    response = sg.client.mail._('send').post(request_body: mail.to_json)
  end

  def time_ago(timestamp)
    return nil unless timestamp

    delta = Time.now - timestamp
    case delta
      when 0..30         then "just now"
      when 31..119       then "about a minute ago"
      when 120..3599     then "#{(delta / 60).round} minutes ago"
      when 3600..86399   then "#{(delta / 3600).round} hours ago"
      when 86400.. then "#{(delta / 86400).round} days ago"
    end
  end

  def days_ago(timestamp)
    return 0 unless timestamp
    (Time.now - timestamp) / 86400
  end

  def checkbox_display_class(day_idx)
    case day_idx
    when 0..1
      "d-none d-lg-block d-print-none"
    when 2..3
      "d-none d-lg-block d-print-block"
    when 4..5
      "d-none d-md-block d-print-block"
    when 6
      'd-print-block'
    end
  end

  # set checkbox state
  def check_value(test_date, dates_ary)
    "checked" if dates_ary.include?(test_date)
  end

  def reps_and_sets_str(exercise)
    reps_str = "#{exercise.reps} " + (exercise.reps.to_i > 1 ? "reps" : "rep") unless exercise.reps.to_s.empty?
    sets_str = "#{exercise.sets} " + (exercise.sets.to_i > 1 ? "sets" : "set") unless exercise.sets.to_s.empty?
    [reps_str, sets_str].compact.join(", ")
  end

  def active_class(test_path)
    "active" if request.path_info == test_path
  end

  # takes a hash query str parameter name/value pairs, returns a query str
  def create_full_query_str(param_hash)
    ary_of_query_strings = param_hash.map { |key, value| (key.to_s + '=' + value) unless value.to_s.empty? }
    '?' + ary_of_query_strings.compact.join('&')
  end
end

def user_role(user_obj)
  if user_obj.is_a?(Patient)
    :patient
  elsif user_obj.is_a?(Therapist)
    :therapist
  elsif user_obj.is_a?(Admin)
    :admin
  end
end

def get_end_date(end_date_str, day_step)
  if nil_or_empty?(end_date_str) || !valid_date_str(end_date_str)
    Date.today
  else
    Date.parse(end_date_str) + day_step
  end
end

def logged_in_user
  if session[:user]
    session[:user].username
  else
    'unknown user'
  end
end

def valid_date_str(date_str)
  date_str =~ /^(19|20)\d\d(0[1-9]|1[012])(0[1-9]|[12][0-9]|3[01])$/
end

def remove_trailing_nils_and_emptys(ary)
  until (!ary[-1].nil? && !ary[-1].empty?) || ary.empty?
    ary.pop
  end
end

def create_group_hierarchy(*groups)
  remove_trailing_nils_and_emptys(groups)
  groups.unshift(GroupOperations::TOP_GROUP) if groups[0] != GroupOperations::TOP_GROUP
  groups
end

def exercise_library_title(group_hierarchy)
  case group_hierarchy.size
  when 1
    "Exercise Library"
  when 2
    "Exercise Library #{'(Group: ' + group_hierarchy[1] + ')'}"
  when 3
    "Exercise Library #{'(Group: ' + group_hierarchy[1] + '/' + group_hierarchy[2] +')'}"
  end
end

def upload_file(source:, dest:)
  # create directory if doesn't exist
  dir_name = File.dirname(dest)

  unless File.directory?(dir_name)
    FileUtils.mkdir_p(dir_name)
  end

  FileUtils.cp(source, dest)
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def nil_or_empty?(value)
  value.nil? || value.empty?
end

def invalid_name(name)
  name =~ /[^a-z0-9\s]/i
end

def invalid_username(name)
  name =~ /[^-_a-z0-9\s]/i
end

# returns array of dates of past 'n' days starting from given date (as Date object)
def past_num_days(num: 7, from:)
  result = []
  (num).times do |n|
    result.unshift(from - n)
  end
  result
end

def log_date_if_therapist_doing_edit(patient)
  # record review date by therapist whenever updating patient
  if session[:user].role == :therapist
    patient.last_review_date = Date.today
    patient.last_review_by = session[:user].username
  end
end


def home_page_for(user)
  return "/about" unless user

  case user.role
  when :patient
    "/users/#{user.username}/exercises"
  when :therapist
    "/users/#{user.username}/therapist_dashboard"
  when :admin
    "/users/#{user.username}/admin_dashboard"
  end
end

def redirect_to_home_page(user)
  redirect home_page_for(user)
end

# returns true only if username exists and password is valid
def authenticate_user(username, test_pw)
  user = User.get(username) # returns nil if user_exists? == false
  user && BCrypt::Password.new(user.pw) == test_pw
end

# user authentication before every route
def verify_user_access(min_authorization: :public, required_username: nil)
  return false unless session[:user] || min_authorization == :public

  session_role = session[:user].role if session[:user]
  current_role = session_role || :public

  access_level_diff_to_min = ROLES.index(current_role) - ROLES.index(min_authorization)

  role_ok = access_level_diff_to_min >= 0
  username_ok = if required_username
                  (session[:user].username == required_username) ||
                    (access_level_diff_to_min > 0 || current_role == :admin)
                 #  if required_username is provided, access is only granted if
                 #  username matches, OR logged-in user has higher access level (i.e. disallow peer access)
                 #  than required.
                 #
                 #  Admin can view another admin's resources in a limited capacity:
                 #    - admins can view another admin's personal details, but not modify
                 #    - admins can deactivate or change role of another admin
                 #  Currently the only admin- or therapist-specific resource is the profile page
                else
                  true
                end

  role_ok && username_ok
end


# used for local testing
# def save_user_obj(user)
#   store = YAML::Store.new("./data/#{user.username}.store")
#   store.transaction do
#     store[:data] = user
#   end
# end

# used for local testing
# def save_exercises(patient)
#   store = YAML::Store.new("./data/patient/#{patient.username}.store")
#   store.transaction do
#     store[:data][:exercises] = patient.exercises
#   end
# end

# used for local testing
# def delete_local_file(path)
#   FileUtils.rm(path)
# end