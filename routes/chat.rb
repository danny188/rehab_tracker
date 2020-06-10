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

  # mark messages read by therapist
  if session[:user].role == :therapist
    @patient.unread_pt_msg = false
    @patient.save
  # mark messages read by patient
  elsif session[:user].role == :patient
    @patient.unread_therapist_msg = false
    @patient.save
  end

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

post "/users/:username/chat_with_therapist/mark_read" do
  data_obj = JSON.parse(request.body.read)

  @patient = User.get(params[:username])

  if data_obj['readBy'] == 'therapist'
    @patient.unread_pt_msg = false
  elsif data_obj['readBy'] == 'patient'
    @patient.unread_therapist_msg = false
  end

  @patient.save
end

post "/users/:username/chat_with_therapist/stream",  provides: 'text/event-stream' do
  unless verify_user_access(min_authorization: :patient, required_username: params[:username])
    redirect "/access_error"
  end

  content_type 'text/event-stream'

  @patient = User.get(params[:username])
  # chat_msg = (session[:user].first_name || session[:user].username) + " (#{Time.now.strftime("%d/%m/%y %k:%M")}); " + params[:new_msg]

  @patient.chat_history = [] unless @patient.chat_history
  address_user_str = session[:user].first_name || session[:user].username
  @patient.chat_history.push([address_user_str, Time.now.strftime("%d/%m/%y %k:%M"), params[:new_msg]])


  if session[:user].role == :therapist
    @patient.unread_therapist_msg = true
  elsif session[:user].role == :patient
    @patient.unread_pt_msg = true
  end

  @patient.save

    settings.connections.each_with_index { |out, index|
      # puts "data: {\"for_user\": \"#{params[:username]}\", \"msg\": \" #{session[:user].username + ': ' + params[:new_msg]}\"\n\n"
        if settings.connection_users[index] == params[:username]
          out << "data: {\"for_user\": \"#{address_user_str}\", \"msg\": \"#{params[:new_msg]}\"}\n\n"
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