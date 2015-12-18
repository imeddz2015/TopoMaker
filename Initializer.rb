require 'Node'
require 'Interface'
require 'Vlan'
require 'Searcher'
require 'RspecParser'

class Initializer

  attr_reader :parser
  
  
  def initialize(file)
    @parser = RspecParser.new(file)
  end

  def nodesCreate
    nodes=Array.new
    @parser.getAllNodes.each do |node|
      nodes.push(Node.new(@parser.getNodeName(node), @parser.getOS(node)))
      nodes.last.interfaces=interfacesCreate(node)
    end
    return nodes
  end

  def interfacesCreate(node)
    interfaces=Array.new
    @parser.getInterfaces(node).each do |int|
      interfaces.push Interface.new(@parser.getInterfaceName(int))
      ip, net = @parser.getNetwork(int)
      interfaces.last.ip = ip
      interfaces.last.netmask = net
    end
    return interfaces
  end

  def vlanCreate(nodeList)
    vlans = Array.new
    @parser.getAllLinks.each do |link|
      vlan = Vlan.new(@parser.getLinkName(link))
      @parser.getLinkInterfaces(link).each do |nameInt|
        interface = Searcher.searchInterface(nameInt, nodeList)
        vlan.addInterface(interface)
      end
      vlans.push(vlan)
    end
    return vlans
  end

  def defVlanNumber(jobid, vlanList)
    vlanNb = %x(kavlan -V -j #{jobid} && echo $?)
    vlans = vlanNb.split("\n")
    if(vlans.delete_at(vlans.size-1).to_i != 0)
      STDERR.puts vlanNb
      exit 1
    end
    if vlans.size < vlanList.size
      STDERR.puts "Not enough VLAN in the reservation"
      exit 1
    end
    i=0
    vlanList.each do |v|
      v.setNumber(vlans[i])
      i+=1 
    end
  end

  def defNodeHostname(jobid, nodeList)
    hosts = %x(uniq /var/lib/oar/#{jobid} && echo $?)
    hostList = hosts.split("\n")
    if(hostList.delete_at(hostList.size-1).to_i != 0)
      STDERR.puts hosts
      exit 1
    end
    if hostList.size < nodeList.size
      STDERR.puts "Not enough nodes in the reservation"
      exit 1
    end
    i=0
    nodeList.each do |v|
      v.setNodeRealName(hostList[i])
      i+=1 
    end
  end

  def deploy(nodeList)
    group = Searcher.groupOS(nodeList)
    group.keys.each do |k|
      puts %x(kadeploy3 -e #{k} -k -m #{group[k].join(" -m ")})
    end
  end

  def setIp(nodeList)
    threads = []
    nodeList.each do |node|
      threads << Thread.new {
        node.installAt
        node.writeConf(node.genConfInterfaces)
        node.restartIpService
      }
    end
    threads.each { |thr| thr.join }
      sleepingThread = Thread.new {
        sleep 70
        puts "Networking service restarted on each node" if $verbose
      }
      return sleepingThread
  end
  
end

