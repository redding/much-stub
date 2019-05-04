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
myclass = Class.new do
  def mymeth; 'meth'; end
  def myval(val); val; end
end
myobj = myclass.new

myobj.mymeth
  # => 'meth'
myobj.myval(123)
  # => 123
myobj.myval(456)
  # => 456

MuchStub.(myobj, :mymeth)
myobj.mymeth
  # => StubError: `mymeth` not stubbed.
MuchStub.(myobj, :mymeth){ 'stub-meth' }
myobj.mymeth
  # => 'stub-meth'
myobj.mymeth(123)
  # => StubError: arity mismatch
MuchStub.(myobj, :mymeth).with(123){ 'stub-meth' }
  # => StubError: arity mismatch
MuchStub.stub_send(myobj, :mymeth) # call to the original method post-stub
  # => 'meth'

MuchStub.(myobj, :myval){ 'stub-meth' }
  # => StubError: arity mismatch
MuchStub.(myobj, :myval).with(123){ |val| val.to_s }
myobj.myval
  # => StubError: arity mismatch
myobj.myval(123)
  # => '123'
myobj.myval(456)
  # => StubError: `myval(456)` not stubbed.
MuchStub.stub_send(myobj, :myval, 123) # call to the original method post-stub
  # => 123
MuchStub.stub_send(myobj, :myval, 456)
  # => 456

MuchStub.unstub(myobj, :mymeth)
MuchStub.unstub(myobj, :myval)

myobj.mymeth
  # => 'meth'
myobj.myval(123)
  # => 123
myobj.myval(456)
  # => 456
```

## Installation

Add this line to your application's Gemfile:

    gem 'much-stub'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install much-stub

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
