require 'sinatra/streaming'
set connections: Array.new
set connection_users: Array.new

get "/users/:username/chat_with_therapist" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  content_type 'text/html'

  @patient = User.get(params[:username])
  @patient.chat_history = [] unless @patient.chat_history

  erb :chat

end

post "/users/:username/chat_with_therapist/clear_history" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  @patient = User.get(params[:username])
  @patient.chat_history = []
  @patient.save

  redirect "/users/#{params[:username]}/chat_with_therapist"
end

post "/users/:username/chat_with_therapist/stream",  provides: 'text/event-stream' do
  # unless verify_user_access(min_authorization: :patient, required_username: params[:username])
  #   redirect "/access_error"
  # end

  content_type 'text/event-stream'

  @patient = User.get(params[:username])
  chat_msg = session[:user].username + ": " + params[:new_msg]
  @patient.chat_history = [] unless @patient.chat_history
  @patient.chat_history.push(chat_msg)
  @patient.save

    settings.connections.each_with_index { |out, index|
      # puts "data: {\"for_user\": \"#{params[:username]}\", \"msg\": \" #{session[:user].username + ': ' + params[:new_msg]}\"\n\n"
        if settings.connection_users[index] == params[:username]
          out << "data: {\"for_user\": \"#{params[:username]}\", \"msg\": \"#{session[:user].username + ': ' + params[:new_msg]}\"}\n\n"
        end
    }
    204
end

get "/users/:username/chat_with_therapist/stream" do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  content_type 'text/event-stream'
  stream :keep_open do |out|
        # Error handling code omitted
        settings.connections.push(out)
        settings.connection_users.push(params[:username])
        out.callback do
          con_idx = settings.connections.index(out)
          if con_idx
            settings.connection_users.delete_at(con_idx)
            settings.connections.delete_at(con_idx)
          end
        end

        out.errback do
          con_idx = settings.connections.index(out)
          if con_idx
            settings.connection_users.delete_at(con_idx)
            settings.connections.delete_at(con_idx)
          end
        end
    end
end