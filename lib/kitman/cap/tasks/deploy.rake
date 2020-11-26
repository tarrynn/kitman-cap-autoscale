namespace :deploy do
  desc 'Check if Auto Scaling Event is in progress'
  task :check_autoscaling_event_in_progress do

    group_name = fetch(:autoscaling_group_name)

    if Kitman::Cap::Autoscale.new.autoscaling_event_in_progress?(group_name)
      fail "Failing Deployment - Auto Scaling activity in progress for group: #{group_name}"
    end
  end

  before :starting, :check_autoscaling_event_in_progress
end
