require 'spec_helper'

module SeamlessDatabasePool
  class ConnectionStatisticsTester
    def insert(sql, name = nil)
      "INSERT #{sql}/#{name}"
    end

    def update(sql, name = nil)
      execute(sql)
      "UPDATE #{sql}/#{name}"
    end

    def execute(sql, name = nil)
      "EXECUTE #{sql}/#{name}"
    end

    protected

    def select(sql, name = nil, _binds = [])
      "SELECT #{sql}/#{name}"
    end

    prepend ::SeamlessDatabasePool::ConnectionStatistics
  end
end

describe SeamlessDatabasePool::ConnectionStatistics do
  it 'should increment statistics on update' do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    expect(connection.update('SQL', 'name')).to eq 'UPDATE SQL/name'
    expect(connection.connection_statistics).to eq({ update: 1 })
    expect(connection.update('SQL 2')).to eq 'UPDATE SQL 2/'
    expect(connection.connection_statistics).to eq({ update: 2 })
  end

  it 'should increment statistics on insert' do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    expect(connection.insert('SQL', 'name')).to eq 'INSERT SQL/name'
    expect(connection.connection_statistics).to eq({ insert: 1 })
    expect(connection.insert('SQL 2')).to eq 'INSERT SQL 2/'
    expect(connection.connection_statistics).to eq({ insert: 2 })
  end

  it 'should increment statistics on execute' do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    expect(connection.execute('SQL', 'name')).to eq 'EXECUTE SQL/name'
    expect(connection.connection_statistics).to eq({ execute: 1 })
    expect(connection.execute('SQL 2')).to eq 'EXECUTE SQL 2/'
    expect(connection.connection_statistics).to eq({ execute: 2 })
  end

  it 'should increment statistics on select' do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    expect(connection.send(:select, 'SQL', 'name')).to eq 'SELECT SQL/name'
    expect(connection.connection_statistics).to eq({ select: 1 })
    expect(connection.send(:select, 'SQL 2')).to eq 'SELECT SQL 2/'
    expect(connection.connection_statistics).to eq({ select: 2 })
  end

  it 'should increment counts only once within a block' do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    expect(connection).to receive(:execute).with('SQL')
    connection.update('SQL')
    expect(connection.connection_statistics).to eq({ update: 1 })
  end

  it 'should be able to clear the statistics' do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    connection.update('SQL')
    expect(connection.connection_statistics).to eq({ update: 1 })
    connection.reset_connection_statistics
    expect(connection.connection_statistics).to eq({})
  end
end
