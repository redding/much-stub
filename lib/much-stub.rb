require "much-stub/version"

module MuchStub
  def self.stubs
    @stubs ||= {}
  end

  def self.stub_key(obj, meth)
    MuchStub::Stub.key(obj, meth)
  end

  def self.arity_matches?(method, args)
    return true if method.arity == args.size # mandatory args
    return true if method.arity < 0 && args.size >= (method.arity+1).abs # variable args
    return false
  end

  def self.call(*args, &block)
    self.stub(*args, &block)
  end

  def self.stub(obj, meth, &block)
    key = self.stub_key(obj, meth)
    self.stubs[key] ||= MuchStub::Stub.new(obj, meth, caller_locations)
    self.stubs[key].tap{ |s| s.do = block }
  end

  def self.unstub(obj, meth)
    key = self.stub_key(obj, meth)
    (self.stubs.delete(key) || MuchStub::NullStub.new).teardown
  end

  def self.unstub!
    self.stubs.keys.each{ |key| self.stubs.delete(key).teardown }
  end

  def self.stub_send(obj, meth, *args, &block)
    orig_caller = caller_locations
    stub = self.stubs.fetch(MuchStub::Stub.key(obj, meth)) do
      raise NotStubbedError, "`#{meth}` not stubbed.", orig_caller.map(&:to_s)
    end
    stub.call_method(args, &block)
  end

  def self.tap(obj, meth, &tap_block)
    self.stub(obj, meth) { |*args, &block|
      self.stub_send(obj, meth, *args, &block).tap { |value|
        tap_block.call(value, *args, &block) if tap_block
      }
    }
  end

  class Stub
    def self.key(object, method_name)
      "--#{object.object_id}--#{method_name}--"
    end

    attr_reader :method_name, :name, :ivar_name, :do

    def initialize(object, method_name, orig_caller = nil, &block)
      orig_caller ||= caller_locations
      @metaclass   = class << object; self; end
      @method_name = method_name.to_s
      @name        = "__muchstub_stub__#{object.object_id}_#{@method_name}"
      @ivar_name   = "@__muchstub_stub_#{object.object_id}_" \
                     "#{@method_name.to_sym.object_id}"

      setup(object, orig_caller)

      @do     = block
      @lookup = {}
    end

    def do=(block)
      @do = block || @do
    end

    def call_method(args, &block)
      @method.call(*args, &block)
    end

    def call(args, orig_caller = nil, &block)
      orig_caller ||= caller_locations
      unless MuchStub.arity_matches?(@method, args)
        raise(
          StubArityError.new(
            @method,
            args,
            method_name: @method_name,
            backtrace: orig_caller))
      end
      lookup(args, orig_caller).call(*args, &block)
    rescue NotStubbedError
      @lookup.rehash
      lookup(args, orig_caller).call(*args, &block)
    end

    def with(*args, &block)
      orig_caller = caller_locations
      unless MuchStub.arity_matches?(@method, args)
        raise(
          StubArityError.new(
            @method,
            args,
            method_name: @method_name,
            backtrace: orig_caller))
      end
      @lookup[args] = block
    end

    def teardown
      @metaclass.send(:undef_method, @method_name)
      MuchStub.send(:remove_instance_variable, @ivar_name)
      @metaclass.send(:alias_method, @method_name, @name)
      @metaclass.send(:undef_method, @name)
    end

    def inspect
      "#<#{self.class}:#{"0x0%x" % (object_id << 1)}" \
      " @method_name=#{@method_name.inspect}" \
      ">"
    end

    private

    def setup(object, orig_caller)
      unless object.respond_to?(@method_name)
        msg = "#{object.inspect} does not respond to `#{@method_name}`"
        raise StubError, msg, orig_caller.map(&:to_s)
      end
      is_constant          = object.kind_of?(Module)
      local_object_methods = object.methods(false).map(&:to_s)
      all_object_methods   = object.methods.map(&:to_s)
      if (is_constant && !local_object_methods.include?(@method_name)) ||
         (!is_constant && !all_object_methods.include?(@method_name))
        params_list = ParameterList.new(object, @method_name)
        @metaclass.class_eval <<-method
          def #{@method_name}(#{params_list}); super; end
        method
      end

      if !local_object_methods.include?(@name) # already stubbed
        @metaclass.send(:alias_method, @name, @method_name)
      end
      @method = object.method(@name)

      MuchStub.instance_variable_set(@ivar_name, self)
      @metaclass.class_eval <<-stub_method
        def #{@method_name}(*args, &block)
          MuchStub.instance_variable_get("#{@ivar_name}").call(args, caller_locations, &block)
        end
      stub_method
    end

    def lookup(args, orig_caller)
      @lookup.fetch(args) do
        self.do || begin
          msg = "#{inspect_call(args)} not stubbed."
          inspect_lookup_stubs.tap do |stubs|
            msg += "\nStubs:\n#{stubs}" if !stubs.empty?
          end
          raise NotStubbedError, msg, orig_caller.map(&:to_s)
        end
      end
    end

    def inspect_lookup_stubs
      @lookup.keys.map{ |args| "    - #{inspect_call(args)}" }.join("\n")
    end

    def inspect_call(args)
      "`#{@method_name}(#{args.map(&:inspect).join(",")})`"
    end
  end

  StubError       = Class.new(ArgumentError)
  NotStubbedError = Class.new(StubError)
  StubArityError  =
    Class.new(StubError) do
      def initialize(method, args, method_name:, backtrace:)
        msg = "arity mismatch on `#{method_name}`: " \
              "expected #{number_of_args(method.arity)}, " \
              "called with #{args.size}"

        super(msg)
        set_backtrace(Array(backtrace).map(&:to_s))
      end

      private

      def number_of_args(arity)
        if arity < 0
          "at least #{(arity + 1).abs}"
        else
          arity
        end
      end
    end

  NullStub = Class.new do
    def teardown; end # no-op
  end

  module ParameterList
    LETTERS = ("a".."z").to_a.freeze

    def self.new(object, method_name)
      arity = get_arity(object, method_name)
      params = build_params_from_arity(arity)
      params << "*args" if arity < 0
      params << "&block"
      params.join(", ")
    end

    private

    def self.get_arity(object, method_name)
      object.method(method_name).arity
    rescue NameError
      -1
    end

    def self.build_params_from_arity(arity)
      number = arity < 0 ? (arity + 1).abs : arity
      (0..(number - 1)).map{ |param_index| get_param_name(param_index) }
    end

    def self.get_param_name(param_index)
      param_index += LETTERS.size # avoid getting 0 for the number of letters
      number_of_letters, letter_index = param_index.divmod(LETTERS.size)
      LETTERS[letter_index] * number_of_letters
    end
  end
end

# Kernel#caller_locations polyfill for pre ruby 2.0.0
if RUBY_VERSION =~ /\A1\..+/ && !Kernel.respond_to?(:caller_locations)
  module Kernel
    def caller_locations(start = 1, length = nil)
      length ? caller[start, length] : caller[start..-1]
    end
  end
end
