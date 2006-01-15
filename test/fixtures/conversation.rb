class Conversation < ActiveRecord::Base
  acts_as_state_machine :initial => :needs_attention, :column => 'state_machine'
  
  state :needs_attention
  state :read
  state :closed, Proc.new { |o| o.update_attribute :closed, true }
  state :awaiting_response
  state :junk
  
  event :new_message do
    transitions :to => :needs_attention,   :from => [:read, :closed, :awaiting_response]
  end

  event :view do
    transitions :to => :read,              :from => :needs_attention
  end
  
  event :reply do
    transitions :to => :awaiting_response, :from => [:read, :closed]
  end
  
  event :close do
    transitions :to => :closed,            :from => [:read, :awaiting_response]
  end
  
  event :junk do
    transitions :to => :junk,              :from => [:read, :closed, :awaiting_response]
  end
  
  event :unjunk do
    transitions :to => :closed,            :from => :junk
  end
end
