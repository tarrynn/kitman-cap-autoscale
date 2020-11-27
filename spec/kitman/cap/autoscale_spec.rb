require 'spec_helper'

describe Kitman::Cap::Autoscale do
  TEST_AUTOSCALING_GROUP_NAME = 'test-group-name'

  let(:subject) { described_class.new }

  let(:asg) do
    {
      auto_scaling_group_arn: "arn:aws:autoscaling:eu-west-1:123456789012:autoScalingGroup:930d940e-891e-4781-a11a-7b0acd480f03:autoScalingGroupName/test-group-name",
      auto_scaling_group_name: "test-group-name",
      availability_zones: ["eu-west-1"],
      created_time: Time.now,
      default_cooldown: 300,
      desired_capacity: 0,
      health_check_type: "EC2",
      max_size: 1,
      min_size: 0,
      target_group_arns: [
        "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/staging/11111111111111"
      ]
    }
  end

  let(:asg_without_tg) do
    {
      auto_scaling_group_arn: "arn:aws:autoscaling:eu-west-1:123456789012:autoScalingGroup:930d940e-891e-4781-a11a-7b0acd480f03:autoScalingGroupName/test-group-name",
      auto_scaling_group_name: "test-group-name",
      availability_zones: ["eu-west-1"],
      created_time: Time.now,
      default_cooldown: 300,
      desired_capacity: 0,
      health_check_type: "EC2",
      max_size: 1,
      min_size: 0,
      target_group_arns: []
    }
  end

  let(:healthy_host) do
    {
      health_check_port: "80",
      target: {
        id: "i-0f76fade",
        port: 80,
      },
      target_health: {
        state: "healthy",
      }
    }
  end

  let(:unhealthy_host) do
    {
      health_check_port: "80",
      target: {
        id: "i-0f76fabc",
        port: 80,
      },
      target_health: {
        state: "unhealthy",
      }
    }
  end

  let(:booting_host) do
    {
      health_check_port: "80",
      target: {
        id: "i-0f76fabc",
        port: 80,
      },
      target_health: {
        state: "initial",
      }
    }
  end

  before :each do
    @auto_scaling_client = Aws::AutoScaling::Client.new(stub_responses: true)
    subject.auto_scaling_client = @auto_scaling_client
    @ec2_client = Aws::EC2::Client.new(stub_responses: true)
    subject.ec2_client = @ec2_client
    @elastic_balancing_client = Aws::ElasticLoadBalancingV2::Client.new(stub_responses: true)
    subject.elastic_balancing_client = @elastic_balancing_client
  end

  context '#autoscaling_event_in_progress' do
    it 'returns false if no autoscaling event in progress' do
      @auto_scaling_client.stub_responses(:describe_auto_scaling_groups, { auto_scaling_groups: [asg] })
      @elastic_balancing_client.stub_responses(:describe_target_health, { target_health_descriptions: [healthy_host] })
      expect(subject.autoscaling_event_in_progress?(TEST_AUTOSCALING_GROUP_NAME)).to be(false)
    end

    it 'returns true if a host is unhealthy' do
      @auto_scaling_client.stub_responses(:describe_auto_scaling_groups, { auto_scaling_groups: [asg] })
      @elastic_balancing_client.stub_responses(:describe_target_health, {
        target_health_descriptions: [healthy_host, unhealthy_host]
      })

      expect(subject.autoscaling_event_in_progress?(TEST_AUTOSCALING_GROUP_NAME)).to be(true)
    end

    it 'returns true if a host is booting up' do
      @auto_scaling_client.stub_responses(:describe_auto_scaling_groups, { auto_scaling_groups: [asg] })
      @elastic_balancing_client.stub_responses(:describe_target_health, {
        target_health_descriptions: [healthy_host, booting_host]
      })

      expect(subject.autoscaling_event_in_progress?(TEST_AUTOSCALING_GROUP_NAME)).to be(true)
    end
  end

  context '#hosts_in_autoscaling_group' do
    context 'with invalid autoscaling group' do
      it 'raises error if auto scaling group not found' do
        @auto_scaling_client.stub_responses(:describe_auto_scaling_groups, { auto_scaling_groups: [] })
        expect do
          subject.hosts_in_autoscaling_group(TEST_AUTOSCALING_GROUP_NAME)
        end.to raise_error(RuntimeError)
      end
    end

    context 'with valid autoscaling group' do
      context 'without target group' do
        it 'raises error' do
          @auto_scaling_client.stub_responses(:describe_auto_scaling_groups, {
            auto_scaling_groups: [asg_without_tg]
          })

          expect do
            subject.hosts_in_autoscaling_group(TEST_AUTOSCALING_GROUP_NAME)
          end.to raise_error(RuntimeError)
        end
      end

      context 'without instances' do
        it 'returns empty list no hosts in group' do
          @auto_scaling_client.stub_responses(:describe_auto_scaling_groups, { auto_scaling_groups: [asg] })
          @elastic_balancing_client.stub_responses(:describe_target_health, { target_health_descriptions: [] })
          expect(subject.hosts_in_autoscaling_group(TEST_AUTOSCALING_GROUP_NAME)).to eq([])
        end
      end

      context 'with instances' do
        let(:ec2_instance_1) {
          {
            public_dns_name: 'public_1.dns.name.com'
          }
        }

        let(:ec2_instance_2) {
          {
            public_dns_name: 'public_2.dns.name.com'
          }
        }

        it 'returns hosts from group' do
          @auto_scaling_client.stub_responses(:describe_auto_scaling_groups, { auto_scaling_groups: [asg] })
          @elastic_balancing_client.stub_responses(:describe_target_health, {
            target_health_descriptions: [healthy_host, healthy_host]
          })
          @ec2_client.stub_responses(:describe_instances,
                                          {reservations: [{instances: [ec2_instance_1]}]},
                                          {reservations: [{instances: [ec2_instance_2]}]},
          )

          expect(subject.hosts_in_autoscaling_group(TEST_AUTOSCALING_GROUP_NAME)).to eq(
            ['public_1.dns.name.com', 'public_2.dns.name.com']
          )
        end
      end
    end
  end
end
