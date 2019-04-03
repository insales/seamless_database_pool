module SeamlessDatabasePool
  module LogSubscriber
    def sql(event)
      payload = event.payload
      name = payload[:name]
      return if 'SCHEMA' == name
      connection_name = SeamlessDatabasePool.connection_names[payload[:connection_id]]
      payload[:name] = [connection_name, name].join(' ') if connection_name
      super
    end
  end
end
