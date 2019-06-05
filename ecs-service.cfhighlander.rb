CfhighlanderTemplate do

  DependsOn 'vpc' if ((defined? network_mode) && (network_mode == "awsvpc"))

  Description "ecs-service - #{component_name} - #{component_version}"

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','production'], isGlobal: true
    ComponentParam 'EcsCluster'

    if (defined? targetgroup) || ((defined? network_mode) && (network_mode == "awsvpc"))
      ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    end

    if defined? targetgroup
      ComponentParam 'LoadBalancer'
      ComponentParam 'TargetGroup'
      ComponentParam 'Listener'
      ComponentParam 'DnsDomain'
    end

    ComponentParam 'DesiredCount', 1
    ComponentParam 'MinimumHealthyPercent', 100
    ComponentParam 'MaximumPercent', 200

    ComponentParam 'EnableScaling', 'false', allowedValues: ['true','false']

    if ((defined? network_mode) && (network_mode == "awsvpc"))
      ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
      ComponentParam 'SecurityGroupBackplane'
    end

    task_definition.each do |task_def, task|
      if task.has_key?('tag_param')
        default_value = task.has_key?('tag_param_default') ? task['tag_param_default'] : 'latest'
        ComponentParam task['tag_param'], default_value
      end
    end if defined? task_definition

    ComponentParam 'NamespaceId' if defined? service_discovery

  end

end
