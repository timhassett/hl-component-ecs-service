CfhighlanderTemplate do

  DependsOn 'vpc@1.0.4'

  Description "ecs-service - #{component_name} - #{component_version}"

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','production'], isGlobal: true
    
    ComponentParam 'VPCId'
    ComponentParam 'SecurityGroupBackplane'
    ComponentParam 'LoadBalancer'
    ComponentParam 'EcsCluster'
    ComponentParam 'TargetGroup'

    maximum_availability_zones.times do |az|
      ComponentParam "SubnetCompute#{az}"
    end

    #create component params for service image tag parameters
    task_definition.each do |task_def, task|
      if task.has_key?('tag_param')
        default_value = task.has_key?('tag_param_default') ? task['tag_param_default'] : 'latest'
        ComponentParam task['tag_param'], default_value
      end
    end if defined? task_definition

  end
  
end