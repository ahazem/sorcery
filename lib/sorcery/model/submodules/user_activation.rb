module Sorcery
  module Model
    module Submodules
      # This submodule adds the ability to make the user activate his account via email
      # or any other way in which he can recieve an activation code.
      # with the activation code the user may activate his account.
      # When using this submodule, supplying a mailer is mandatory.
      module UserActivation
        def self.included(base)
          base.sorcery_config.class_eval do
            attr_accessor :activation_state_attribute_name,               # the attribute name to hold activation state
                                                                          # (active/pending).
                                                                          
                          :activation_token_attribute_name,               # the attribute name to hold activation code
                                                                          # (sent by email).
                                                                          
                          :activation_token_expires_at_attribute_name,    # the attribute name to hold activation code
                                                                          # expiration date. 
                                                                          
                          :activation_token_expiration_period,            # how many seconds before the activation code
                                                                          # expires. nil for never expires.
                                                                          
                          :user_activation_mailer,                        # your mailer class. Required.
                          :activation_needed_email_method_name,           # activation needed email method on your
                                                                          # mailer class.
                                                                          
                          :activation_success_email_method_name,          # activation success email method on your
                                                                          # mailer class.
                                                                          
                          :prevent_non_active_users_to_login              # do you want to prevent or allow users that
                                                                          # did not activate by email to login?
          end
          
          base.sorcery_config.instance_eval do
            @defaults.merge!(:@activation_state_attribute_name             => :activation_state,
                             :@activation_token_attribute_name             => :activation_token,
                             :@activation_token_expires_at_attribute_name  => :activation_token_expires_at,
                             :@activation_token_expiration_period          => nil,
                             :@user_activation_mailer                      => nil,
                             :@activation_needed_email_method_name         => :activation_needed_email,
                             :@activation_success_email_method_name        => :activation_success_email,
                             :@prevent_non_active_users_to_login           => true)
            reset!
          end
          
          base.class_eval do
            # don't setup activation if no password supplied - this user is created automatically
            before_create :setup_activation, :if => Proc.new { |user| user.send(sorcery_config.password_attribute_name).present? }
            # don't send activation needed email if no crypted password created - this user is external (OAuth etc.)
            after_create  :send_activation_needed_email!, :if => Proc.new { |user| !user.external?}
          end
          
          base.sorcery_config.after_config << :validate_mailer_defined
          base.sorcery_config.after_config << :define_user_activation_mongoid_fields if defined?(Mongoid) and base.ancestors.include?(Mongoid::Document)
          base.sorcery_config.before_authenticate << :prevent_non_active_login
          
          base.extend(ClassMethods)
          base.send(:include, InstanceMethods)


        end
        
        module ClassMethods
          # Find user by token, also checks for expiration.
          # Returns the user if token found and is valid.
          def load_from_activation_token(token)
            token_attr_name = @sorcery_config.activation_token_attribute_name
            token_expiration_date_attr = @sorcery_config.activation_token_expires_at_attribute_name
            load_from_token(token, token_attr_name, token_expiration_date_attr)
          end
          
          protected
          
          # This submodule requires the developer to define his own mailer class to be used by it.
          def validate_mailer_defined
            msg = "To use user_activation submodule, you must define a mailer (config.user_activation_mailer = YourMailerClass)."
            raise ArgumentError, msg if @sorcery_config.user_activation_mailer == nil
          end

          def define_user_activation_mongoid_fields
            self.class_eval do
              field sorcery_config.activation_state_attribute_name,            :type => String
              field sorcery_config.activation_token_attribute_name,            :type => String
              field sorcery_config.activation_token_expires_at_attribute_name, :type => DateTime
            end
          end
        end
        
        module InstanceMethods
          # clears activation code, sets the user as 'active' and optionaly sends a success email.
          def activate!
            config = sorcery_config
            self.send(:"#{config.activation_token_attribute_name}=", nil)
            self.send(:"#{config.activation_state_attribute_name}=", "active")
            send_activation_success_email! unless self.external?
            save!(:validate => false) # don't run validations
          end
          
          protected

          def setup_activation
            config = sorcery_config
            generated_activation_token = TemporaryToken.generate_random_token
            self.send(:"#{config.activation_token_attribute_name}=", generated_activation_token)
            self.send(:"#{config.activation_state_attribute_name}=", "pending")
            self.send(:"#{config.activation_token_expires_at_attribute_name}=", Time.now.utc + config.activation_token_expiration_period) if config.activation_token_expiration_period
          end

          # called automatically after user initial creation.
          def send_activation_needed_email!
            generic_send_email(:activation_needed_email_method_name, :user_activation_mailer) unless sorcery_config.activation_needed_email_method_name.nil?
          end

          def send_activation_success_email!
            generic_send_email(:activation_success_email_method_name, :user_activation_mailer) unless sorcery_config.activation_success_email_method_name.nil?
          end
          
          def prevent_non_active_login
            config = sorcery_config
            config.prevent_non_active_users_to_login ? self.send(config.activation_state_attribute_name) == "active" : true
          end

        end
      end
    end
  end
end