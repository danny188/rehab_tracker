require 'sinatra/streaming'
set connections: []

get "/users/:username/chat_with_therapist" do
  content_type 'text/html'

  erb :chat

end

post "/users/:username/chat_with_therapist/stream" do
  content_type 'text/event-stream'
  # stream :keep_open do |out|
  #       # Error handling code omitted
  #       out << ": hello\n\n" unless out.closed?

  #       out << "data:{\"hi apple 2\"}\n\n"

  #   end
    settings.connections.each { |out| out << "data:#{session[:user].username + ': ' + params[:new_msg]}\n\n" }
    204
end

get "/users/:username/chat_with_therapist/stream" do
  content_type 'text/event-stream'
  stream :keep_open do |out|
        # Error handling code omitted
        settings.connections << out
        out.callback { settings.connections.delete(out) }
        out << ": hello\n\n" unless out.closed?

        # out << "data:{\"hi apple\"}\n\n"

    end

end