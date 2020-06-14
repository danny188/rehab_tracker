# email notifications
post "/users/:username/send-notification" do
  @event = params[:event]
  @user = User.get(params[:username])

  case @event
    when 'exercise_update'
      @user.send_exercises_updated_email if @user.subscriptions[@event.to_sym]
      session[:success] = "Exercise Update Notification Email Sent "
      redirect "/users/#{params[:username]}/exercises"
    when 'exercise_reminder'
      # @user.send_exercises_reminder_email if @user.subscriptions[@event.to_sym]
    when 'new_chat_msg'
  end
end