# email notifications
post "/users/:username/send-notification" do
  unless verify_user_access(min_authorization: :therapist)
    redirect "/access_error"
  end

  @event = params[:event]
  @user = User.get(params[:username])

  subscribed = @user.subscriptions[@event.to_sym]

  case @event
    when 'exercise_update'
      if subscribed
        response = @user.send_exercises_updated_email

        if response.status_code == 202
          session[:success] = "Exercise Update Notification Email Sent"
        else
          session[:error] = "Error in sending Exercise Update Notification Email"
        end
      else
        session[:warning] = "User did not subscribe to Exercise Update Notification Email"
      end
      redirect "/users/#{params[:username]}/exercises"
    when 'exercise_reminder'
      # @user.send_exercises_reminder_email if subscribed
    when 'new_chat_msg'
  end
end