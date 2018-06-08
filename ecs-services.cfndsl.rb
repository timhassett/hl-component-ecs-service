CloudFormation do

  az_conditions_resources('SubnetCompute', maximum_availability_zones)

  log_retention = 7 unless defined?(log_retention)
  Resource('LogGroup') {
    Type 'AWS::Logs::LogGroup'
    Property('LogGroupName', Ref('AWS::StackName'))
    Property('RetentionInDays', "#{log_retention}")
  }

  definitions, task_volumes = Array.new(2){[]}

  task_definition.each do |task_name, task|

    env_vars, mount_pounts, ports = Array.new(3){[]}

    name = task.has_key?('name') ? task['name'] : task_name

    image_repo = task.has_key?('repo') ? "#{task['repo']}/" : ''
    image_name = task.has_key?('image') ? task['image'] : task_name
    image_tag = task.has_key?('tag') ? "#{task['tag']}" : 'latest'
    image_tag = task.has_key?('tag_param') ? Ref("#{task['tag_param']}") : image_tag

    # create main definition
    task_def =  {
      Name: name,
      Image: FnJoin('',[ image_repo, image_name, ":", image_tag ]),
      LogConfiguration: {
        LogDriver: 'awslogs',
        Options: {
          'awslogs-group' => Ref("LogGroup"),
          "awslogs-region" => Ref("AWS::Region"),
          "awslogs-stream-prefix" => name
        }
      }
    }

    task_def.merge!({ MemoryReservation: task['memory'] }) if task.has_key?('memory')
    task_def.merge!({ Cpu: task['cpu'] }) if task.has_key?('cpu')

    if !(task['env_vars'].nil?)
      task['env_vars'].each do |name,value|
        split_value = value.to_s.split(/\${|}/)
        if split_value.include? 'environment'
          fn_join = split_value.map { |x| x == 'environment' ? [ Ref('EnvironmentName'), '.', FnFindInMap('AccountId',Ref('AWS::AccountId'),'DnsDomain') ] : x }
          env_value = FnJoin('', fn_join.flatten)
        elsif value == 'cf_version'
          env_value = cf_version
        else
          env_value = value
        end
        env_vars << { Name: name, Value: env_value}
      end
    end

    task_def.merge!({Environment: env_vars }) if env_vars.any?

    # add links
    if task.key?('links')
      task['links'].each do |links|
      task_def.merge!({ Links: [ links ] })
      end
    end

    # add entrypoint
    if task.key?('entrypoint')
      task['entrypoint'].each do |entrypoint|
      task_def.merge!({ EntryPoint: entrypoint })
      end
    end

    # By default Essential is true, switch to false if `not_essential: true`
    task_def.merge!({ Essential: false }) if task['not_essential']

    # add docker volumes
    if (task.key?('mounts'))
      task['mounts'].each do |mount|
        path = (mount.key?('path') ? mount['path'] :  tasks[service]['volumes'][mount['volume']])
        mount_pounts << { ContainerPath: path, SourceVolume: mount['volume'], ReadOnly: (mount.key?('ReadOnly') ? true : false) }
      end
      task_def.merge!({MountPoints: mount_pounts })
    end

    # add port
    if task.key?('ports')
      port_mapppings = []
      task['ports'].each do |port|
        port_array = port.to_s.split(":").map(&:to_i)
        mapping = {}
        mapping.merge!(ContainerPort: port_array[0])
        mapping.merge!(HostPort: port_array[1]) if port_array.length == 2
        port_mapppings << mapping
      end
      task_def.merge!({PortMappings: port_mapppings})
    end

    definitions << task_def

  end if defined? task_definition

  # add docker volumes
  if defined?(volumes)
    volumes.each do |volume, path|
      task_volumes << { Name: volume, Host: { SourcePath: path } }
    end
  end

  if defined?(iam)
    IAM_Role('TaskRole') do
      AssumeRolePolicyDocument ({
        Statement: [
          {
            Effect: 'Allow',
            Principal: { Service: [ 'ec2.amazonaws.com' ] },
            Action: [ 'sts:AssumeRole' ]
          },
          {
            Effect: 'Allow',
            Principal: { Service: [ 'ssm.amazonaws.com' ] },
            Action: [ 'sts:AssumeRole' ]
          }
        ]
      })
      Path '/'
      Policies(IAMPolicies.new.create_policies(iam))
    end

    IAM_Role('ExecutionRole') do
      AssumeRolePolicyDocument ({
        Statement: [
          {
            Effect: 'Allow',
            Principal: { Service: [ 'ecs-tasks.amazonaws.com' ] },
            Action: [ 'sts:AssumeRole' ]
          }
        ]
      })
      Path '/'
      Policies({
        Version: "2012-10-17",
        Statement: [
          {
            Effect: "Allow",
            Action: [
              "ecr:GetAuthorizationToken",
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage",
              "logs:CreateLogStream",
              "logs:PutLogEvents"
            ],
            Resource: "*"
          }
        ]
      })
    end
  end

  Resource('Task') do
    Type 'AWS::ECS::TaskDefinition'
    Property('ContainerDefinitions', definitions)

    if defined?(cpu)
      Property('Cpu', cpu)
    end

    if defined?(memory)
      Property('Memory', memory)
    end

    if defined?(network_mode)
      Property('NetworkMode', network_mode)
    end

    if task_volumes.any?
      Property('Volumes', task_volumes)
    end

    if defined?(iam)
      Property('TaskRoleArn', Ref('TaskRole'))
      Property('ExecutionRoleArn', Ref('ExecutionRole'))
    end

  end if defined? task_definition

  service_loadbalancer = []
  if defined?(targetgroup)
    service_loadbalancer << {
      ContainerName: targetgroup['container'],
      ContainerPort: targetgroup['port'],
      TargetGroupArn: Ref('TargetGroup')
    }
  end

  IAM_Role('Role') do
    AssumeRolePolicyDocument ({
      Statement: [
        Effect: 'Allow',
        Principal: { Service: [ 'ecs.amazonaws.com' ] },
        Action: [ 'sts:AssumeRole' ]
      ]
    })
    Path '/'
    Policies Policies(IAMPolicies.new.create_policies([
      'ecs-service-role'
    ]))
  end

  awsvpc_enabled = false
  if defined?(network_mode) && network_mode == 'awsvpc'
    awsvpc_enabled = true
  end

  has_security_group = false
  if ((defined? securityGroups) && (securityGroups.has_key?(component_name)))
    has_security_group = true
  end
    
  if awsvpc_enabled == true
    sg_name = 'SecurityGroupBackplane'
    if has_security_group == true
      EC2_SecurityGroup('ServiceSecurityGroup') do
        VpcId Ref('VPC')
        GroupDescription "#{component_name} ECS service"
        SecurityGroupIngress sg_create_rules(securityGroups[component_name], ip_blocks)
      end
      sg_name = 'ServiceSecurityGroup'
    end
  end

  ECS_Service('Service') do
    Cluster Ref("EcsCluster")
    DesiredCount 1
    DeploymentConfiguration ({
        MinimumHealthyPercent: 100,
        MaximumPercent: 200
    })
    TaskDefinition Ref('Task')

    if service_loadbalancer.any?
      Role Ref('Role')
      LoadBalancers service_loadbalancer
    end

    if awsvpc_enabled == true
      NetworkConfiguration({
        AwsvpcConfiguration: {
          AssignPublicIp: "DISABLED",
          SecurityGroups: [ Ref(sg_name) ],
          Subnets: az_conditional_resources('SubnetCompute', maximum_availability_zones)
        }        
      })
    end
  end if defined? task_definition

end