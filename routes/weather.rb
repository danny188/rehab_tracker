get "/weather" do
  url = "https://api.openweathermap.org/data/2.5/weather?id=2147714&appid=#{ENV['OPEN_WEATHER_MAP_API_KEY']}&units=metric"
  uri = URI(url)
  response = Net::HTTP.get(uri)
  @data = JSON.parse(response)
  @weather_icon_url = "http://openweathermap.org/img/wn/#{@data['weather'][0]['icon']}@2x.png"
  @cur_time = Time.now.strftime("%d/%m %a %I:%M %p")

  logger.info "#{session[:user].username if session[:user]} checks weather"

  weather_btn_popover_content = <<-HEREDOC
  <div class="text-center">
  <p>#{@cur_time}</p>
  <img width="120px" height="120px" id="wicon"  src="#{@weather_icon_url}" alt="Weather icon">
  <p>#{ @data['weather'][0]['description'] }</p>
  <hr>
  <p>Current Temp: #{@data['main']['temp']} °C</p>
  <p>Max Temp: #{@data['main']['temp_max']} °C</p>
  <p>Min Temp: #{@data['main']['temp_min']} °C</p>

  </div>
  HEREDOC
end