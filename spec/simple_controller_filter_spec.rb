# frozen_string_literal: true

require 'spec_helper'
require 'action_controller'
require 'active_support/core_ext/string/output_safety'
require 'ostruct'

RSpec.describe SeamlessDatabasePool::ControllerFilter do
  let(:base_controller_class) do
    Class.new(ActionController::Metal) do
      include AbstractController::Callbacks
      include ActionController::Redirecting

      include ::SeamlessDatabasePool::SimpleControllerFilter

      attr_reader :session

      def initialize(session)
        super()
        @session = session
        @_response = OpenStruct.new
        @_request = OpenStruct.new
        @_routes = nil
      end

      def base_action
        ::SeamlessDatabasePool.read_only_connection_type
      end
    end
  end
  let(:session) { {} }
  let(:controller) { controller_class.new(session) }

  context 'when nothing set' do
    let(:controller_class) { Class.new(base_controller_class) }

    it 'uses master' do
      expect(controller.send(:process_action, 'base_action')).to eq :master
    end
  end

  context 'when set' do
    let(:controller_class) do
      Class.new(base_controller_class) do
        use_database_pool :persistent

        def action_with_redirect
          SeamlessDatabasePool.use_master_connection
          redirect_to('http://example.org') # using full url to skip missing url helpers
        end
      end
    end

    it 'uses that pool' do
      expect(controller.send(:process_action, 'base_action')).to eq :persistent
    end

    it 'uses master when set in session' do
      controller.send(:use_master_db_connection_on_next_request)
      expect(controller.send(:process_action, 'base_action')).to eq :master
    end

    it 'persists in session on redirect' do
      controller.send(:process_action, 'action_with_redirect')
      expect(controller.send(:process_action, 'base_action')).to eq :master
    end
  end

  context 'when set in parent and skipped in self' do
    let(:controller_parent_class) do
      Class.new(base_controller_class) do
        use_database_pool :persistent
      end
    end
    let(:controller_class) do
      Class.new(controller_parent_class) do
        skip_use_database_pool raise: false
      end
    end

    it 'uses master' do
      expect(controller.send(:process_action, 'base_action')).to eq :master
    end
  end
end
