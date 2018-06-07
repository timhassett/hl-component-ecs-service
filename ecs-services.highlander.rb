HighlanderComponent do

  DependsOn 'vpc@1.0.4'

  Description "ecs-service - #{component_name} - #{component_version}"

  Parameters do
    StackParam 'EnvironmentName', 'dev', isGlobal: true
    StackParam 'EnvironmentType', 'development', isGlobal: true
    
    OutputParam component: 'vpc', name: "VPCId"
    OutputParam component: 'vpc', name: "SecurityGroupBackplane"
    OutputParam component: 'loadbalancer', name: 'LoadBalancer'
    OutputParam component: 'ecs', name: 'EcsCluster'
    OutputParam component: 'loadbalancer', name: "#{targetgroup['name']}TargetGroup"

    subnet_parameters({'private'=>{'name'=>'Compute'}}, maximum_availability_zones)

    #create component params for service image tag parameters
    task_definition.each do |task_def, task|
      if task.has_key?('tag_param')
        default_value = task.has_key?('tag_param_default') ? task['tag_param_default'] : 'latest'
        StackParam task['tag_param'], default_value
      end
    end

  end
  
end