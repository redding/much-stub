# MuchStub

MuchStub is a stubbing API for replacing method calls on objects in test runs.  This is intended to be brought into testing environments and used in test runs to stub out external dependencies.

All it does is replace method calls.  In general it tries to be friendly and complain if stubbing doesn't match up with the object/method being stubbed:

* each stub takes a block that is called in place of the method
* complains if you stub a method that the object doesn't respond to
* complains if you stub with an arity mismatch
* no methods are added to `Object` to support stubbing

Note: this was originally implemented in and extracted from [Assert](https://github.com/redding/assert).

## Usage

```ruby
# Given this object/API

my_class = Class.new do
  def my_method
    "my-method"
  end

  def my_value(value)
    value
  end
end
my_object = my_class.new

my_object.my_method
  # => "my-method"
my_object.my_value(123)
  # => 123
my_object.my_value(456)
  # => 456

# Create a new stub for the :my_method method

MuchStub.(my_object, :my_method)
my_object.my_method
  # => StubError: `my_method` not stubbed.
MuchStub.(my_object, :my_method){ "stubbed-method" }
my_object.my_method
  # => "stubbed-method"
my_object.my_method(123)
  # => StubError: arity mismatch
MuchStub.(my_object, :my_method).with(123){ "stubbed-method" }
  # => StubError: arity mismatch

# Call the original method after it has been stubbed.

MuchStub.stub_send(my_object, :my_method)
  # => "my-method"

# Create a new stub for the :my_value method

MuchStub.(my_object, :my_value){ "stubbed-method" }
  # => StubError: arity mismatch
MuchStub.(my_object, :my_value).with(123){ |val| val.to_s }
my_object.my_value
  # => StubError: arity mismatch
my_object.my_value(123)
  # => "123"
my_object.my_value(456)
  # => StubError: `my_value(456)` not stubbed.

# Call the original method after it has been stubbed.

MuchStub.stub_send(my_object, :my_value, 123)
  # => 123
MuchStub.stub_send(my_object, :my_value, 456)
  # => 456

# Unstub individual stubs

MuchStub.unstub(my_object, :my_method)
MuchStub.unstub(my_object, :my_value)

# OR blanket unstub all stubs

MuchStub.unstub!

# The original API/behavior is preserved after unstubbing

my_object.my_method
  # => "my-method"
my_object.my_value(123)
  # => 123
my_object.my_value(456)
  # => 456
```

### Stubs for spying

```ruby
# Given this object/API

my_class = Class.new do
  def basic_method(value)
    value
  end

  def iterator_method(items, &block)
    items.each(&block)
  end
end
my_object = my_class.new

# Store method call arguments/blocks for spying.

basic_method_called_with = nil
MuchStub.(my_object, :basic_method) { |*args|
  basic_method_called_with = args
}

my_object.basic_method(123)
basic_method_called_with
  # => [123]

iterator_method_call_args = nil
iterator_method_call_block = nil
MuchStub.(my_object, :iterator_method) { |*args, &block|
  iterator_method_call_args = args
  iterator_method_call_block = block
}

my_object.iterator_method([1, 2, 3], &:to_s)
iterator_method_call_args
  # => [[1, 2, 3]]
iterator_method_call_block
  # => #<Proc:0x00007fb083a6feb0(&:to_s)>

# Count method calls for spying.

basic_method_call_count = 0
MuchStub.(my_object, :basic_method) {
  basic_method_call_count += 1
}

my_object.basic_method(123)
basic_method_call_count
  # => 1

# Count method calls and store arguments for spying.

basic_method_calls = []
MuchStub.(my_object, :basic_method) { |*args|
  basic_method_calls << args
}

my_object.basic_method(123)
basic_method_calls.size
  # => 1
basic_method_calls.first
  # => [123]
```

### Stubs for test doubles.

```ruby
# Given this object/API ...

my_class = Class.new do
  def build_thing(thing_value);
    Thing.new(value)
  end
end
my_object = my_class.new

# ... and this Test Double.
class FakeThing
  attr_reader :built_with

  def initialize(*args)
    @built_with = args
  end
end

# Stub in the test double.

MuchStub.(my_object, :build_thing) { |*args|
  FakeThing.new(*args)
}

thing = my_object.build_thing(123)
thing.built_with
  # => [123]
```

## Installation

Add this line to your application's Gemfile:

    gem "much-stub"

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install much-stub

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am "Added some feature"`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
