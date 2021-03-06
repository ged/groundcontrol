# -*- ruby -*-
# frozen_string_literal: true

require 'set'
require 'sysexits'
require 'pluggability'
require 'loggability'

require 'msgpack'
require 'json'
require 'yaml'

require 'symphony' unless defined?( Symphony )
require 'symphony/signal_handling'


# A task is the subclassable unit of work that Symphony loads when it starts up.
class Symphony::Task
	extend Loggability,
	       Pluggability,
	       Sysexits,
	       Symphony::MethodUtilities

	include Symphony::SignalHandling


	# Signal to reset to defaults for the child
	SIGNALS = %i[ INT TERM HUP ]

	# Valid work model types
	WORK_MODELS = %i[ longlived oneshot ]

	# The number of seconds between checks to see if the worker is idle. Note that
	# this is not the same as the idle timeout -- it's how often to check to see if
	# the task has been idle for too long.
	IDLE_CHECK_INTERVAL = 5 # seconds

	# The default number of seconds to wait for work
	DEFAULT_IDLE_TIMEOUT = IDLE_CHECK_INTERVAL * 2


	# Loggability API -- log to symphony's logger
	log_to :symphony

	# Pluggability API -- set the directory/directories that will be search when trying to
	# load tasks by name.
	plugin_prefixes 'symphony/tasks'


	@queue         = nil
	@acknowledge   = true
	@routing_keys  = Set.new
	@prefetch      = 10
	@persistent    = false
	@always_rebind = false


	### Create a new Task object and listen for work. Exits with the code returned
	### by #start when it's done.
	def self::run( exit_on_idle=false )
		if self.subscribe_to.empty?
			raise ScriptError,
				"No subscriptions defined. Add one or more patterns using subscribe_to."
		end

		exit self.new( self.queue, exit_on_idle ).start
	end


	### Prepare the process to be forked.
	def self::before_fork
		self.log.debug "Before fork [%d]: Threads: %p" % [ Process.pid, ThreadGroup::Default.list ]
		Symphony::Queue.reset
	end


	### Prepare the process after being forked from the Daemon.
	def self::after_fork
		self.log.debug "After fork [%d]: Threads: %p" % [ Process.pid, ThreadGroup::Default.list ]
		Symphony::Queue.reset
		Process.setpgrp
		Symphony.config.install if Symphony.config
	end


	### Inheritance hook -- set some defaults on subclasses.
	def self::inherited( subclass )
		super

		subclass.instance_variable_set( :@queue, nil )
		subclass.instance_variable_set( :@always_rebind, false )
		subclass.instance_variable_set( :@routing_keys, Set.new )
		subclass.instance_variable_set( :@acknowledge, true )
		subclass.instance_variable_set( :@work_model, :longlived )
		subclass.instance_variable_set( :@prefetch, 10 )
		subclass.instance_variable_set( :@timeout_action, :reject )
		subclass.instance_variable_set( :@timeout, nil )
		subclass.instance_variable_set( :@persistent, false )
		subclass.instance_variable_set( :@idle_timeout, DEFAULT_IDLE_TIMEOUT )
	end


	### Fetch the Symphony::Queue for this task, creating it if necessary.
	def self::queue
		unless @queue
			@queue = Symphony::Queue.for_task( self )
		end
		return @queue
	end


	### Return an queue name derived from the name of the task class.
	def self::default_queue_name
		name = self.name || "anonymous task %d" % [ self.object_id ]
		return name.gsub( /\W+/, '.' ).downcase
	end


	### Return a consumer tag for this task's queue consumer.
	def self::consumer_tag
		return "%s.%s.%d" % [
			self.queue_name,
			Socket.gethostname.gsub(/\..*$/, ''),
			Process.pid,
		]
	end


	#
	# :section: Declarative Methods
	# These methods are used to configure how the task interacts with its queue and
	# how it runs.


	### Get/set the name of the queue to consume.
	def self::queue_name( new_name=nil )
		if new_name
			@queue_name = new_name
		end

		@queue_name ||= self.default_queue_name
		return @queue_name
	end


	### Set up one or more topic key patterns to use when binding the Task's queue
	### to the exchange.
	def self::subscribe_to( *routing_keys )
		unless routing_keys.empty?
			self.log.info "Setting task routing keys to: %p." % [ routing_keys ]
			@routing_keys.replace( routing_keys )
		end

		return @routing_keys
	end
	class << self; alias_method :routing_keys, :subscribe_to ; end


	### Get/set the "always re-bind" flag that causes the queue the task uses to always
	### re-bind to its exchange when the task starts. The normal behavior is that the queue
	### is only bound if it didn't already exist, which can mean that you'd need to destroy the
	### queue to force it to rebind if you change a task's routing keys.
	def self::always_rebind( new_setting=nil )
		unless new_setting.nil?
			self.log.info "%s forced re-binding." % [ new_setting ? "Enabled" : "Disabled" ]
			@always_rebind = new_setting
		end

		return @always_rebind
	end


	### Enable or disable acknowledgements.
	def self::acknowledge( new_setting=nil )
		unless new_setting.nil?
			self.log.info "Turning task acknowlegement %s." % [ new_setting ? "on" : "off" ]
			@acknowledge = new_setting
		end

		return @acknowledge
	end


	### Get/set the maximum number of seconds the job should work on a single
	### message before giving up.
	def self::timeout( seconds=nil, options={} )
		unless seconds.nil?
			self.log.info "Setting the task timeout to %0.2fs." % [ seconds.to_f ]
			@timeout = seconds.to_f
			self.timeout_action( options[:action] )
		end

		return @timeout
	end


	### Set the action taken when work times out.
	def self::timeout_action( new_value=nil )
		if new_value
			@timeout_action = new_value.to_sym
		end

		return @timeout_action
	end


	### Alter the work model between oneshot or longlived.
	def self::work_model( new_setting=nil )
		if new_setting
			new_setting = new_setting.to_sym
			unless WORK_MODELS.include?( new_setting )
				raise "Unknown work_model %p (must be one of: %s)" %
					[ new_setting, WORK_MODELS.join(', ') ]
			end

			self.log.info "Setting task work model to: %p." % [ new_setting ]
			@work_model = new_setting
		end

		return @work_model
	end


	### Set the maximum number of messages to prefetch. Ignored if the work_model is
	### :oneshot.
	def self::prefetch( count=nil )
		if count
			@prefetch = count
		end
		return @prefetch
	end


	### Create the queue the task consumes from as a persistent queue, so it
	### will continue to receive events even if the task is no longer consuming them.
	### This only effects queues which are not already declared, so if the
	### bindings for the queue change you'll need to delete the existing queue
	### before starting up to have them take effect.
	def self::persistent( new_setting=nil )
		if new_setting
			@persistent = new_setting
		end
		return @persistent
	end


	### Get/set the maximum number of seconds the worker should wait for events to
	### arrive before exiting.
	def self::idle_timeout( seconds=nil, options={} )
		unless seconds.nil?
			self.log.info "Setting the idle timeout to %0.2fs." % [ seconds.to_f ]
			@idle_timeout = seconds.to_f
		end

		return @idle_timeout
	end



	#
	# Instance Methods
	#

	### Create a worker that will listen on the specified +queue+ for a job.
	def initialize( queue, exit_on_idle=false )
		@queue          = queue
		@signal_handler = nil
		@shutting_down  = false
		@restarting     = false
		@idle_checker   = nil
		@last_worked    = Time.now
		@exit_on_idle   = exit_on_idle
	end



	######
	public
	######

	# The queue that the task consumes messages from
	attr_reader :queue

	# The signal handler thread
	attr_reader :signal_handler

	# Is the task in the process of shutting down?
	attr_predicate_accessor :shutting_down

	# Is the task in the process of restarting?
	attr_predicate_accessor :restarting

	# The Thread that checks for idle timeout
	attr_accessor :idle_checker

	# The Time the task was last running
	attr_accessor :last_worked

	# Flag that determines whether this task instance exits when it doesn't have any work.
	attr_predicate :exit_on_idle


	### Set up the task and start handling messages.
	def start
		rval = nil

		Process.setproctitle( self.procname )

		begin
			self.restarting = false
			rval = self.with_signal_handler( *SIGNALS ) do
				self.start_handling_messages
			end
		end while self.restarting?

		return rval ? 0 : 1

	rescue Exception => err
		self.log.fatal "%p in %p: %s: %s" % [ err.class, self.class, err.message, err.backtrace.first ]
		self.log.debug { '  ' + err.backtrace.join("  \n") }

		return :software
	end


	### Restart the task after reloading the config.
	def restart
		self.restarting = true
		self.log.warn "Restarting..."

		if Symphony.config.reload
			self.log.info "  config reloaded"
		else
			self.log.info "  no config changes"
		end

		self.log.info "  resetting queue"
		Symphony::Queue.reset
		self.queue.shutdown
	end


	### Stop the task immediately, e.g., when sent a second TERM signal.
	def stop_immediately
		self.log.warn "Already in shutdown -- halting immediately."
		self.shutting_down = true
		self.ignore_signals( *SIGNALS )
		self.queue.halt
	end


	### Set the task to stop after what it's doing is completed.
	def stop_gracefully
		self.log.warn "Attempting to shut down gracefully."
		self.shutting_down = true
		self.queue.shutdown
	end


	### Start consuming messages from the queue, calling #work for each one.
	def start_handling_messages
		oneshot = self.class.work_model == :oneshot

		rval = nil
		self.queue.wait_for_message( oneshot ) do |payload, metadata|
			begin
				self.last_worked = nil
				work_payload = self.preprocess_payload( payload, metadata )

				rval = if self.class.timeout
					self.work_with_timeout( work_payload, metadata )
				else
					self.work( work_payload, metadata )
				end
			ensure
				self.last_worked = Time.now
			end

			rval
		end

		return rval
	end


	### Start the thread that will deliver signals once they're put on the queue, and
	### check for the last time a job was handled by this task process.
	def start_signal_handler
		@signal_handler = Thread.new do
			Thread.current.abort_on_exception = true
			loop do
				# self.log.debug "Signal handler: waiting for new signals in the queue."
				self.wait_for_signals( IDLE_CHECK_INTERVAL )
				self.check_for_idle_timeout
			end
		end
	rescue => err
		self.log.fatal "Signal handler thread crashed: %p: %s" % [ err.class, err.message ]
		self.stop_immediately
	end


	### Check to see if the last run was more than #idle_timeout seconds ago,
	### and cancelling the task's consumer if so.
	def check_for_idle_timeout

		# If it's unset, it means it's running now
		return unless self.last_worked && self.exit_on_idle?

		seconds_idle = Time.now - self.last_worked
		self.log.debug "%p: idle %0.2fs" % [ self.class, seconds_idle ]

		if seconds_idle > self.class.idle_timeout
			self.log.debug "Sending stop signal due to idle timeout"
			self.stop_gracefully
		end
	end


	### Stop the signal handler thread.
	def stop_signal_handler
		@signal_handler.exit if @signal_handler
	end


	### Handle signals; called by the signal handler thread with a signal from the
	### queue.
	def handle_signal( sig )
		self.log.debug "Handling signal %s" % [ sig ]
		case sig
		when :TERM
			self.on_terminate
		when :INT
			self.on_interrupt
		when :HUP
			self.on_hangup
		else
			self.log.warn "Unhandled signal %s" % [ sig ]
		end
	end


	### Do any necessary pre-processing on the raw +payload+ according to values in
	### the given +metadata+.
	def preprocess_payload( payload, metadata )
		self.log.debug "Got a %0.2fK %s payload" %
			[ payload.bytesize / 1024.0, metadata[:content_type] ]
		work_payload = case metadata[:content_type]
			when 'application/x-msgpack'
				MessagePack.unpack( payload )
			when 'application/json', 'text/javascript'
				JSON.parse( payload )
			when 'application/x-yaml', 'text/x-yaml'
				YAML.load( payload )
			else
				payload
			end

		return work_payload
	end


	### Return a consumer tag for this task's queue consumer.
	def make_consumer_tag
		return "%s.%s.%d" % [
			self.queue_name,
			Socket.gethostname.gsub(/\..*$/, ''),
			Process.pid,
		]
	end


	### Do work based on the given message +payload+ and +metadata+.
	def work( payload, metadata )
		raise NotImplementedError,
			"%p doesn't implement required method #work" % [ self.class ]
	end


	### Wrap a timeout around the call to work, and handle timeouts according to
	### the configured timeout_action.
	def work_with_timeout( payload, metadata )
		Timeout.timeout( self.class.timeout ) do
			return self.work( payload, metadata )
		end
	rescue Timeout::Error
		self.log.error "Timed out while performing work"
		raise if self.class.timeout_action == :reject
		return false
	end


	### Return a string for setting the proc title
	def procname
		return "%s %s: Symphony: %p (%s) -> %s" % [
			RUBY_ENGINE,
			RUBY_VERSION,
			self.class,
			self.class.work_model,
			self.class.queue_name
		]
	end


	### Handle a hangup signal by re-reading the config and restarting.
	def on_hangup
		self.log.info "Hangup signal."
		self.restart
	end


	### Handle a termination or interrupt signal.
	def on_terminate
		self.log.debug "Signalled to shut down."

		if self.shutting_down?
			self.stop_immediately
		else
			self.stop_gracefully
		end
	end
	alias_method :on_interrupt, :on_terminate


end # class Symphony::Task

