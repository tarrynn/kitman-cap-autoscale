require 'aws-sdk-ec2'
require 'aws-sdk-autoscaling'
require 'aws-sdk-elasticloadbalancingv2'

module Kitman
  module Cap
    class Autoscale
      STATE_NAME_FILTER = 'instance-state-name'
      RUNNING_STATE = 'running'
      HEALTHY_STATE = 'healthy'

      ACCESS_KEY_ENV_VARIABLE_NAME = 'CAPISTRANO_AWS_ACCESS_KEY'
      SECRET_KEY_ENV_VARIABLE_NAME = 'CAPISTRANO_AWS_ACCESS_SECRET_KEY'
      REGION_ENV_VARIABLE_NAME = 'CAPISTRANO_AWS_REGION'

      attr_accessor :auto_scaling_client
      attr_accessor :ec2_client

      def hosts_in_autoscaling_group(group_name)
        hosts = []

        log "Checking target group: #{group_name}"
        asg = get_autoscaling_group(group_name)

        unless asg.nil?
          load_balancers = get_load_balancers(asg.load_balancer_names)

          raise "No load balancers found for autoscaling group: '#{group}'" if load_balancers.empty?

          log "Discovered #{load_balancers.count} load balancers for autoscaling group: '#{group_name}'"

          target_groups = get_target_groups_from_load_balancers(load_balancers)

          raise "No target groups for autoscaling group: '#{group}'" if target_groups.empty?

          target_groups.each do |group|
            healthy_targets = get_healthy_targets(group)
            log "Discovered #{healthy_targets.count} instances for target group: '#{group}'"
            healthy_targets.each do |instance|
              hosts << public_dns_name_from_instance_id(instance.target.id)
            end
          end

          log "Located hosts #{hosts.join(', ')}"
          hosts
        else
          raise "Autoscaling group: '#{group}' not found"
        end
      end

      def autoscaling_event_in_progress?(group_name)
        group = get_target_group(group_name)
        unhealthy_targets = get_unhealthy_targets(group)

        unhealthy_targets.any?
      end

      private

      def get_ec2_instance(instance_id)
        describe_instances_response = ec2_client.describe_instances(
          instance_ids: [instance_id],
          filters: [{ name: STATE_NAME_FILTER, values: [RUNNING_STATE] }])

        describe_instances_response.reservations.first.instances.first
      end

      def get_autoscaling_group(autoscaling_group_name)
        describe_auto_scaling_groups_response = auto_scaling_client.describe_auto_scaling_groups(
          auto_scaling_group_names: [autoscaling_group_name])

        describe_auto_scaling_groups_response.auto_scaling_groups.first
      end

      def describe_target_group(target_group_arns)
        elastic_balancing_client.describe_target_groups(target_group_arns: [target_group_arn]).first
      end

      def get_load_balancers(names)
        resp = elastic_balancing_client.resp = elastic_balancing_client.describe_target_health({
          names: names,
        })

        resp.load_balancers
      end

      def describe_load_balancer_listeners(load_balancer_arn)
        resp = client.describe_listeners({
          load_balancer_arn: load_balancer_arn
        })

        resp.listeners
      end

      def get_healthy_targets(group)
        resp = elastic_balancing_client.describe_target_health({
          target_group_arn: group.target_group_arn,
        })

        resp.target_health_descriptions.select { |instance| instance.target_health.state == HEALTHY_STATE }
      end

      def get_target_groups_from_load_balancers(load_balancers)
        target_groups = []
        load_balancers.each do |lb|
          listeners = describe_load_balancer_listeners(lb.load_balancer_arn)
          listeners.each do |listener|
            target_group = listener.default_actions.find { |action| action.type == "forward" }
            tg = describe_target_group(target_group.target_group_arn)
            target_groups << tg.target_group_name
          end
        end

        target_groups
      end

      def get_unhealthy_targets(group)
        resp = elastic_balancing_client.describe_target_health({
          target_group_arn: group[:target_group_arn],
        })

        resp.target_health_descriptions.select { |instance| instance.target_health.state != HEALTHY_STATE }
      end

      def public_dns_name_from_instance_id(instance_id)
        log "locating public dns name for instance id: #{instance_id}"

        dns_name = get_ec2_instance(instance_id).public_dns_name

        fail "Unable to map instance-id: #{instance_id} to public dns name" if dns_name.nil?

        log "Mapped #{instance_id} : #{dns_name}"
        dns_name
      end

      def log(message)
        puts "Capistrano::AutoScaling - #{message}" # rubocop:disable Rails/Output
      end

      def auto_scaling_client
        Aws::AutoScaling::Client.new(capistrano_aws_credentials)
      end

      def ec2_client
        Aws::EC2::Client.new(capistrano_aws_credentials)
      end

      def elastic_balancing_client
        Aws::ElasticLoadBalancingV2::Client.new(capistrano_aws_credentials)
      end

      def capistrano_aws_credentials
        @aws_credentials ||= {
          region: ENV[REGION_ENV_VARIABLE_NAME],
          access_key_id: ENV[ACCESS_KEY_ENV_VARIABLE_NAME],
          secret_access_key: ENV[SECRET_KEY_ENV_VARIABLE_NAME]
        }

        fail 'Capistrano AWS environment variables are missing' if @aws_credentials.values.any?(&:nil?)

        @aws_credentials
      end
    end
  end
end
