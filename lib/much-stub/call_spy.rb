require "much-stub/call"

module MuchStub
  class CallSpy
    METHOD_NAME_REPLACEMENTS = {
      "!" => "_bang",
      "?" => "_predicate"
    }.freeze

    def initialize(**return_values)
      @call_spy_return_values = return_values.transform_keys{ |key| key.to_s }

      @call_spy_method_calls = Hash.new { |hash, key| hash[key] = [] }
      @call_spy_method_return_values =
        Hash.new { |hash, key| hash[key] = call_spy_return_value_proc(key) }
    end

    private

    def call_spy_method_return_value(method_name, much_stub_call)
      @call_spy_method_return_values[method_name.to_s].call(much_stub_call)
    end

    def call_spy_return_value_proc(method_name)
      value = @call_spy_return_values[method_name]
      return value if value.respond_to?(:call)

      ->(*) { value.nil? ? self : value }
    end

    def call_spy_normalize_method_name(name)
      METHOD_NAME_REPLACEMENTS.reduce(name.to_s) { |acc, (source, replacement)|
        acc.gsub(source, replacement)
      }
    end

    def call_spy_define_spied_method(name)
      method_name = call_spy_normalize_method_name(name)
      self.define_singleton_method(name) do |*args, &block|
        call = MuchStub::Call.new(*args, &block)
        @call_spy_method_calls[method_name] << call
        call_spy_method_return_value(name, call)
      end
    end

    def call_spy_define_query_method(query_method_match)
      spied_method_name = query_method_match[1]
      query_method_suffix = query_method_match[2]
      method_name = call_spy_normalize_method_name(spied_method_name)
      self.define_singleton_method("#{method_name}#{query_method_suffix}") do
        yield(method_name) if block_given?
      end
    end

    def method_missing(name, *args, &block)
      if (match = name.match(/(\w+)(_calls)\z/))
        call_spy_define_query_method(match) do |method_name|
          @call_spy_method_calls[method_name]
        end
        self.send(name, *args, &block)
      elsif (match = name.match(/(\w+)(_last_called_with)\z/))
        call_spy_define_query_method(match) do |method_name|
          self.send("#{method_name}_calls").last
        end
        self.send(name, *args, &block)
      elsif (match = name.match(/(\w+)(_called_with)\z/))
        call_spy_define_query_method(match) do |method_name|
          self.send("#{method_name}_last_called_with")
        end
        self.send(name, *args, &block)
      elsif (match = name.match(/(\w+)(_call_count)\z/))
        call_spy_define_query_method(match) do |method_name|
          self.send("#{method_name}_calls").size
        end
        self.send(name, *args, &block)
      elsif (match = name.match(/(\w+)(_called\?)\z/))
        call_spy_define_query_method(match) do |method_name|
          self.send("#{method_name}_call_count") > 0
        end
        self.send(name, *args, &block)
      else
        call_spy_define_spied_method(name)
        self.send(name, *args, &block)
      end
    end

    def respond_to_missing?(*args)
      super
    end
  end
end
