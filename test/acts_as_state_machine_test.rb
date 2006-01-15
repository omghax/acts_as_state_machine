require File.dirname(__FILE__) + '/test_helper'

class ActsAsStateMachineTest < Test::Unit::TestCase
  fixtures :conversations
  
  def test_no_initial_value_raises_exception
    assert_raise(RailsStudio::Acts::StateMachine::NoInitialState) {
      Person.acts_as_state_machine({})
    }
  end
  
  def test_initial_state_value
    assert_equal :needs_attention, Conversation.initial_state
  end
  
  def test_column_was_set
    assert_equal 'state_machine', Conversation.state_column
  end
  
  def test_initial_state
    c = Conversation.create
    assert_equal :needs_attention, c.current_state
  end
  
  def test_states_were_set
    [:needs_attention, :read, :closed, :awaiting_response, :junk].each do |s|
      assert Conversation.states.include?(s)
    end
  end
  
  def test_event_methods_created
    c = Conversation.create
    %w(new_message! view! reply! close! junk! unjunk!).each do |event|
      assert c.respond_to?(event)
    end
  end
  
  def test_transition_table
    tt = Conversation.transition_table
    
    assert_equal tt[:new_message][:read],              :needs_attention
    assert_equal tt[:new_message][:closed],            :needs_attention
    assert_equal tt[:new_message][:awaiting_response], :needs_attention
  end

  def test_next_state_for_event
    c = Conversation.create
    assert_equal :read, c.next_state_for_event(:view)
  end
  
  def test_change_state
    c = Conversation.create
    c.view!
    assert_equal :read, c.current_state
  end
  
  def test_ignore_invalid_events
    c = Conversation.create
    c.view!
    c.junk!
    
    # This is the invalid event
    c.new_message!
    assert_equal :junk, c.current_state
  end
  
  def test_transition_block_is_executed
    c = Conversation.create
    c.view!

    # This should execute the block
    c.close!
    assert c.reload.closed?
  end
  
  
  def test_find_all_in_state
    cs = Conversation.find_in_state(:all, :read)
    
    assert_equal 2, cs.size
  end
  
  def test_find_first_in_state
    c = Conversation.find_in_state(:first, :read)
    
    assert_equal conversations(:first).id, c.id
  end
  
  def test_find_all_in_state_with_conditions
    cs = Conversation.find_in_state(:all, :read, :conditions => ['subject = ?', conversations(:second).subject])
    
    assert_equal 1, cs.size
    assert_equal conversations(:second).id, cs.first.id
  end
  
  def test_find_first_in_state_with_conditions
    c = Conversation.find_in_state(:first, :read, :conditions => ['subject = ?', conversations(:second).subject])
    assert_equal conversations(:second).id, c.id
  end
  
  def test_count_in_state
    cnt0 = Conversation.count(['state_machine = ?', 'read'])
    cnt  = Conversation.count_in_state(:read)
    
    assert_equal cnt0, cnt
  end
  
  def test_count_in_state_with_conditions
    cnt0 = Conversation.count(['state_machine = ? AND subject = ?', 'read', 'Foo'])
    cnt  = Conversation.count_in_state(:read, ['subject = ?', 'Foo'])
    
    assert_equal cnt0, cnt
  end
  
  def test_find_in_invalid_state_raises_exception
    assert_raise(RailsStudio::Acts::StateMachine::InvalidState) {
      Conversation.find_in_state(:all, :dead)
    }
  end
  
  def test_count_in_invalid_state_raises_exception
    assert_raise(RailsStudio::Acts::StateMachine::InvalidState) {
      Conversation.count_in_state(:dead)
    }
  end
end
