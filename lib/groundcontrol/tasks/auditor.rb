#!/usr/bin/env ruby

require 'pp'
require 'pathname'
require 'tmpdir'
require 'groundcontrol/task' unless defined?( GroundControl::Task )
require 'groundcontrol/metrics'


# A spike to log events
class Auditor < GroundControl::Task
	prepend GroundControl::Metrics

	subscribe_to '#'
	prefetch 1000
	queue_name '_audit'


	### Create a new Auditor task.
	def initialize( queue )
		super
		@logdir = Pathname.pwd
		@logfile = @logdir + 'events.log'
		@log = @logfile.open( File::CREAT|File::APPEND|File::WRONLY, encoding: 'utf-8' )
		self.log.info "Logfile is: %s" % [ @logfile ]
	end


	######
	public
	######

	#
	# Task API
	#

	# Log the event.
	def work( payload, metadata )
		@log.puts "%d%s [%s]: %p" % [
			metadata[:delivery_info][:delivery_tag],
			metadata[:delivery_info][:redelivered] ? '+' : '',
			metadata[:delivery_info][:routing_key],
			payload
		]

		return true
	end


end # class Auditor

