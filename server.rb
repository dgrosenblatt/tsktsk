require 'dotenv'
require 'sinatra'
require 'sinatra/reloader'
require 'pg'
require 'pry'
require 'twilio-ruby'

Dotenv.load

configure do
  Twilio.configure do |config|
    config.account_sid = ENV['TWILIO_SID']
    config.auth_token = ENV['TWILIO_TOKEN']
  end
end


def db_connection
  begin
    connection = PG.connect(dbname: 'tasks')
    yield(connection)
  ensure
    connection.close
  end
end

def list_tasks
  db_connection { |con| con.exec('select * from tasks order by start desc;') }.to_a
end

def save(task)
  db_connection do |con|
    con.exec_params(
      'insert into tasks (description, start, points) values ($1, now(), 0)', [task]
    )
  end
end

def finish(task_id)
  db_connection do |con|
    con.exec_params(
      'update tasks set finish = now() where id = $1', [task_id]
    )
  end
end

def upvote(task_id, new_score) # Need to figure out how to increase vote column by 1
  db_connection do |con|
    con.exec_params(
      'update tasks set points = $1 where id = $2', [new_score, task_id]
    )
  end
end

def current_score(task_id)
  db_connection do |con|
    con.exec_params(
      'select points from tasks where id = $1', [task_id]
    )
  end
end

def twilio_client
  Twilio::REST::Client.new
end

def twilio_count
  db_connection { |con| con.exec_params('select * from twilio') }.to_a.first["number_of_messages"].to_i
end

def twilio_increment
  new_count = twilio_count + 1
  db_connection { |con| con.exec_params('update twilio set number_of_messages = $1', [new_count])}
end

def twilio_messages
  twilio_client.messages.list(to:'+13392300494')
end

get '/tasks' do
  if twilio_count < twilio_messages.length
    save(twilio_messages.first.body)
    twilio_increment
  end
  #sort == recent => does nothing right now
  @tasks = list_tasks
  @sort = params[:sort]
  @tasks.keep_if {|task| task["finish"]} if @sort == "done"
  @tasks.keep_if {|task| !task["finish"]} if @sort == "todo"
  @tasks.sort_by! {|task| -task["points"].to_i} if @sort == "pts"
  erb :index
end

post '/tasks' do
  @task = params["new_task"]
  save(@task)
  redirect '/tasks'
end

get '/tasks/finished/:id' do
  @task_id = params["id"].to_i
  finish(@task_id)
  redirect '/tasks'
end


# put into url for get '/tasks' to keep tasks sorted after voting
get '/tasks/upvote/:id' do
  @task_id = params["id"].to_i
  @new_score = current_score(@task_id).to_a[0]["points"].to_i + 1
  upvote(@task_id, @new_score) # Need to complete upvote method first!
  redirect '/tasks'
end
