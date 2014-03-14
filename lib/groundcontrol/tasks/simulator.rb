#!/usr/bin/env ruby

require 'pathname'
require 'tmpdir'
require 'groundcontrol/task' unless defined?( GroundControl::Task )


# A spike to test out various task execution outcomes.
class Simulator < GroundControl::Task

	# Simulate processing all events
	subscribe_to '#'

	# Fetch 100 events at a time
	prefetch 100


	### Create a new Simulate task.
	def initialize( queue )
		super
		@logdir = Pathname( Dir.tmpdir )
		@logfile = @logdir + 'events.log'
		$stderr.puts "Logfile is: %s" % [ @logfile ]
		@log = @logfile.open( File::CREAT|File::APPEND|File::WRONLY, encoding: 'utf-8' )
	end


	######
	public
	######

	#
	# Task API
	#

	# Do the ping.
	def work( payload, metadata )
		if metadata[:properties][:headers] &&
		   metadata[:properties][:headers]['x-death']
			puts "Deaths! %p" % [ metadata[:properties][:headers]['x-death'] ]
		end

		val = Random.rand
		case
		when val < 0.33
			$stderr.puts "Simulating an error in the task (reject)."
			raise "OOOOOPS! %p" % [ payload['key'] ]
		when val < 0.66
			$stderr.puts "Simulating a soft failure in the task (reject+requeue)."
			return false
		else
			$stderr.puts "Simulating a successful task run (accept)"
			@log.puts( payload['key'] )
			@log.flush
			return true
		end
	end


end # class Simulator
