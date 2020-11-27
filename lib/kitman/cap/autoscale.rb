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
      attr_accessor :elastic_balancing_client

      def hosts_in_autoscaling_group(group_name)
        hosts = []

        log "Checking autoscaling group: #{group_name}"
        asg = get_autoscaling_group(group_name)

        unless asg.nil?
          unless asg.target_group_arns.empty?
            asg.target_group_arns.each do |arn|
              healthy_targets = get_healthy_targets(arn)
              log "Discovered #{healthy_targets.count} instances for target group: '#{arn}'"
              healthy_targets.each do |instance|
                hosts << public_dns_name_from_instance_id(instance.target.id)
              end
            end

            log "Located hosts #{hosts.join(', ')}"
            hosts
          else
            raise "No target groups for autoscaling group: '#{group_name}'"
          end
        else
          raise "Autoscaling group: '#{group_name}' not found"
        end
      end

      def autoscaling_event_in_progress?(group_name)
        asg = get_autoscaling_group(group_name)

        unless asg.nil?
          unless asg.target_group_arns.empty?
            asg.target_group_arns.each do |arn|
              unhealthy_targets = get_unhealthy_targets(arn)
              return true if unhealthy_targets.any?
            end

            false
          else
            raise "No target groups for autoscaling group: '#{group_name}'"
          end
        else
          raise "Autoscaling group: '#{group_name}' not found"
        end
      end

      private

      def get_ec2_instance(instance_id)
        describe_instances_response = ec2_client.describe_instances(
          instance_ids: [instance_id],
          filters: [{ name: STATE_NAME_FILTER, values: [RUNNING_STATE] }])

        describe_instances_response.reservations.first.instances.first
      end

      def get_autoscaling_group(autoscaling_group_name)
        resp = auto_scaling_client.describe_auto_scaling_groups(
          auto_scaling_group_names: [autoscaling_group_name]
        )

        resp.auto_scaling_groups.first
      end

      def get_healthy_targets(arn)
        resp = elastic_balancing_client.describe_target_health({
          target_group_arn: arn,
        })

        resp.target_health_descriptions.select { |instance| instance.target_health.state == HEALTHY_STATE }
      end

      def get_unhealthy_targets(arn)
        resp = elastic_balancing_client.describe_target_health({
          target_group_arn: arn,
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
        @auto_scaling_client ||= Aws::AutoScaling::Client.new(capistrano_aws_credentials)
      end

      def ec2_client
        @ec2_client ||= Aws::EC2::Client.new(capistrano_aws_credentials)
      end

      def elastic_balancing_client
        @elastic_balancing_client ||= Aws::ElasticLoadBalancingV2::Client.new(capistrano_aws_credentials)
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
