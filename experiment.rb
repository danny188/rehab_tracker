class Exercise
  attr_accessor :name, :reps, :patient

  def initialize(name, reps = 30, patient)
    @name = name
    @reps = reps
    @patient = patient
  end

  def to_s
    "#{patient.username}"
  end
end

class Patient
  attr_accessor :username, :exercise

  def initialize(username)
    @username = username
  end

  def to_s
    "#{exercise.name}"
  end
end

bob = Patient.new('Bob')
exercise1 = Exercise.new('push-up', 30, bob)
bob.exercise = exercise1

puts bob.exercise.name # push up
puts exercise1.patient.username # bob

puts bob
puts exercise1

a = 1
b = 2
p c = [a,b]
p a = [c,b]