module RailsStudio                   #:nodoc:
  module Acts                        #:nodoc:
    module StateMachine              #:nodoc:
      class InvalidState < Exception #:nodoc:
      end
      class NoInitialState < Exception #:nodoc:
      end
      
      def self.included(base)        #:nodoc:
        base.extend ActMacro
      end
      
      module ActMacro
        # Configuration options are
        #
        # * +column+ - specifies the column name to use for keeping the state (default: state)
        # * +initial+ - specifies an initial state for newly created objects (required)
        def acts_as_state_machine(opts)
          self.extend(ClassMethods)
          raise NoInitialState unless opts[:initial]
          
          write_inheritable_attribute :states, {}
          write_inheritable_attribute :initial_state, opts[:initial]
          write_inheritable_attribute :transition_table, {}
          write_inheritable_attribute :state_column, opts[:column] || 'state'
          
          class_inheritable_reader    :initial_state
          class_inheritable_reader    :state_column
          class_inheritable_reader    :transition_table
          
          class_eval "include RailsStudio::Acts::StateMachine::InstanceMethods"

          before_create               :set_initial_state
        end
      end
      
      module InstanceMethods
        def set_initial_state #:nodoc:
          write_attribute self.class.state_column, self.class.initial_state.to_s
        end
      
        # Returns the current state the object is in, as a Ruby symbol.
        def current_state
          self.send(self.class.state_column).to_sym
        end
      
        # Returns what the next state for a given event would be, as a Ruby symbol.
        def next_state_for_event(event)
          self.class.read_inheritable_attribute(:transition_table)[event.to_sym][current_state]
        end
      end

      module ClassMethods
        # Returns an array of all known states.
        def states
          read_inheritable_attribute(:states).keys
        end
        
        # Define an event.  This takes a block which describes all valid transitions
        # for this event.
        #
        # Example:
        #
        # class Order < ActiveRecord::Base
        #   acts_as_state_machine :initial => :open
        #
        #   state :open
        #   state :closed
        #
        #   event :close_order do
        #     transitions :to => :closed, :from => :open
        #   end
        # end
        #
        # +transitions+ takes a hash where <tt>:to</tt> is the state to transition
        # to and <tt>:from</tt> is a state (or Array of states) from which this
        # event can be fired.
        #
        # This creates an instance method used for firing the event.  The method
        # created is the name of the event followed by an exclamation point (!).
        # Example: <tt>order.close_order!</tt>.
        def event(event, &block)
          class_eval <<-EOV
          def #{event.to_s}!
            ns = next_state_for_event(:#{event.to_s})
            if ns
              self.update_attribute(self.class.state_column, ns.to_s)
              if (p = self.class.read_inheritable_attribute(:states)[ns])
                p.call self
              end
            end
          end
          EOV
          
          tt = read_inheritable_attribute(:transition_table)
          tt[event.to_sym] ||= {}
          
          if block_given?
            trannys = instance_eval(&block)
            Array(trannys[:from]).each do |s|
              tt[event.to_sym][s.to_sym] = trannys[:to]
            end
          end
        end
        
        def transitions(opts)        #:nodoc:
          opts
        end

        # Define a state of the system. +state+ can take an optional Proc object
        # which will be executed every time the system transitions into that
        # state.  The proc will be passed the current object.
        #
        # Example:
        #
        # class Order < ActiveRecord::Base
        #   acts_as_state_machine :initial => :open
        #
        #   state :open
        #   state :closed, Proc.new { |o| Mailer.send_notice(o) }
        # end
        def state(state, proc=nil)
          read_inheritable_attribute(:states)[state.to_sym] = proc
        end
        
        # Wraps ActiveRecord::Base.find to conveniently find all records in
        # a given state.  Options:
        #
        # * +number+ - This is just :first or :all from ActiveRecord
        # * +state+ - The state to find
        # * +args+ - The rest of the args are passed down to ActiveRecord +find+
        def find_in_state(number, state, *args)
          raise InvalidState unless states.include?(state)
          
          options = args.last.is_a?(Hash) ? args.pop : {}
          if options[:conditions]
            options[:conditions].first << " AND #{self.state_column} = ?"
            options[:conditions] << state.to_s
          else
            options[:conditions] = ["#{self.state_column} = ?", state.to_s]
          end
          self.find(number, options)
        end
        
        # Wraps ActiveRecord::Base.count to conveniently count all records in
        # a given state.  Options:
        #
        # * +state+ - The state to find
        # * +args+ - The rest of the args are passed down to ActiveRecord +find+
        def count_in_state(state, conditions=nil)
          raise InvalidState unless states.include?(state)
          
          if conditions
            conditions.first << " AND #{self.state_column} = ?"
            conditions << state.to_s
          else
            conditions = ["#{self.state_column} = ?", state.to_s]
          end
          self.count(conditions)
        end
      end
    end
  end
end