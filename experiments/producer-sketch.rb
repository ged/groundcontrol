#!/usr/bin/env ruby

require 'laika'

$stderr.sync = true

# A little sketch of how GroundControl's API should work.

LAIKA.require_features( :ldap, :groundcontrol )
LAIKA.load_config( '../../etc/config.yml' )

queue = LAIKA::GroundControl.default_queue
Sequel.extension( :pretty_table )

loop do

	$stderr.print "Adding gatherer tasks for hosts:"
	LAIKA::Netgroup[:workstations].hosts.each do |host|
		$stderr.print " #{host.cn.first}"
		job = LAIKA::GroundControl::Job.new( task_name: 'gather', arguments: host.fqdn )
		queue.add( job )
	end

	started = Time.now
	$stderr.puts "Pausing job injection..."
	queue.wait_for_notification( poll: true, timeout: 5 ) do |*|
		$stderr.puts "%d tasks remain..." % [ queue.dataset.filter( locked_at: nil ).count ]
		throw :stop if Time.now - started > 5 * 60
	end

end
