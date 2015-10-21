# provider azure ARM
require 'base64'

require 'puppet_x/puppetlabs/azure/prefetch_error'
require 'puppet_x/puppetlabs/azure/provider_arm'

require 'pry'

Puppet::Type.type(:azure_vm).provide(:azure_arm, :parent => PuppetX::Puppetlabs::Azure::ProviderArm) do
  confine feature: :azure
  confine feature: :azure_hocon
  confine feature: :azure_retries

  mk_resource_methods

  def self.instances
    begin
      PuppetX::Puppetlabs::Azure::ProviderArm.new.get_all_vms.collect do |machine|
        begin
          hash = machine_to_hash(machine)
          Puppet.debug("Ignoring #{name} due to invalid or incomplete response from Azure") unless hash
          new(hash) if hash
        end
      end.compact
    rescue StandardError => e
      raise PuppetX::Puppetlabs::Azure::PrefetchError.new(self.resource_type.name.to_s, e)
    end
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name] # rubocop:disable Lint/AssignmentInCondition
        resource.provider = prov
      end
    end
  end

  def self.ensure_from(status)
    case status
    when 'StoppedDeallocated', 'Stopped'
      :stopped
    else
      :running
    end
  end

  def self.build_image_from_reference(image_reference)
    image = "#{image_reference.publisher}:#{image_reference.offer}:#{image_reference.sku}:#{image_reference.version}"
  end

  def self.machine_to_hash(machine)
    {
      name: machine.name,
      image: self.build_image_from_reference(machine.properties.storage_profile.image_reference),
      ensure: ensure_from(machine.properties.provisioning_state),
      location: machine.location,
      # NOTE: ipaddress cant be found easily in the ARM API.
      # ipaddress: machine.ipaddress,
      username: machine.properties.os_profile.admin_username,
      hostname: machine.properties.os_profile.computer_name,
      size: machine.properties.hardware_profile.vm_size,
      object: machine,
    }
  end

  def exists?
    Puppet.info("Checking if #{name} exists")
    @property_hash[:ensure] and @property_hash[:ensure] != :absent
  end

  def create
    Puppet.info("Creating #{name}")
    params = {
      name: name,
      image: resource[:image],
      location: resource[:location],
      size: resource[:size],
      user: resource[:user],
      password: resource[:password],
    }
    create_arm_vm(params)
  end

  def destroy
    Puppet.info("Deleting #{name}")
    delete_vm(machine.name)
    @property_hash[:ensure] = :absent
  end

  def stop
    Puppet.info("Stopping #{name}")
    stop_vm(machine.name)
    @property_hash[:ensure] = :stopped
  end

  def start
    Puppet.info("Starting #{name}")
    start_vm(machine.name)
    @property_hash[:ensure] = :running
  end

  def running?
    !stopped?
  end

  def stopped?
    ['StoppedDeallocated', 'Stopped'].include? machine.status
  end

  private
  def machine
    vm = if @property_hash[:object]
           @property_hash[:object]
         else
           Puppet.debug("Looking up #{name}")
           get_vm(name)
         end
    raise Puppet::Error, "No virtual machine called #{name}" unless vm
    vm
  end
end
