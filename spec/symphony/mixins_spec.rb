#!/usr/bin/env rspec -wfd

require_relative '../helpers'

require 'symphony/mixins'


RSpec.describe Symphony, 'mixins' do

	describe Symphony::MethodUtilities, 'used to extend a class' do

		let!( :extended_class ) do
			klass = Class.new do
				def initialize
					@foo = nil
				end
			end
			klass.extend( Symphony::MethodUtilities )
			klass
		end

		it "can declare a class-level attribute reader" do
			extended_class.singleton_attr_reader :foo
			expect( extended_class ).to respond_to( :foo )
			expect( extended_class ).to_not respond_to( :foo= )
			expect( extended_class ).to_not respond_to( :foo? )
		end

		it "can declare a class-level attribute writer" do
			extended_class.singleton_attr_writer :foo
			expect( extended_class ).to_not respond_to( :foo )
			expect( extended_class ).to respond_to( :foo= )
			expect( extended_class ).to_not respond_to( :foo? )
		end

		it "can declare a class-level attribute reader and writer" do
			extended_class.singleton_attr_accessor :foo
			expect( extended_class ).to respond_to( :foo )
			expect( extended_class ).to respond_to( :foo= )
			expect( extended_class ).to_not respond_to( :foo? )
		end

		it "can declare a class-level alias" do
			def extended_class.foo
				return "foo"
			end
			extended_class.singleton_method_alias( :bar, :foo )

			expect( extended_class.bar ).to eq( 'foo' )
		end

		it "can declare an instance attribute predicate method" do
			extended_class.attr_predicate :foo
			instance = extended_class.new

			expect( instance ).to_not respond_to( :foo )
			expect( instance ).to_not respond_to( :foo= )
			expect( instance ).to respond_to( :foo? )

			expect( instance.foo? ).to eq( false )

			instance.instance_variable_set( :@foo, 1 )
			expect( instance.foo? ).to eq( true )
		end

		it "can declare an instance attribute predicate and writer" do
			extended_class.attr_predicate_accessor :foo
			instance = extended_class.new

			expect( instance ).to_not respond_to( :foo )
			expect( instance ).to respond_to( :foo= )
			expect( instance ).to respond_to( :foo? )

			expect( instance.foo? ).to eq( false )

			instance.foo = 1
			expect( instance.foo? ).to eq( true )
		end

	end

end
