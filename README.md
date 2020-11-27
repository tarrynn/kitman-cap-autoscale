# Kitman CAP Autoscale

Capistrano tasks for interacting with AWS Autoscaling

Supports two operations

1. ``autoscaling_event_in_progress?`` check to see if an autoscaling activity is currently in progress
2. ``hosts_in_autoscaling_group`` Retrieve the public DNS hostnames of all instances in an Autoscaling group

Install
=======

Add it as a gem:

```ruby
    gem "kitman-cap-autoscale", require: false
```

Add to config/deploy.rb:

```ruby
    require 'kitman-cap-autoscale'
```

Add to config/deploy/(staging | production).rb:

```ruby
set :autoscaling_group_name, '<Auto Scaling Group Name>'

set_servers_from_autoscaling_group fetch(:autoscaling_group_name)

```


Available tasks
===============

    deploy:check_autoscaling_event_in_progress      # Check to see if an active autoscaling event is in progress



Copyright (c) 2016 [Kitman Labs], released under the MIT license
