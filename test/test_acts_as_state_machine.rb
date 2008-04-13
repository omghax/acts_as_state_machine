RAILS_ROOT = File.dirname(__FILE__)

require "rubygems"
require "test/unit"
require "active_record"
require "active_record/fixtures"

$:.unshift File.dirname(__FILE__) + "/../lib"
require File.dirname(__FILE__) + "/../init"

# Log everything to a global StringIO object instead of a file.
require "stringio"
$LOG = StringIO.new
$LOGGER = Logger.new($LOG)
ActiveRecord::Base.logger = $LOGGER

ActiveRecord::Base.configurations = {
  "sqlite" => {
    :adapter => "sqlite",
    :dbfile  => "state_machine.sqlite.db"
  },

  "sqlite3" => {
    :adapter => "sqlite3",
    :dbfile  => "state_machine.sqlite3.db"
  },

  "mysql" => {
    :adapter  => "mysql",
    :host     => "localhost",
    :username => "rails",
    :password => nil,
    :database => "state_machine_test"
  },

  "postgresql" => {
    :min_messages => "ERROR",
    :adapter      => "postgresql",
    :username     => "postgres",
    :password     => "postgres",
    :database     => "state_machine_test"
  }
}

# Connect to the database.
ActiveRecord::Base.establish_connection(ENV["DB"] || "sqlite")

# Create table for conversations.
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define(:version => 1) do
  create_table :conversations, :force => true do |t|
    t.column :state_machine, :string
    t.column :subject,       :string
    t.column :closed,        :boolean
  end
end

class Test::Unit::TestCase
  self.fixture_path = File.dirname(__FILE__) + "/fixtures/"
  self.use_transactional_fixtures = true
  self.use_instantiated_fixtures  = false

  def create_fixtures(*table_names, &block)
    Fixtures.create_fixtures(Test::Unit::TestCase.fixture_path, table_names, &block)
  end
end

class Conversation < ActiveRecord::Base
  attr_writer :can_close
  attr_accessor :read_enter, :read_exit,
                :needs_attention_enter, :needs_attention_after,
                :read_after_first, :read_after_second,
                :closed_after

  # How's THAT for self-documenting? ;-)
  def always_true
    true
  end

  def can_close?
    !!@can_close
  end

  def read_enter_action
    self.read_enter = true
  end

  def read_after_first_action
    self.read_after_first = true
  end

  def read_after_second_action
    self.read_after_second = true
  end

  def closed_after_action
    self.closed_after = true
  end
end

class ActsAsStateMachineTest < Test::Unit::TestCase
  include ScottBarron::Acts::StateMachine
  fixtures :conversations

  def teardown
    Conversation.class_eval do
      write_inheritable_attribute :states, {}
      write_inheritable_attribute :initial_state, nil
      write_inheritable_attribute :transition_table, {}
      write_inheritable_attribute :event_table, {}
      write_inheritable_attribute :state_column, "state"

      # Clear out any callbacks that were set by acts_as_state_machine.
      write_inheritable_attribute :before_create, []
      write_inheritable_attribute :after_create, []
    end
  end

  def test_no_initial_value_raises_exception
    assert_raises(NoInitialState) do
      Conversation.class_eval { acts_as_state_machine }
    end
  end

  def test_state_column
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
    end

    assert_equal "state_machine", Conversation.state_column
  end

  def test_initial_state_value
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
    end

    assert_equal :needs_attention, Conversation.initial_state
  end

  def test_initial_state
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
    end

    c = Conversation.create!
    assert_equal :needs_attention, c.current_state
    assert c.needs_attention?
  end

  def test_states_were_set
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response
      state :junk
    end

    [:needs_attention, :read, :closed, :awaiting_response, :junk].each do |state|
      assert Conversation.states.include?(state)
    end
  end

  def test_query_methods_created
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response
      state :junk
    end

    c = Conversation.create!
    [:needs_attention?, :read?, :closed?, :awaiting_response?, :junk?].each do |query|
      assert c.respond_to?(query)
    end
  end

  def test_event_methods_created
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response
      state :junk

      event(:new_message) {}
      event(:view) {}
      event(:reply) {}
      event(:close) {}
      event(:junk, :note => "finished") {}
      event(:unjunk) {}
    end

    c = Conversation.create!
    [:new_message!, :view!, :reply!, :close!, :junk!, :unjunk!].each do |event|
      assert c.respond_to?(event)
    end
  end

  def test_transition_table
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response
      state :junk

      event :new_message do
        transitions :to => :needs_attention, :from => [:read, :closed, :awaiting_response]
      end
    end

    tt = Conversation.transition_table
    assert tt[:new_message].include?(SupportingClasses::StateTransition.new(:from => :read, :to => :needs_attention))
    assert tt[:new_message].include?(SupportingClasses::StateTransition.new(:from => :closed, :to => :needs_attention))
    assert tt[:new_message].include?(SupportingClasses::StateTransition.new(:from => :awaiting_response, :to => :needs_attention))
  end

  def test_next_state_for_event
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end
    end

    c = Conversation.create!
    assert_equal :read, c.next_state_for_event(:view)
  end

  def test_change_state
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end
    end

    c = Conversation.create!
    c.view!
    assert c.read?
  end

  def test_can_go_from_read_to_closed_because_guard_passes
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end

      event :reply do
        transitions :to => :awaiting_response, :from => [:read, :closed]
      end

      event :close do
        transitions :to => :closed, :from => [:read, :awaiting_response], :guard => lambda { |o| o.can_close? }
      end
    end

    c = Conversation.create!
    c.can_close = true
    c.view!
    c.reply!
    c.close!
    assert_equal :closed, c.current_state
  end

  def test_cannot_go_from_read_to_closed_because_of_guard
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end

      event :reply do
        transitions :to => :awaiting_response, :from => [:read, :closed]
      end

      event :close do
        transitions :to => :closed, :from => [:read, :awaiting_response], :guard => lambda { |o| o.can_close? }
        transitions :to => :read, :from => [:read, :awaiting_response], :guard => :always_true
      end
    end

    c = Conversation.create!
    c.can_close = false
    c.view!
    c.reply!
    c.close!
    assert_equal :read, c.current_state
  end

  def test_ignore_invalid_events
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read
      state :closed
      state :awaiting_response
      state :junk

      event :new_message do
        transitions :to => :needs_attention, :from => [:read, :closed, :awaiting_response]
      end

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end

      event :junk, :note => "finished" do
        transitions :to => :junk, :from => [:read, :closed, :awaiting_response]
      end
    end

    c = Conversation.create
    c.view!
    c.junk!

    # This is the invalid event
    c.new_message!
    assert_equal :junk, c.current_state
  end

  def test_entry_action_executed
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read, :enter => :read_enter_action

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end
    end

    c = Conversation.create!
    c.read_enter = false
    c.view!
    assert c.read_enter
  end

  def test_after_actions_executed
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :closed, :after => :closed_after_action
      state :read, :enter => :read_enter_action,
      :exit  => Proc.new { |o| o.read_exit = true },
      :after => [:read_after_first_action, :read_after_second_action]

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end

      event :close do
        transitions :to => :closed, :from => [:read, :awaiting_response]
      end
    end

    c = Conversation.create!

    c.read_after_first = false
    c.read_after_second = false
    c.closed_after = false

    c.view!
    assert c.read_after_first
    assert c.read_after_second

    c.can_close = true
    c.close!

    assert c.closed_after
    assert_equal :closed, c.current_state
  end

  def test_after_actions_not_run_on_loopback_transition
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :closed, :after => :closed_after_action
      state :read, :after => [:read_after_first_action, :read_after_second_action]

      event :view do
        transitions :to => :read, :from => :needs_attention
      end

      event :close do
        transitions :to => :closed, :from => :read
      end
    end

    c = Conversation.create!

    c.view!
    c.read_after_first = false
    c.read_after_second = false
    c.view!

    assert !c.read_after_first
    assert !c.read_after_second

    c.can_close = true

    c.close!
    c.closed_after = false
    c.close!

    assert !c.closed_after
  end

  def test_exit_action_executed
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :junk
      state :needs_attention
      state :read, :exit => lambda { |o| o.read_exit = true }

      event :view do
        transitions :to => :read, :from => :needs_attention
      end

      event :junk, :note => "finished" do
        transitions :to => :junk, :from => :read
      end
    end

    c = Conversation.create!
    c.read_exit = false
    c.view!
    c.junk!
    assert c.read_exit
  end

  def test_entry_and_exit_not_run_on_loopback_transition
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
      state :read, :exit => lambda { |o| o.read_exit = true }

      event :view do
        transitions :to => :read, :from => [:needs_attention, :read]
      end
    end

    c = Conversation.create!
    c.view!
    c.read_enter = false
    c.read_exit  = false
    c.view!
    assert !c.read_enter
    assert !c.read_exit
  end

  def test_entry_and_after_actions_called_for_initial_state
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention, :enter => lambda { |o| o.needs_attention_enter = true },
      :after => lambda { |o| o.needs_attention_after = true }
    end

    c = Conversation.create!
    assert c.needs_attention_enter
    assert c.needs_attention_after
  end

  def test_run_transition_action_is_private
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention
      state :needs_attention
    end

    c = Conversation.create!
    assert_raises(NoMethodError) { c.run_transition_action :foo }
  end

  def test_find_all_in_state
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
      state :read
    end

    cs = Conversation.find_in_state(:all, :read)
    assert_equal 2, cs.size
  end

  def test_find_first_in_state
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
      state :read
    end

    c = Conversation.find_in_state(:first, :read)
    assert_equal conversations(:first).id, c.id
  end

  def test_find_all_in_state_with_conditions
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
      state :read
    end

    cs = Conversation.find_in_state(:all, :read, :conditions => ['subject = ?', conversations(:second).subject])

    assert_equal 1, cs.size
    assert_equal conversations(:second).id, cs.first.id
  end

  def test_find_first_in_state_with_conditions
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
      state :read
    end

    c = Conversation.find_in_state(:first, :read, :conditions => ['subject = ?', conversations(:second).subject])
    assert_equal conversations(:second).id, c.id
  end

  def test_count_in_state
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
      state :read
    end

    cnt0 = Conversation.count(:conditions => ['state_machine = ?', 'read'])
    cnt  = Conversation.count_in_state(:read)

    assert_equal cnt0, cnt
  end

  def test_count_in_state_with_conditions
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
      state :read
    end

    cnt0 = Conversation.count(:conditions => ['state_machine = ? AND subject = ?', 'read', 'Foo'])
    cnt  = Conversation.count_in_state(:read, :conditions => ['subject = ?', 'Foo'])

    assert_equal cnt0, cnt
  end

  def test_find_in_invalid_state_raises_exception
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
      state :read
    end

    assert_raises(InvalidState) do
      Conversation.find_in_state(:all, :dead)
    end
  end

  def test_count_in_invalid_state_raises_exception
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
      state :read
    end

    assert_raise(InvalidState) do
      Conversation.count_in_state(:dead)
    end
  end

  def test_can_access_events_via_event_table
    Conversation.class_eval do
      acts_as_state_machine :initial => :needs_attention, :column => "state_machine"
      state :needs_attention
      state :junk

      event :junk, :note => "finished" do
        transitions :to => :junk, :from => :needs_attention
      end
    end

    event = Conversation.event_table[:junk]
    assert_equal :junk, event.name
    assert_equal "finished", event.opts[:note]
  end

  def test_custom_state_values
    Conversation.class_eval do
      acts_as_state_machine :initial => "NEEDS_ATTENTION", :column => "state_machine"
      state :needs_attention, :value => "NEEDS_ATTENTION"
      state :read, :value => "READ"

      event :view do
        transitions :to => "READ", :from => ["NEEDS_ATTENTION", "READ"]
      end
    end

    c = Conversation.create!
    assert_equal "NEEDS_ATTENTION", c.state_machine
    assert c.needs_attention?
    c.view!
    assert_equal "READ", c.state_machine
    assert c.read?
  end
end
