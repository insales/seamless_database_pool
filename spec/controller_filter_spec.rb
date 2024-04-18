# frozen_string_literal: true

require 'spec_helper'

module SeamlessDatabasePool
  class TestApplicationController
    attr_reader :session

    def initialize(session)
      @session = session
    end

    def process(action, *_args)
      send action
    end

    def redirect_to(options = {}, _response_status = {})
      options
    end

    def base_action
      ::SeamlessDatabasePool.read_only_connection_type
    end
  end

  class TestBaseController < TestApplicationController
    include ::SeamlessDatabasePool::ControllerFilter

    use_database_pool read: :persistent

    def read
      ::SeamlessDatabasePool.read_only_connection_type
    end

    def other
      ::SeamlessDatabasePool.read_only_connection_type
    end
  end

  class TestOtherController < TestBaseController
    use_database_pool :all => :random, %i[edit save redirect_master_action] => :master

    def edit
      ::SeamlessDatabasePool.read_only_connection_type
    end

    def save
      ::SeamlessDatabasePool.read_only_connection_type
    end

    def redirect_master_action
      redirect_to(action: :read)
    end

    def redirect_read_action
      redirect_to(action: :read)
    end
  end

  class TestRails2ApplicationController < TestApplicationController
    attr_reader :action_name

    def process(action, *_args)
      @action_name = action
      perform_action
    end

    private

    def perform_action
      send action_name
    end
  end

  class TestRails2BaseController < TestRails2ApplicationController
    include ::SeamlessDatabasePool::ControllerFilter

    use_database_pool read: :persistent

    def read
      ::SeamlessDatabasePool.read_only_connection_type
    end
  end
end

RSpec.describe SeamlessDatabasePool::ControllerFilter do
  let(:session) { {} }
  let(:base_controller_class) { SeamlessDatabasePool::TestBaseController }
  let(:controller_class) { SeamlessDatabasePool::TestOtherController }
  let(:controller) { controller_class.new(session) }

  it 'should work with nothing set' do
    controller = SeamlessDatabasePool::TestApplicationController.new(session)
    expect(controller.process('base_action')).to eq :master
  end

  it 'should allow setting a connection type for a single action' do
    controller = SeamlessDatabasePool::TestBaseController.new(session)
    expect(controller.process('read')).to eq :persistent
    expect(controller.process('other')).to eq :master
  end

  it 'should allow setting a connection type for actions' do
    expect(controller.process('edit')).to eq :master
    expect(controller.process('save')).to eq :master
  end

  it 'should allow setting a connection type for all actions' do
    expect(controller.process('other')).to eq :random
  end

  it "should inherit the superclass' options" do
    expect(controller.process('read')).to eq :persistent
  end

  it 'should be able to force using the master connection on the next request' do
    # First request
    expect(controller.process('read')).to eq :persistent
    controller.use_master_db_connection_on_next_request

    # Second request
    expect(controller.process('read')).to eq :master

    # Third request
    expect(controller.process('read')).to eq :persistent
  end

  context 'when set unknown method' do
    let(:controller_class) do
      Class.new(base_controller_class) do
        use_database_pool({ base_action: :lala_foo })
      end
    end

    it 'raises' do
      # expect(controller.send(:process_action, 'base_action')).to eq :persistent
      expect { controller.send(:process_action, 'base_action') }.to raise_error(/Invalid read pool method/)
    end
  end

  it 'should not break trying to force the master connection if sessions are not enabled' do
    expect(controller.process('read')).to eq :persistent
    controller.use_master_db_connection_on_next_request

    # Second request
    session.clear
    expect(controller.process('read')).to eq :persistent
  end

  it 'should force the master connection on the next request for a redirect in master connection block' do
    controller = SeamlessDatabasePool::TestOtherController.new(session)
    expect(controller.process('redirect_master_action')).to eq({ action: :read })

    expect(controller.process('read')).to eq :master
  end

  it 'should not force the master connection on the next request for a redirect not in master connection block' do
    expect(controller.process('redirect_read_action')).to eq({ action: :read })

    expect(controller.process('read')).to eq :persistent
  end

  it 'should work with a Rails 2 controller' do
    controller = SeamlessDatabasePool::TestRails2BaseController.new(session)
    expect(controller.process('read')).to eq :persistent
  end
end
