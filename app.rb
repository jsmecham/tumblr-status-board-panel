#
# Tumblr Status Board Panel
#

require "sinatra/reloader" if development?

# Configuration --------------------------------------------------------------

configure do

  set :consumer_key, ENV["TUMBLR_KEY"]
  set :consumer_secret, ENV["TUMBLR_SECRET"]
  set :database_url, ENV["DATABASE_URL"] || "sqlite3://#{Dir.pwd}/database.db"
  set :styles_path, "#{File.dirname(__FILE__)}/public/styles"
  set :scripts_path, "#{File.dirname(__FILE__)}/public/scripts"
  set :session_secret, ENV["SESSION_SECRET"] unless ENV["SESSION_SECRET"].nil?

end

# DataMapper / Model Setup ---------------------------------------------------

DataMapper.setup(:default, settings.database_url)

class User
  include DataMapper::Resource
  property :id, Serial
  property :uid, String
  property :oauth_token, String
  property :oauth_token_secret, String
  property :created_at, DateTime
  property :updated_at, DateTime
end

DataMapper.finalize.auto_upgrade!

# OmniAuth -------------------------------------------------------------------

use OmniAuth::Strategies::Tumblr, settings.consumer_key, settings.consumer_secret

# Tumblr Client --------------------------------------------------------------

enable :sessions

helpers do

  def initialize_tumblr_client
    Tumblr.configure do |config|
      config.consumer_key = settings.consumer_key
      config.consumer_secret = settings.consumer_secret
      config.oauth_token = current_user.oauth_token
      config.oauth_token_secret = current_user.oauth_token_secret
    end
  end

  def tumblr_client
    @client ||= Tumblr::Client.new
  end

  def current_user
    @current_user ||= User.get(session[:user_id]) if session[:user_id]
  end
end

# ----------------------------------------------------------------------------

get '/' do
  if current_user
    initialize_tumblr_client
    @blogs = tumblr_client.info["user"]["blogs"]
    haml :index
  else
    redirect '/login'
  end
end

# Followers ------------------------------------------------------------------

get "/followers/:blog_name" do |blog_name|

  # Authenticate the User by OAuth Access Token
  if session[:user_id].nil?
    user = User.first(:oauth_token => params[:token])
    return status 401 if user.nil?
    session[:user_id] = user.id
  end

  # Request data from Tumblr
  initialize_tumblr_client
  @title     = tumblr_client.blog_info(blog_name)["blog"]["title"]
  @followers = tumblr_client.followers(blog_name, limit: 1)

  haml :followers, :layout => :widget

end

# Authentication -------------------------------------------------------------

get '/auth/:name/callback' do
  auth = request.env["omniauth.auth"]
  user = User.first_or_create({ :uid => auth["uid"]}, {
    :uid => auth["uid"],
    :created_at => Time.now,
    :oauth_token => auth["credentials"]["token"],
    :oauth_token_secret => auth["credentials"]["secret"]
  })
  session[:user_id] = user.id
  redirect '/'
end

get "/login" do
  haml :login
end

get "/logout" do
  session[:user_id] = nil
  redirect '/'
end

# Process Assets -------------------------------------------------------------

get "/styles/:stylesheet.css" do |stylesheet|
  content_type "text/css"
  template = File.read(File.join(settings.styles_path, "#{stylesheet}.sass"))
  Sass::Engine.new(template).render
end

get "/scripts/:script.js" do |script|
  content_type "application/javascript"
  template = File.read(File.join(settings.scripts_path, "#{script}.coffee"))
  CoffeeScript.compile(template)
end
