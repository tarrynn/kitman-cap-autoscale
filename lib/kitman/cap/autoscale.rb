require 'aws-sdk-ec2'
require 'aws-sdk-autoscaling'

module Kitman
  module Cap
    class Autoscale
      STATE_NAME_FILTER = 'instance-state-name'
      RUNNING_STATE = 'running'

      ACCESS_KEY_ENV_VARIABLE_NAME = 'CAPISTRANO_AWS_ACCESS_KEY'
      SECRET_KEY_ENV_VARIABLE_NAME = 'CAPISTRANO_AWS_ACCESS_SECRET_KEY'
      REGION_ENV_VARIABLE_NAME = 'CAPISTRANO_AWS_REGION'

      attr_accessor :auto_scaling_client
      attr_accessor :ec2_client

      def hosts_in_autoscaling_group(autoscaling_group_name)
        hosts = []

        log "Checking autoscaling group: #{autoscaling_group_name}"
        auto_scaling_group = get_autoscaling_group(autoscaling_group_name)

        unless auto_scaling_group.nil?
          log "Discovered #{auto_scaling_group.instances.count} instances"
          auto_scaling_group.instances.each do |instance|
            hosts << public_dns_name_from_instance_id(instance.instance_id)
          end

          log "Located hosts #{hosts.join(', ')}"
          hosts
        else
          raise "Auto scaling group: '#{autoscaling_group_name}' not found"
        end
      end

      def autoscaling_event_in_progress?(group_name)
        activities = auto_scaling_client.describe_scaling_activities(auto_scaling_group_name: group_name).activities

        activities.any? && activities.none? { |activity| activity.status_code.eql? 'Successful' }
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

      def capistrano_aws_credentials
        @aws_credentials ||= {
          access_key_id: ENV[ACCESS_KEY_ENV_VARIABLE_NAME],
          secret_access_key: ENV[SECRET_KEY_ENV_VARIABLE_NAME],
          region: ENV[REGION_ENV_VARIABLE_NAME]
        }

        fail 'Capistrano AWS environment variables are missing' if @aws_credentials.values.any?(&:nil?)

        @aws_credentials
      end
    end
  end
end
