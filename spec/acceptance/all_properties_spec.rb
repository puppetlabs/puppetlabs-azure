require 'spec_helper_acceptance'

describe 'azure_vm when creating a machine with all available properties' do
  include_context 'with certificate copied to system under test'
  include_context 'with temporary affinity group'

  before(:all) do
    @name = "CLOUD-#{SecureRandom.hex(8)}"

    @config = {
      name: @name,
      ensure: 'present',
      optional: {
        image: UBUNTU_IMAGE,
        location: CHEAPEST_AZURE_LOCATION,
        user: 'specuser',
        password: 'SpecPass123!@#$%',
        size: 'Medium',
        deployment: "CLOUD-DN-#{SecureRandom.hex(8)}",
        cloud_service: "CLOUD-CS-#{SecureRandom.hex(8)}",
        affinity_group: @affinity_group_name,
        availability_set: "CLOUD-AS-#{SecureRandom.hex(8)}",
      }
    }
    @manifest = PuppetManifest.new(@template, @config)
    @result = @manifest.execute
    @machine = @client.get_virtual_machine(@name).first
    @ip = @machine.ipaddress
  end

  it_behaves_like 'an idempotent resource'

  include_context 'destroys created resources after use'

  it 'should have the correct size' do
    expect(@machine.role_size).to eq(@config[:optional][:size])
  end

  it 'should have the correct deployment name' do
    expect(@machine.deployment_name).to eq(@config[:optional][:deployment])
  end

  it 'should have the correct cloud service name' do
    expect(@machine.cloud_service_name).to eq(@config[:optional][:cloud_service])
  end

  it 'is accessible using the password' do
    result = run_command_over_ssh('true', 'password')
    expect(result.exit_status).to eq 0
  end

  it 'should have the correct availability set' do
    expect(@machine.availability_set_name).to eq(@config[:optional][:availability_set])
  end

  it 'should be in the correct affinity group' do
    affinity_group = @client.get_affinity_group(@affinity_group_name)
    associated_services = affinity_group.hosted_services.map { |service| service[:service_name] }
    expect(associated_services).to include(@machine.cloud_service_name)
  end

  context 'which has read-only properties' do
    read_only = [
      :location,
      :deployment,
      :cloud_service,
      :size,
      :image,
      :availability_set,
    ]

    read_only.each do |new_config_value|
      it "should prevent change to read-only property #{new_config_value}" do
        config_clone = Marshal.load(Marshal.dump(@config))
        config_clone[:optional][new_config_value.to_sym] = 'foo'
        expect_failed_apply(config_clone)
      end
    end
  end

  context 'when looked for using puppet resource' do
    include_context 'a puppet resource run'
    puppet_resource_should_show('size')
    puppet_resource_should_show('deployment')
    puppet_resource_should_show('cloud_service')
    puppet_resource_should_show('availability_set')
  end
end
