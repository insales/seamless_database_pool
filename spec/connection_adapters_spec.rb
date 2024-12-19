# frozen_string_literal: true

require 'spec_helper'
require 'active_record/connection_adapters/read_only_adapter'

describe 'Test connection adapters' do
  if SeamlessDatabasePool::TestModel.database_configs.empty?
    puts 'No adapters specified for testing. Specify the adapters with TEST_ADAPTERS variable'
  else
    SeamlessDatabasePool::TestModel.database_configs.each_key do |adapter|
      context adapter do
        let(:model) { SeamlessDatabasePool::TestModel.db_model(adapter) }
        let(:connection) { model.connection }
        let(:read_connection) { connection.available_read_connections.first }
        let(:master_connection) { connection.master_connection }

        before(:all) do
          ActiveRecord::Base.configurations = { 'test' => { 'adapter' => 'sqlite3', 'database' => ':memory:' } }
          ActiveRecord::Base.establish_connection('adapter' => 'sqlite3', 'database' => ':memory:')
          ActiveRecord::Base.connection
          SeamlessDatabasePool::TestModel.db_model(adapter).create_tables
        end

        after(:all) do
          SeamlessDatabasePool::TestModel.db_model(adapter).drop_tables
          SeamlessDatabasePool::TestModel.db_model(adapter).cleanup_database!
        end

        before(:each) do
          model.create!(name: 'test', value: 1)
          SeamlessDatabasePool.use_persistent_read_connection
        end

        after(:each) do
          model.delete_all
          SeamlessDatabasePool.use_master_connection
        end

        it 'should force the master connection on reload' do
          record = model.first
          expect(SeamlessDatabasePool).not_to receive(:current_read_connection)
          record.reload
        end

        it 'should quote table names properly' do
          expect(connection.quote_table_name('foo')).to eq master_connection.quote_table_name('foo')
        end

        it 'should quote column names properly' do
          expect(connection.quote_column_name('foo')).to eq master_connection.quote_column_name('foo')
        end

        it 'should quote string properly' do
          expect(connection.quote_string('foo')).to eq master_connection.quote_string('foo')
        end

        it 'should quote booleans properly' do
          expect(connection.quoted_true).to eq master_connection.quoted_true
          expect(connection.quoted_false).to eq master_connection.quoted_false
        end

        it 'should quote dates properly' do
          date = Date.today
          time = Time.now
          expect(connection.quoted_date(date)).to eq master_connection.quoted_date(date)
          expect(connection.quoted_date(time)).to eq master_connection.quoted_date(time)
        end

        it 'should query for records' do
          record = model.find_by_name('test')
          expect(record.name).to eq 'test'
        end

        it 'should work with query caching' do
          record_id = model.first.id
          model.cache do
            found = model.find(record_id)
            expect(found.value).to eq 1
            connection.master_connection.update("UPDATE #{model.table_name} SET value = 0 WHERE id = #{record_id}")
            pending "rails 7.1 seems to invalidate cache" if (Rails::VERSION::MAJOR*10 + Rails::VERSION::MINOR) >= 71
            expect(model.find(record_id).value).to eq 1
          end
        end

        it 'should work bust the query cache on update' do
          record_id = model.first.id
          model.cache do
            found = model.find(record_id)
            found.name = 'new value'
            found.save!
            expect(model.find(record_id).name).to eq 'new value'
          end
        end

        context 'read connection' do
          let(:sample_sql) do
            "SELECT #{connection.quote_column_name('name')} FROM #{connection.quote_table_name(model.table_name)}"
          end

          it 'should not include the master connection in the read pool for these tests' do
            expect(connection.available_read_connections).not_to include(master_connection)
            expect(connection.current_read_connection).not_to eq master_connection
          end

          it 'should send select to the read connection' do
            results = connection.send(:select, sample_sql)
            expect(results.to_a).to eq [{ 'name' => 'test' }]
            expect(results.to_a).to eq master_connection.send(:select, sample_sql).to_a
            expect(results).to be_read_only
          end

          it 'should send select_rows to the read connection' do
            results = connection.select_rows(sample_sql)
            expect(results).to eq [['test']]
            expect(results).to eq master_connection.select_rows(sample_sql)
            expect(results).to be_read_only
          end

          it 'should send execute to the read connection' do
            results = connection.execute(sample_sql)
            expect(results).to be_read_only
          end

          it 'should send columns to the read connection' do
            results = connection.columns(model.table_name)
            columns = results.collect(&:name).sort.should
            expect(columns).to eq %w[id name value]
            expect(columns).to eq master_connection.columns(model.table_name).collect(&:name).sort
            expect(results).to be_read_only
          end

          it 'should send tables to the read connection' do
            results = connection.tables
            expect(results).to eq [model.table_name]
            expect(results).to eq master_connection.tables
            expect(results).to be_read_only
          end

          it 'should reconnect dead connections in the read pool' do
            read_connection.disconnect!
            expect(read_connection).not_to be_active
            results = connection.select_all(sample_sql)
            expect(results).to be_read_only
            expect(read_connection).to be_active
          end
        end

        context 'methods not overridden' do
          let(:sample_sql) do
            "SELECT #{connection.quote_column_name('name')} FROM #{connection.quote_table_name(model.table_name)}"
          end

          it 'should use select_all' do
            results = connection.select_all(sample_sql)
            expect(results.to_a).to eq [{ 'name' => 'test' }].to_a
            expect(results.to_a).to eq master_connection.select_all(sample_sql).to_a
          end

          it 'should use select_one' do
            results = connection.select_one(sample_sql)
            expect(results).to eq({ 'name' => 'test' })
            expect(results).to eq master_connection.select_one(sample_sql)
          end

          it 'should use select_values' do
            results = connection.select_values(sample_sql)
            expect(results).to eq ['test']
            expect(results).to eq master_connection.select_values(sample_sql)
          end

          it 'should use select_value' do
            results = connection.select_value(sample_sql)
            expect(results).to eq 'test'
            expect(results).to eq master_connection.select_value(sample_sql)
          end
        end

        context 'master connection' do
          let(:insert_sql) do
            "INSERT INTO #{connection.quote_table_name(model.table_name)} " \
              "(#{connection.quote_column_name('name')}) VALUES ('new')"
          end
          let(:update_sql) do
            "UPDATE #{connection.quote_table_name(model.table_name)} SET #{connection.quote_column_name('value')} = 2"
          end
          let(:delete_sql) { "DELETE FROM #{connection.quote_table_name(model.table_name)}" }

          it 'should blow up if a master connection method is sent to the read only connection' do
            expect { read_connection.update(update_sql)  }.to raise_error(NotImplementedError)
            expect { read_connection.update(insert_sql)  }.to raise_error(NotImplementedError)
            expect { read_connection.update(delete_sql)  }.to raise_error(NotImplementedError)
            expect { read_connection.transaction { nil } }.to raise_error(NotImplementedError)
            expect { read_connection.create_table(:test) }.to raise_error(NotImplementedError)
          end

          it 'should send update to the master connection' do
            connection.update(update_sql)
            expect(model.first.value).to eq 2
          end

          it 'should send insert to the master connection' do
            connection.update(insert_sql)
            expect(model.find_by_name('new')).not_to eq nil
          end

          it 'should send delete to the master connection' do
            connection.update(delete_sql)
            expect(model.first).to eq nil
          end

          it 'should send transaction to the master connection' do
            connection.transaction do
              connection.update(update_sql)
            end
            expect(model.first.value).to eq 2
          end

          it 'should send schema altering statements to the master connection' do
            SeamlessDatabasePool.use_master_connection do
              connection.create_table(:foo) do |t|
                t.string :name
              end
              connection.add_index(:foo, :name)
            ensure
              connection.remove_index(:foo, :name)
              connection.drop_table(:foo)
            end
          end

          it 'should properly dump the schema' do
            with_driver = StringIO.new
            ActiveRecord::SchemaDumper.dump(connection, with_driver)

            without_driver = StringIO.new
            ActiveRecord::SchemaDumper.dump(master_connection, without_driver)

            expect(with_driver.string).to eq without_driver.string
          end

          it 'should allow for database specific types' do
            if adapter == 'postgresql'
              SeamlessDatabasePool.use_master_connection do
                connection.enable_extension 'hstore'
                connection.create_table(:pg) do |t|
                  t.hstore :my_hash
                end
              end
              connection.drop_table(:pg)
            end
          end
        end
      end
    end
  end
end
