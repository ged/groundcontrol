#!/usr/bin/env rspec

BEGIN {
	require 'pathname'
	invdir = Pathname( __FILE__ ).dirname.parent.parent.parent
	basedir = invdir.parent

	libdir = invdir + 'lib'
	dbdir = basedir + 'laika-db'

	$LOAD_PATH.unshift( invdir.to_s ) unless $LOAD_PATH.include?( invdir.to_s )
	$LOAD_PATH.unshift( libdir.to_s ) unless $LOAD_PATH.include?( libdir.to_s )
	$LOAD_PATH.unshift( dbdir.to_s ) unless $LOAD_PATH.include?( dbdir.to_s )
}

require 'rspec'

require 'spec/lib/groundcontrolhelpers'
require 'spec/lib/groundcontrolconstants'
require 'spec/lib/dbhelpers'

require 'laika'
require 'laika/groundcontrol'
require 'laika/featurebehavior'


describe LAIKA::GroundControl::Task do

	before( :all ) do
		setup_logging( :fatal )
		setup_test_database()
		LAIKA::GroundControl::Job.create_schema!( :groundcontrol ) # Workaround for Sequel bug
		LAIKA::GroundControl::Job.create_table!
	end

	after( :each ) do
		LAIKA::GroundControl::Job.truncate
	end

	after( :all ) do
		LAIKA::GroundControl::Job.drop_table
		LAIKA::GroundControl::Job.drop_schema( :groundcontrol )
		cleanup_test_database()
	end


	


end
