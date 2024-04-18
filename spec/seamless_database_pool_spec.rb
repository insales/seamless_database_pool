require 'spec_helper'

describe 'SeamlessDatabasePool' do
  before(:each) do
    SeamlessDatabasePool.clear_read_only_connection
  end

  after(:each) do
    SeamlessDatabasePool.clear_read_only_connection
  end

  it 'should use the master connection by default' do
    connection = double(:connection, master_connection: :master_db_connection, using_master_connection?: false)
    expect(SeamlessDatabasePool.read_only_connection_type).to eq :master
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :master_db_connection
  end

  it 'should be able to set using persistent read connections' do
    connection = double(:connection)
    expect(connection).to receive(:random_read_connection).once.and_return(:read_db_connection)
    allow(connection).to receive(:using_master_connection?).and_return(false)
    SeamlessDatabasePool.use_persistent_read_connection
    expect(SeamlessDatabasePool.read_only_connection_type).to eq :persistent
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
  end

  it 'should be able to set using random read connections' do
    connection = double(:connection)
    expect(connection).to receive(:random_read_connection).and_return(:read_db_connection_1, :read_db_connection_2)
    allow(connection).to receive(:using_master_connection?).and_return(false)
    SeamlessDatabasePool.use_random_read_connection
    expect(SeamlessDatabasePool.read_only_connection_type).to eq :random
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection_1
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection_2
  end

  it 'should use the master connection if the connection is forcing it' do
    connection = double(:connection, master_connection: :master_db_connection)
    expect(connection).to receive(:using_master_connection?).and_return(true)
    SeamlessDatabasePool.use_persistent_read_connection
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :master_db_connection
  end

  it 'should be able to set using the master connection' do
    connection = double(:connection, master_connection: :master_db_connection)
    allow(connection).to receive(:using_master_connection?).and_return(false)
    SeamlessDatabasePool.use_master_connection
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :master_db_connection
  end

  it 'should be able to use persistent read connections within a block' do
    connection = double(:connection, master_connection: :master_db_connection)
    expect(connection).to receive(:random_read_connection).once.and_return(:read_db_connection)
    allow(connection).to receive(:using_master_connection?).and_return(false)
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :master_db_connection
    expect(SeamlessDatabasePool.use_persistent_read_connection do
      expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
      expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
      :test_val
    end).to eq :test_val
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :master_db_connection
  end

  it 'should be able to use random read connections within a block' do
    connection = double(:connection, master_connection: :master_db_connection)
    expect(connection).to receive(:random_read_connection).and_return(:read_db_connection_1, :read_db_connection_2)
    allow(connection).to receive(:using_master_connection?).and_return(false)
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :master_db_connection
    expect(SeamlessDatabasePool.use_random_read_connection do
      expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection_1
      expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection_2
      :test_val
    end).to eq :test_val
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :master_db_connection
  end

  it 'should be able to use the master connection within a block' do
    connection = double(:connection, master_connection: :master_db_connection)
    expect(connection).to receive(:random_read_connection).once.and_return(:read_db_connection)
    allow(connection).to receive(:using_master_connection?).and_return(false)
    SeamlessDatabasePool.use_persistent_read_connection
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
    expect(SeamlessDatabasePool.use_master_connection do
      expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :master_db_connection
      :test_val
    end).to eq :test_val
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
    SeamlessDatabasePool.clear_read_only_connection
  end

  it 'should be able to use connection blocks within connection blocks' do
    connection = double(:connection, master_connection: :master_db_connection)
    allow(connection).to receive(:random_read_connection).and_return(:read_db_connection)
    allow(connection).to receive(:using_master_connection?).and_return(false)
    SeamlessDatabasePool.use_persistent_read_connection do
      expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
      SeamlessDatabasePool.use_master_connection do
        expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :master_db_connection
        SeamlessDatabasePool.use_random_read_connection do
          expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
        end
        expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :master_db_connection
      end
    end
    SeamlessDatabasePool.clear_read_only_connection
  end

  it 'should be able to change the persistent connection' do
    connection = double(:connection)
    allow(connection).to receive(:random_read_connection).and_return(:read_db_connection)
    allow(connection).to receive(:using_master_connection?).and_return(false)

    SeamlessDatabasePool.use_persistent_read_connection
    expect(SeamlessDatabasePool.read_only_connection_type).to eq :persistent
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
    SeamlessDatabasePool.set_persistent_read_connection(connection, :another_db_connection)
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :another_db_connection

    SeamlessDatabasePool.use_random_read_connection
    expect(SeamlessDatabasePool.read_only_connection_type).to eq :random
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
    SeamlessDatabasePool.set_persistent_read_connection(connection, :another_db_connection)
    expect(SeamlessDatabasePool.read_only_connection(connection)).to eq :read_db_connection
  end

  it 'should be able to specify a default read connection type instead of :master' do
    expect(SeamlessDatabasePool.read_only_connection_type).to eq :master
    expect(SeamlessDatabasePool.read_only_connection_type(nil)).to eq nil
  end

  describe 'master_database_configuration' do
    subject(:master_database_configuration) { SeamlessDatabasePool.master_database_configuration(database_config) }
    let(:raw_db_config) do
      YAML.safe_load(<<~YAML)
        development:
          adapter: seamless_database_pool
          pool_adapter: mysql2
          database: dev_db
          username: root
          master:
            host: localhost
            pool_weight: 2
          read_pool:
            host: slavehost
            pool_weight: 5
        test:
          adapter: mysql2
          database: test_db
      YAML
    end
    let(:database_config) { ActiveRecord::DatabaseConfigurations.new(raw_db_config) }

    it 'should pull out the master configurations for compatibility with rake db:* tasks' do
      expect(master_database_configuration).to be_a(ActiveRecord::DatabaseConfigurations)
      expect(master_database_configuration.configurations.size).to eq(2)
      expect(master_database_configuration.configs_for(env_name: 'development').map(&:configuration_hash)).to eq(
        [{
          adapter: 'mysql2',
          database: 'dev_db',
          username: 'root',
          host: 'localhost'
        }]
      )
      expect(master_database_configuration.configs_for(env_name: 'test').map(&:configuration_hash)).to eq(
        [{
          adapter: 'mysql2',
          database: 'test_db'
        }]
      )
    end

    context 'when multiple primary db' do
      let(:raw_db_config) do
        YAML.safe_load(<<~YAML)
          development:
            primary:
              adapter: seamless_database_pool
              pool_adapter: mysql2
              database: dev_db
              username: root
              master:
                host: localhost
                pool_weight: 2
              read_pool:
                host: slavehost
                pool_weight: 5
            shard:
              pool_adapter: mysql2
              database: dev_db_shard
              migrations_paths: 'db/migrate_shards'
              database_tasks: true
              schema_dump: false
            shard_replica:
              pool_adapter: mysql2
              database: dev_db_shard
              replica: true
            with_url:
              adapter: seamless_database_pool
              pool_adapter: mysql2
              master:
                url: mysql2://localhost:1234
          test:
            adapter: mysql2
            database: test_db
        YAML
      end

      it 'should pull out the master configurations for compatibility with rake db:* tasks' do
        expect(master_database_configuration).to be_a(ActiveRecord::DatabaseConfigurations)
        expect(master_database_configuration.configurations.size).to eq(4) # except replica

        expect(master_database_configuration.configs_for(env_name: 'development').map(&:configuration_hash)).to eq(
          [
            {
              adapter: 'mysql2',
              database: 'dev_db',
              username: 'root',
              host: 'localhost'
            },
            {
              pool_adapter: 'mysql2',
              database: 'dev_db_shard',
              migrations_paths: 'db/migrate_shards',
              database_tasks: true,
              schema_dump: false
            },
            {
              adapter: 'mysql2',
              host: 'localhost',
              port: 1234
            }
          ]
        )
        expect(master_database_configuration.configs_for(env_name: 'test').map(&:configuration_hash)).to eq(
          [{
            adapter: 'mysql2',
            database: 'test_db'
          }]
        )
      end
    end
  end
end
