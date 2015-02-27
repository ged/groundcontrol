#!/usr/bin/env rspec -cfd

require_relative '../../helpers'

require 'symphony/task_group/longlived'

describe Symphony::TaskGroup::LongLived do

	let( :task ) do
		Class.new( Symphony::Task ) do
			extend Symphony::MethodUtilities

			singleton_attr_accessor :has_before_forked, :has_after_forked, :has_run

			def self::before_fork
				self.has_before_forked = true
			end
			def self::after_fork
				self.has_after_forked = true
			end
			def self::run
				self.has_run = true
			end
		end
	end

	let( :task_group ) do
		described_class.new( task, 2 )
	end


	# not enough samples
	# trending up



	it "doesn't start anything if it's throttled" do
		# Simulate a child starting up and failing
		task_group.instance_variable_set( :@last_child_started, Time.now )
		task_group.adjust_throttle( 5 )

		expect( Process ).to_not receive( :fork )
		expect( task_group.adjust_workers ).to be_nil
	end


	context "when told to adjust its worker pool" do

		it "starts an initial worker if it doesn't have any" do
			expect( Process ).to receive( :fork ).and_return( 414 )
			allow( Process ).to receive( :setpgid ).with( 414, 0 )

			channel = double( Bunny::Channel )
			queue = double( Bunny::Queue )
			expect( Symphony::Queue ).to receive( :amqp_channel ).
				and_return( channel )
			expect( channel ).to receive( :queue ).
				with( task.queue_name, passive: true, prefetch: 0 ).
				and_return( queue )

			task_group.adjust_workers

			expect( task_group.started_one_worker? ).to be_truthy
			expect( task_group.pids ).to include( 414 )
		end


		it "starts an additional worker if its work load is trending upward" do
			samples = [ 1, 2, 2, 3, 3, 3, 4 ]
			task_group.sample_size = samples.size

			expect( Process ).to receive( :fork ).and_return( 525, 528 )
			allow( Process ).to receive( :setpgid )

			channel = double( Bunny::Channel )
			queue = double( Bunny::Queue )
			expect( Symphony::Queue ).to receive( :amqp_channel ).
				and_return( channel )
			expect( channel ).to receive( :queue ).
				with( task.queue_name, passive: true, prefetch: 0 ).
				and_return( queue )

			allow( queue ).to receive( :consumer_count ).and_return( 1 )
			expect( queue ).to receive( :message_count ).and_return( *samples )

			start = 1414002605
			start.upto( start + samples.size ) do |time|
				Timecop.freeze( time ) do
					task_group.adjust_workers
				end
			end

			expect( task_group.started_one_worker? ).to be_truthy
			expect( task_group.pids ).to include( 525, 528 )
		end


		it "starts an additional worker if its work load is holding steady at a non-zero value" do
			pending "this being a problem we see in practice"
			samples = [ 4, 4, 4, 5, 5, 4, 4 ]
			task_group.sample_size = samples.size

			expect( Process ).to receive( :fork ).and_return( 525, 528 )
			allow( Process ).to receive( :setpgid )

			channel = double( Bunny::Channel )
			queue = double( Bunny::Queue )
			expect( Symphony::Queue ).to receive( :amqp_channel ).
				and_return( channel )
			expect( channel ).to receive( :queue ).
				with( task.queue_name, passive: true, prefetch: 0 ).
				and_return( queue )

			allow( queue ).to receive( :consumer_count ).and_return( 1 )
			expect( queue ).to receive( :message_count ).and_return( *samples )

			start = 1414002605
			start.upto( start + samples.size ) do |time|
				Timecop.freeze( time ) do
					task_group.adjust_workers
				end
			end

			expect( task_group.pids.size ).to eq( 2 )
		end


		it "doesn't start a worker if it's already running the maximum number of workers" do
			samples =   [ 1, 2, 2, 3, 3, 3, 4, 4, 4, 5 ]
			consumers = [ 1, 1, 1, 1, 1, 1, 1, 2, 2, 2 ]
			task_group.sample_size = samples.size - 3

			expect( Process ).to receive( :fork ).and_return( 525, 528 )
			allow( Process ).to receive( :setpgid )

			channel = double( Bunny::Channel )
			queue = double( Bunny::Queue )
			expect( Symphony::Queue ).to receive( :amqp_channel ).
				and_return( channel )
			expect( channel ).to receive( :queue ).
				with( task.queue_name, passive: true, prefetch: 0 ).
				and_return( queue )

			expect( queue ).to receive( :consumer_count ).and_return( *consumers )
			expect( queue ).to receive( :message_count ).and_return( *samples )

			start = 1414002605
			start.upto( start + samples.size ) do |time|
				Timecop.freeze( time ) do
					task_group.adjust_workers
				end
			end

			expect( task_group.pids.size ).to eq( 2 )
		end


		it "doesn't start anything if its work load is holding steady at zero" do
			samples = [ 0, 1, 0, 0, 0, 0, 1, 0, 0 ]
			task_group.sample_size = samples.size - 3

			expect( Process ).to receive( :fork ).and_return( 525 )
			allow( Process ).to receive( :setpgid )

			channel = double( Bunny::Channel )
			queue = double( Bunny::Queue )
			expect( Symphony::Queue ).to receive( :amqp_channel ).
				and_return( channel )
			expect( channel ).to receive( :queue ).
				with( task.queue_name, passive: true, prefetch: 0 ).
				and_return( queue )

			allow( queue ).to receive( :consumer_count ).and_return( 1 )
			expect( queue ).to receive( :message_count ).and_return( *samples )

			start = 1414002605
			start.upto( start + samples.size ) do |time|
				Timecop.freeze( time ) do
					task_group.adjust_workers
				end
			end

			expect( task_group.pids.size ).to eq( 1 )
		end


		it "doesn't start anything if its work load is trending downward" do
			samples = [ 4, 3, 3, 2, 2, 2, 1, 1, 0, 0 ]
			task_group.sample_size = samples.size

			expect( Process ).to receive( :fork ).and_return( 525 )
			allow( Process ).to receive( :setpgid )

			channel = double( Bunny::Channel )
			queue = double( Bunny::Queue )
			expect( Symphony::Queue ).to receive( :amqp_channel ).
				and_return( channel )
			expect( channel ).to receive( :queue ).
				with( task.queue_name, passive: true, prefetch: 0 ).
				and_return( queue )

			allow( queue ).to receive( :consumer_count ).and_return( 1 )
			expect( queue ).to receive( :message_count ).and_return( *samples )

			start = 1414002605
			start.upto( start + samples.size ) do |time|
				Timecop.freeze( time ) do
					task_group.adjust_workers
				end
			end

			expect( task_group.started_one_worker? ).to be_truthy
			expect( task_group.pids.size ).to eq( 1 )
		end

	end

end
